# SDRangel `RemoteTCPInput` pivot plan

Status: active. Supersedes the network/protocol section of
[`ebaz4205-sdr-plan-v2.md`](ebaz4205-sdr-plan-v2.md). RemoteInput
(UDP + cm256 super-frames + HTTP REST) is abandoned; we serve a
single TCP socket compatible with SDRangel's `RemoteTCPInput` plugin.
TX path is deferred until RX is solid.

## Why the pivot

`RemoteInput` requires correct cm256 FEC, 512-byte super-frame
assembly, frame-index reordering, and an out-of-band HTTP REST
control channel. After exhausting bring-up, RX never produced a
clean spectrum in SDRangel. `RemoteTCPInput` collapses all of that
into one TCP stream with in-band control — TCP gives reliability
for free, the wire format is a flat int16 I/Q stream, and commands
are 5-byte fixed-width packets. At our post-DDC rates (≤ 8 MB/s for
2 MS/s int16 I/Q) TCP capacity is a non-issue on 100M Ethernet.

## Wire protocol (server = firmware, client = SDRangel)

**Greeting on accept (12 bytes, big-endian):**
```
"RTL0"                      // magic
uint32  tuner_type          // 5 (R820T placeholder)
uint32  tuner_gain_count    // 0
```

**Optional `SDRA` extended header right after** so 16-bit I/Q is
advertised natively rather than masquerading as 8-bit RTL. Exact
byte layout must be cross-checked against
`RemoteTCPInputTCPHandler.cpp` in the SDRangel build the user runs
(field set has churned across versions). At minimum:
```
"SDRA"                      // magic
uint32  protocol_revision
uint64  center_freq_hz
uint32  sample_rate_hz
uint8   sample_bits         // 16
uint8   sample_bytes_per_iq // 4
... (remaining fields per RemoteTCPInputTCPHandler::MetaData)
```

**Sample stream (forever after greeting):** raw little-endian
`int16 I, int16 Q, int16 I, int16 Q, ...`. No framing.

**Client → server commands (5 bytes each, lock-step):**
```
uint8   cmd
uint32  param   (big-endian)
```
Honoured commands:
- `0x01` set freq Hz → `sdr_set_frequency(param)`
- `0x02` set sample rate Hz → map to nearest decim (15/30/60/120) → `sdr_set_rate()`

All other commands: read & discard.

## File-by-file disposition

**Add:**
- `firmware/src/network/sdra_tcp_server.{c,h}` — listen on :1234,
  accept one client, send greeting, run sample-pump + command-poll
  loop, drop client on error and re-accept.

**Rewrite or fold:**
- `firmware/src/tasks/rx_task.c` — strip super-frame builder.
  Preferred: fold the DMA→TCP pump into `sdra_tcp_server.c` and
  delete `rx_task.{c,h}` outright (no separate framing layer
  remains, the task *is* the protocol).
- `firmware/src/main.c` — drop `rx_task_set_dest`, `tx_task_start`,
  `http_rest_start`. Replace with `sdra_tcp_start(1234)`.

**Delete (RemoteInput-era, all dead under the new design):**
- `firmware/src/network/udp_tx.{c,h}`
- `firmware/src/network/udp_rx.{c,h}`
- `firmware/src/network/http_rest.{c,h}` — settings travel in-band
  on the TCP socket; no HTTP server needed.
- `firmware/src/protocol/sdrangel_frame.{c,h}` — superframe + meta
  + CRC32 are RemoteInput-specific.
- `firmware/src/protocol/cm256.{c,h}` — TCP makes FEC redundant.
- `firmware/src/protocol/iq_convert.{c,h}` — DMA produces
  `{Q[15:0], I[15:0]}` 32-bit beats; `netconn_write` ships them
  directly (with at most a byte-swap if endianness mismatches).
- `firmware/src/tasks/tx_task.{c,h}` — TX deferred, delete now and
  rebuild later (RemoteTCPSink, or a TX command on the same socket).

**Keep untouched:**
- `firmware/src/network/net_init.{c,h}` — lwIP/IP101G bring-up was
  the hard part; do not re-litigate.
- `firmware/src/platform/` — DMA, `ddc_ctrl`, etc. already tested.
- All RTL.

**Obsolete docs/tools to delete:**
- `docs/sdrangel_protocol.md` — RemoteInput superframe notes.
- `docs/debug.md` — verify before deletion.
- `docs/NEXT_STEPS.md` — written against the old plan.
- `docs/REVIEW.md` — end-of-iteration summary, lives in git history.
- `docs/ebaz4205-sdr-plan.md` — v1, already superseded.
- `tools/test_udp_rx.py`, `tools/test_udp_tx.py` — replace with one
  `tools/test_tcp_rx.py` that connects to :1234, parses the greeting,
  dumps int16 I/Q to file, and optionally sends a `set_freq` command.

**Keep:** datasheet PDFs, `docs/EBAZ4205-ADC-DAC.md`,
`docs/Project Target.txt`. Trim `docs/PROGRESS.md` of RemoteInput
entries or append a "pivot to TCP" note.

`docs/ebaz4205-sdr-plan-v2.md` needs its network/protocol section
edited to point at this file (or replaced by a v3 once the pivot
lands).

`CLAUDE.md` software-stack and architecture sections also describe
`rx_task → cm256 → UDP TX` and `http_task` REST — both gone.
Update on landing.

## Incremental milestones

1. **Strip first.** Delete the obsolete `.c/.h/.md` files and remove
   their includes/callers from `main.c`. Build should fail cleanly
   with "missing `sdra_tcp_start`" — that's the green light.
2. **Skeleton TCP server.** Listen on :1234, accept, send 12-byte
   `RTL0` greeting, hold the socket open writing zero-valued int16
   I/Q at a fixed rate. Verify SDRangel's RemoteTCPInput connects,
   sees the magic, and shows a flat baseband.
3. **Wire the DMA.** Replace the zero-pump with `ebaz_dma_wait →
   netconn_write(buf, EBAZ_DMA_BUF_BYTES, NETCONN_COPY) →
   ebaz_dma_swap → ebaz_dma_start`. Verify live noise/signal.
4. **Add SDRA extended header** so 16-bit native is advertised
   correctly. Cross-check field layout against the running
   SDRangel build before coding.
5. **Add command parsing.** `netconn_set_recvtimeout(0)` for
   non-blocking peek between writes; route `0x01` and `0x02` to
   `sdr_set_frequency` / `sdr_set_rate`.
6. **Then** decide TX. Easiest: opposite direction on the same
   socket with a tiny header marking start of sample stream, or a
   second listener for `RemoteTCPSink`. Defer until RX is solid.

Each step is its own reviewable commit.

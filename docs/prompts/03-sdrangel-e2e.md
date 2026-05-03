# Step 3 — Real SDRAngel end-to-end test

You're picking up `ebaz4205-sdr` (see `CLAUDE.md`). DMA RX should be
working (step 1 cleared the timeout), MDIO works (step 2). The wire
format implementation has never been validated against real SDRAngel —
do that now.

## Known starting state (after step 1 hardware verify, 2026-05-03)

Once the DMA timeout cleared, `rx_task` started looping through buffers
and `[udp_tx] send err=-4` (lwIP `ERR_RTE`) fires every iteration when
no host is listening on `192.168.1.10:9090` and/or the netif is still
coming up. Expected — you'll quiet it by pointing a real host at the
firmware (via `tools/test_udp_rx.py` or SDRAngel). If the error
persists *after* a host is listening and `[net] up:` was logged, that's
a real bug — investigate `udp_tx_open` / `netconn_sendto` in
`firmware/src/network/udp_tx.c`.

## Read first

1. `CLAUDE.md`
2. `docs/sdrangel_protocol.md` — our derivation of SDRAngel's
   "Remote Output / Remote Input" wire format
3. `firmware/src/protocol/sdrangel_frame.{c,h}` — the wire structs
4. `firmware/src/tasks/rx_task.c`, `tx_task.c` — the producers/consumers
5. `tools/test_udp_rx.py`, `test_udp_tx.py` — host-side helpers

## What to do

### 1. Loopback first (no RF needed)

On the same Linux PC as the EBAZ:

```bash
python3 tools/test_udp_rx.py        # listens for super-blocks from EBAZ
```

Default firmware destination is `192.168.1.10:9090` — adjust either
`tools/test_udp_rx.py` or the firmware's `rx_task_set_dest()` call in
`firmware/src/main.c` so they match. With ADC inputs grounded the
EBAZ should send a stream of zeros (or DC offset) to the host. The
script verifies the meta CRC on each block — if CRC fails, the wire
struct layout is wrong; iterate on `sdrangel_frame.{c,h}`.

### 2. Real SDRAngel

Install SDRAngel on the host. Add a "Remote Input" device with the
EBAZ's source IP/port. Confirm baseband appears in the spectrum
display. Without an antenna you'll see noise; with a known signal
generator on the ADC you should see it at DC ± fc.

Common issues to watch for:
- **Endianness** of multi-byte fields — SDRAngel may expect LE/BE
  differently than we pack
- **CRC polynomial** mismatch
- **`nb_fec_blocks`** must be 0 (we have a stub FEC; see step 5)

### 3. TX path

Add a "Remote Output" device in SDRAngel pointed at the EBAZ's
listening port. Generate a signal in SDRAngel and verify it comes
out of the DAC.

## Build & verify

Mostly Python + SDRAngel; firmware changes only if wire format is
wrong. Use `firmware/scripts/vitis_rebuild.tcl` for incremental
relinking, then `bootgen` + new SD card.

When done: commit findings + any wire-format fixes; mark row 3 ✅
in `docs/NEXT_STEPS.md`. If you fix protocol issues, also update
`docs/sdrangel_protocol.md`.

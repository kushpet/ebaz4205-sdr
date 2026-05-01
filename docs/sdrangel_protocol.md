# SDRAngel "Remote" UDP wire format (as implemented by this firmware)

Authoritative source: [`sdrbase/channel/remotedatablock.h`](https://github.com/f4exb/sdrangel/blob/master/sdrbase/channel/remotedatablock.h)
in [f4exb/sdrangel](https://github.com/f4exb/sdrangel). Verified against
`plugins/channelrx/remotesink/remotesinksender.cpp` and
`plugins/channeltx/remotesource/remotesourceworker.cpp`.

## Datagram

One UDP packet = one **super-block**. Always **512 bytes** (no padding,
no length prefix). Sent unicast over UDP.

```
+------------------+------------------------------------+
| 8-byte header    |       504-byte payload             |
+------------------+------------------------------------+
```

Default port: **9090**.

## Header (8 B, little-endian, packed)

| Off | Width | Field         | Notes |
|-----|-------|---------------|-------|
| 0   | u16   | frame_index   | wraps mod 65536; same for all blocks of one super-frame |
| 2   | u8    | block_index   | 0=meta, 1..127=IQ, 128..255=FEC parity |
| 3   | u8    | sample_bytes  | 2 or 4 |
| 4   | u8    | sample_bits   | 8/16/24 |
| 5   | u8    | filler        | 0 |
| 6   | u16   | filler2       | 0 |

Re-assembly is by `(frame_index, block_index)` — there is no SoF marker
or sample counter.

## Super-frame

128 "original" blocks per frame:

| block_index | Content |
|-------------|---------|
| 0           | `RemoteMetaDataFEC` (30 B + zero pad) |
| 1..127      | IQ samples |

Followed by **N parity blocks** (block_index 128..127+N) where N =
`nb_fec_blocks` from the meta record. CM256 parameters: `OriginalCount=128`,
`RecoveryCount=N`, `BlockBytes=504`.

## Metadata payload (block 0, first 30 B; rest zero)

| Off | Width | Field                    |
|-----|-------|--------------------------|
| 0   | u64   | center_frequency_hz      |
| 8   | u32   | sample_rate (Hz)         |
| 12  | u8    | sample_bytes             |
| 13  | u8    | sample_bits              |
| 14  | u8    | nb_original_blocks (=128)|
| 15  | u8    | nb_fec_blocks            |
| 16  | u8    | device_index             |
| 17  | u8    | channel_index            |
| 18  | u32   | tv_sec                   |
| 22  | u32   | tv_usec                  |
| 26  | u32   | crc32 (over bytes 0..25) |

CRC: standard reflected CRC-32 (poly `0xEDB88320`, init `0xFFFFFFFF`,
xorout `0xFFFFFFFF`) — same as zlib / boost.

## IQ payload

Interleaved little-endian `int16` `I,Q,I,Q,...`. With sample_bytes=2 and
sample_bits=16, one block carries `504 / 4 = 126` complex samples.

## Notes for this firmware

- Both `Remote Input` (device→host) and `Remote Output` (host→device) use
  the same on-wire structures. The difference is only direction.
- Default `nb_fec_blocks = 0` (no FEC) — turn it on once UDP is verified
  end-to-end. cm256 recovery time is non-trivial on a Cortex-A9.
- Sample-rate ↔ decimation correspondence (R is the CIC decimation):

  | R   | sample_rate (Hz, post HB-FIR ÷2) |
  |-----|----------------------------------|
  | 30  | 1_000_000                        |
  | 60  |   500_000                        |
  | 120 |   250_000                        |

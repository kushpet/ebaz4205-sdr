# Bring-up and debug checklist

A pragmatic order to follow the first time you flash the bitstream and
boot the firmware. Each step should be passed before moving on.

## 0. Pre-flight

- [ ] Vivado 2022.2 / Vitis 2022.2 installed.
- [ ] EBAZ4205 powered (12 V), JTAG cable connected.
- [ ] AD9226 add-on board on DATA3, DAC904 add-on board on DATA1+DATA2.
- [ ] Ethernet cable from EBAZ4205 to host (or switch). Host has a route
      to `192.168.1.100/24` (or you change `EBAZ_IP4_ADDR` in
      `firmware/src/network/net_init.h`).

## 1. UART comes up

Boot the firmware over JTAG. UART0 on the EBAZ4205 is exposed on the
USB-UART of the dev board (115200 8N1).

Expected first output:

```
====================================================
  EBAZ4205 SDR firmware (bare-metal + FreeRTOS)
  ...
  DDC base: 0x43C00000   DUC base: 0x43C01000
====================================================
[net] up: 192.168.1.100/255.255.255.0 gw=192.168.1.1
[ip101g] PHYID = 0243:c8a0    ; or similar IC+ ID
[ip101g] BMSR = ... LINK_UP
[dma] init OK; rx=...
[boot] SDR firmware ready
[http] listening on :8888
```

If UART is silent: **ILA / debug bridge not the issue here** — check the
BD's PS UART0 MIO mapping (14/15) and the FSBL.

If `[ip101g] reset timeout`: pin U18 (PHY refclk) probably isn't getting
25 MHz. Use a scope on U18; if dead, the MMCM's `clk_25mhz` isn't
reaching the pad — verify XDC, MMCM placement, and `make_bd_pins_external`.

## 2. Network reachable

```
host$ ping 192.168.1.100      # answers within ~1 ms
host$ curl http://192.168.1.100:8888/sdrangel
{"name":"EBAZ4205","version":"1.0","streamRate":1000000,...}
```

If ping fails: link is up (LED on RJ-45 lit?), but ARP/IP isn't. Check
`sys_thread_new("xemacif_input"...)` is actually starting (UART log).
Wireshark for ARP requests from the host that go unanswered ⇒ MAC
doesn't reply ⇒ GEM0 RX not working ⇒ MII clocks wrong (very often
PHY refclk again).

## 3. UDP datapath, no DSP

Set the firmware to send a simple counter pattern (debug build): swap
`iq_copy_dma_to_wire` for a routine that writes I=k, Q=-k. Verify on the
host:

```
host$ ./tools/test_udp_rx.py --port 9090 --frames 8
[meta] frame=0 fc=7.100 MHz fs=1000000 bytes=2 bits=16 nbo=128 nbf=0
  rx 1000 blocks (500.0 KiB, 4.00 Mbit/s)
```

If you see CRC failures on meta: the host and device disagree on the
struct layout — re-check `sdrangel_frame.h` against
`docs/sdrangel_protocol.md`.

## 4. Real DSP path

Drive a clean tone into the AD9226 (e.g. an HP signal generator at
7.0 MHz, −20 dBm). Set the device:

```
curl -X PATCH http://192.168.1.100:8888/sdrangel/deviceset/0/device/settings \
     -d '{"centerFrequency":7000000,"log2Decim":5}'
```

(`log2Decim=5` ⇒ R=32, post-HB rate ≈ 938 kS/s)

```
host$ ./tools/test_udp_rx.py --port 9090 --out tone.s16 --frames 100
host$ python3 -c "
import numpy as np, sys
x = np.fromfile('tone.s16', '<i2').astype(np.float32).view(np.complex64)
import scipy.signal as sp
f, p = sp.welch(x, 1e6, nperseg=2048)
import matplotlib.pyplot as plt
plt.semilogy(f, p); plt.show()"
```

Expect a single tone at ≈ 0 Hz (since fc was tuned to 7.0 MHz). If the
tone shows at +fs/4 instead of 0 → NCO frequency word miscalculation.

## 5. SDRAngel end-to-end

In SDRAngel:

1. **Remote Source** device → set `Address: 192.168.1.100`, `Port: 9090`.
2. Add a Remote Output channel, point it at the EBAZ port for the
   transmit path.
3. Verify spectrum / waterfall.

## Common failure modes

| Symptom | First thing to check |
|---|---|
| No `[net] up` line | GIC init failed; PS interrupt config in BD |
| `xemac_add failed` | MAC base address mismatch with `XPAR_XEMACPS_0_BASEADDR` |
| ARP works but UDP silent | lwIP `tcpip_thread` not running (priority too low?) |
| UDP works but waveform wrong | DMA buffer marked cacheable — recheck `Xil_SetTlbAttributes` on `EBAZ_DMA_REGION_BASE` |
| Spectrum mirrored | `complex_mixer.v` Q-sign caveat (CLAUDE.md) |
| Frequent gaps in spectrum | RX-side UDP socket buffer too small on the host (`sysctl net.core.rmem_max`) |
| `[udp_tx] send err=-11` (`ERR_WOULDBLOCK`) | lwIP MEM_SIZE or PBUF_POOL_SIZE too small |

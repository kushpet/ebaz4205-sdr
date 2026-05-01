# Iteration review — what was actually done

This pass closed Phase 1 and brought Phase 2 + Phase 3 to a working
first-cut. None of the new code has been built or simulated yet — the
review here is structural ("does it compile, link, and route?") not
behavioural ("does the radio decode SSB?"). Validation belongs to a
follow-up pass on real silicon, with the steps in `docs/debug.md`.

## Starting point (before this pass)

Everything from the v2 plan up to and including 1.11 was already in
the tree (see `git log`):

- XDC, project + build Tcl, MMCM, ADC/DAC interfaces.
- NCO + complex mixer, CIC, halfband FIR.
- DDC/DUC top modules + Block-Design Tcl.
- Plans (`docs/ebaz4205-sdr-plan.md` / `-v2.md`) describing the rest.

Missing: 1.12 toplevel, all of Phase 2 (firmware), all of Phase 3
(tooling/debug).

## What I added

### 1. Project hygiene
- `CLAUDE.md` — project overview, hardware constants, RTL/firmware
  conventions, address map, build commands, known caveats.
- `docs/PROGRESS.md` — task-by-task status against the v2 plan.

### 2. FPGA closure (Phase 1)
- `hardware/rtl/sdr_top.v` — toplevel: ODDR-driven `CLK_ADC`, LED
  status, BD-wrapper instantiation.
- `hardware/scripts/create_bd.tcl` — **rewrote** to embed the MMCM
  inside the BD, split clock domains (100 MHz AXI fabric, 60 MHz DSP),
  expose external pins for `clk_60mhz`, `clk_25mhz`, `mmcm_locked`,
  PS reset, plus the existing ADC/DAC pins.
- `hardware/constraints/ebaz4205.xdc` — added `PHY_REFCLK_25MHZ` →
  U18 and an explicit comment block for generated clocks.

### 3. Firmware (Phase 2)
- `firmware/lscript.ld` — DDR layout reserving 0x0800_0000.. for the
  non-cached DMA region.
- `firmware/src/platform/platform_init.{c,h}` — caches, MMU
  attributes, banner; defines address-map symbols and IRQ IDs.
- `firmware/src/platform/ip101g.{c,h}` — MDIO bring-up: soft-reset,
  PHYID readback, ANAR for 100BASE-TX FD/HD, restart auto-neg.
- `firmware/src/platform/axi_dma.{c,h}` — XAxiDma wrapper, ping-pong
  buffers from the non-cached region, ISR↔FreeRTOS semaphore.
- `firmware/src/platform/ddc_ctrl.{c,h}` — typed accessors for the
  DDC/DUC AXI-Lite registers; `ebaz_freq_to_word` for the NCO.
- `firmware/src/network/net_init.{c,h}` — GIC + lwIP TCPIP thread +
  GEM0 attach (`xemac_add`) + IP101G init.
- `firmware/src/network/{udp_tx,udp_rx}.{c,h}` — NETCONN-based
  blocking UDP, designed around 512-byte super-blocks.
- `firmware/src/network/http_rest.{c,h}` — minimal HTTP/1.0 server
  on port 8888 with three endpoints (`GET /sdrangel`,
  `GET /sdrangel/.../device/run`,
  `PATCH /sdrangel/.../device/settings`). Settings parser hand-rolled,
  no JSON library dependency.
- `firmware/src/protocol/sdrangel_frame.{c,h}` — packed C structs for
  the SDRAngel "Remote" wire format derived from
  `sdrbase/channel/remotedatablock.h` upstream; CRC-32 over the meta
  payload; helpers to fill meta/IQ headers.
- `firmware/src/protocol/cm256.{c,h}` — façade with the right API but
  a no-FEC pass-through implementation. Documented swap-in path.
- `firmware/src/protocol/iq_convert.{c,h}` — DMA↔wire helpers (memcpy
  with optional Q15 gain).
- `firmware/src/tasks/rx_task.{c,h}` — DMA-driven IQ producer that
  builds super-frames and pushes blocks via `udp_tx`.
- `firmware/src/tasks/tx_task.{c,h}` — UDP consumer that reassembles
  super-frames by `frame_index` and pushes IQ to the DUC DMA buffer.
- `firmware/src/main.c` — boot task: net→DMA→workers, then exits.

### 4. Tooling (Phase 3)
- `tools/test_udp_rx.py` — host-side super-block parser; verifies the
  meta CRC, dumps IQ to a `.s16` file.
- `tools/test_udp_tx.py` — host-side super-frame generator; reads a
  `.s16` IQ file and feeds the EBAZ at the configured rate.
- `docs/sdrangel_protocol.md` — written-down wire format with
  upstream citations (the agent that researched it cited specific
  files and line ranges in `f4exb/sdrangel`).
- `docs/debug.md` — bring-up checklist with expected UART output,
  ping/curl probes, scope/Wireshark tips, common failure modes.

## Validation status

| Layer | Built? | Simulated? | Run on real HW? |
|---|---|---|---|
| RTL (Phase 1) | Existing modules had test-benches; new `sdr_top.v` and updated `create_bd.tcl` not yet run | Existing `tb_*` only | No |
| Firmware (Phase 2) | Not built — no Vitis BSP in the repo | n/a | No |
| PC tools (Phase 3) | `python3 -m py_compile` would catch syntax; not run end-to-end | n/a | No |

So the explicit honest answer to "what was actually done": all the
files the plan asked for now exist with substantive implementations
that match the contracts CLAUDE.md/PROGRESS.md describe, and the
project is ready for a Vivado build run. Nothing has been *executed*
in this iteration — that's the next one.

## Suggested next iteration

1. `vivado -mode batch -source create_project.tcl` then
   `-source create_bd.tcl` then `-source build.tcl`. Address any
   synth/impl warnings (likely: the `disconnect_bd_net` removal in
   `create_bd.tcl` should already be clean, but PHY refclk routing
   might need a `set_property CLOCK_DEDICATED_ROUTE FALSE`).
2. Export `.xsa`, create a Vitis platform, generate FreeRTOS BSP with
   `lwip213` enabled (set `api_mode=SOCKET_API` is **not** what we
   use — we use NETCONN, which lwIP enables by default with FreeRTOS).
3. Build the firmware app, run on hardware, walk through `docs/debug.md`.
4. Once UDP works end-to-end without FEC, drop the catid/cm256 sources
   into `firmware/third_party/cm256/` and replace `cm256.c`. Adjust
   the meta block to advertise `nb_fec_blocks > 0`.
5. Resolve the `complex_mixer.v` Q-sign mirror.

## Caveats that future me should remember

- The new `create_bd.tcl` re-creates the BD from scratch each run.
  Don't hand-edit the generated `system.bd` and expect it to survive.
- The DDC/DUC sit on a 60 MHz AXI-Lite slave; the AXI Interconnect
  bridges the 100/60 MHz domain. Burst-y register pokes are fine, but
  any large polling loop should target the DMA registers (100 MHz
  side) rather than the DDC/DUC.
- DMA buffers are 64 KB × 2 ping-pong, 4 buffers total = 256 KB out
  of the 128 MB non-cached region. Plenty of headroom to grow if the
  RX-path UDP send rate becomes the bottleneck.
- `g_center_frequency_hz` and `g_dec_rate` in `http_rest.c` are
  shared with `rx_task.c`. They are not protected by a mutex — single
  word writes are atomic on Cortex-A9 so this is benign for now, but
  if more state shows up here introduce a lightweight FreeRTOS guard.

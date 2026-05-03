# CLAUDE.md — EBAZ4205 SDR

## Project goal

Software-defined radio transceiver on EBAZ4205 (Zynq-7010) board with
add-on AD9226 ADC and DAC904 DAC, controlled remotely by **SDRAngel**
(`Remote Input` / `Remote Output` plugins) over Ethernet (IP101G PHY).

**Target sample rate** at the ADC/DAC: 60 MHz. Streamed to host after
on-FPGA DDC/DUC (decimation 30..120 ⇒ 0.25..2 MS/s I/Q).

Source plans: [`docs/ebaz4205-sdr-plan.md`](docs/ebaz4205-sdr-plan.md),
[`docs/ebaz4205-sdr-plan-v2.md`](docs/ebaz4205-sdr-plan-v2.md) (the v2
plan with DDC/DUC supersedes v1).

## Top-level architecture

```
        ┌──────────────────────── PL (FPGA, 60 MHz) ───────────────────────┐
ADC ───▶│ adc_if ─▶ NCO+mixer ─▶ CIC dec ÷R ─▶ HB FIR ÷2 ─▶ AXI-Stream I/Q│─▶ DMA S2MM ──▶ DDR
        │                                                                   │
DAC ◀───│ dac_if ◀─ NCO+mixer ◀─ CIC int ×R ◀─ HB FIR ×2 ◀─ AXI-Stream I/Q│◀─ DMA MM2S ◀── DDR
        └────────────────────────────────────────────────────────────────────┘
                                     ▲
                                AXI-Lite (regs)
                                     │
              ┌──────────────── PS (Cortex-A9, bare metal + FreeRTOS) ────────────────┐
              │  GEM0 (MII) ─ lwIP ─ UDP TX (RX-path) ─┐                              │
              │                       UDP RX (TX-path) ┤── SDRAngel superframe (cm256)│
              │                       HTTP REST :8888  ┘                              │
              └──────────────────────────────────────────────────────────────────────┘
```

## Hardware constants

| Item | Value | Source |
|---|---|---|
| FPGA part | `xc7z010clg400-1` | EBAZ4205 |
| PS clock to PL | FCLK_CLK0 = 100 MHz | `create_bd.tcl` |
| PHY refclk | FCLK_CLK3 = 25 MHz → pin U18 | EBAZ4205 schematic |
| PL DSP/IO bank | LVCMOS33 | `ebaz4205.xdc` |
| ADC | AD9226, 12-bit twos-complement, parallel @ 60 MHz | `docs/ad9226.pdf` |
| DAC | DAC904, 14-bit unsigned, parallel @ 60 MHz | `docs/dac904-14bit.pdf` |
| PHY | IC+ IP101G, MII | `docs/IP101GRI.PDF` |
| DDR | 256 MB (Zynq PS-attached) | EBAZ4205 schematic |
| GEM0 PHY MDIO addr | `0x01` | board convention |

## RTL conventions (already established)

- Single 60 MHz clock for the whole DSP datapath (`clk_60mhz`).
- AXI-Stream I/Q payload = `{Q[15:0], I[15:0]}` packed in one 32-bit word.
- AXI-Lite slaves use the simple Xilinx-style two-handshake state machine
  found in [`hardware/rtl/nco.v`](hardware/rtl/nco.v); the same template is
  copy-pasted into `dac_if.v`, `cic_interpolator.v`, `hb_fir_*.v`,
  `ddc_top.v`, `duc_top.v`. Only `0x00..0x0C` registers are used.
- DDC and DUC have **independent** `nco_direct` instances driven from
  identical `freq_word` registers. They are *not* phase-locked across TX/RX,
  but both follow the same software-set carrier.
- DAC pin polarity: `DAC[i]` pin drives DAC chip data bit `i` directly
  (`DAC[13]`=H16=BIT1=D13(MSB), `DAC[0]`=G20=BIT14=D0(LSB)). The header
  comment in [`hardware/rtl/dac_if.v`](hardware/rtl/dac_if.v) is misleading
  but the assignment `DAC <= s_axis_tdata[13:0]` is correct.

## Address map (assigned in `create_bd.tcl`)

| Region | Base | Size |
|---|---|---|
| AXI DMA0 (S2MM, ADC→DDR) lite | `0x4040_0000` | 64 KB |
| AXI DMA1 (MM2S, DDR→DAC) lite | `0x4042_0000` | 64 KB |
| DDC control (`ddc_top` AXI-Lite) | `0x43C0_0000` | 4 KB |
| DUC control (`duc_top` AXI-Lite) | `0x43C0_1000` | 4 KB |

DDC/DUC register offsets:
- `0x00` `nco_freq_word[31:0]` (Δφ, units of 2³² / 60 MHz ≈ 0.0140 Hz/LSB)
- `0x04` `decimation_rate[6:0]` (15 / 30 / 60 / 120)
- `0x08` DDC: status (RO, bit0=overflow sticky, bit1=lock); DUC: PD (bit0)

## Software stack (planned)

- Vitis 2022.2 BSP (xilffs, lwIP-2.1, xilstandalone) + FreeRTOS 10
- lwIP in `OS_MODE` with `tcpip_thread`, GEM0 MAC, static IP `192.168.1.100`
- Tasks:
  - `rx_task` (priority 3): DMA S2MM → frame builder → cm256 → UDP TX
  - `tx_task` (priority 3): UDP RX → cm256 → frame parser → DMA MM2S
  - `http_task` (priority 1): minimal HTTP/1.0 REST on port 8888
  - lwIP `tcpip_thread` (priority 2)

## Repository layout

```
ebaz4205-sdr/
├── CLAUDE.md                    ← this file
├── README.md
├── docs/
│   ├── PROGRESS.md              ← live status / what's done
│   ├── REVIEW.md                ← end-of-iteration summary
│   ├── ebaz4205-sdr-plan*.md    ← original plans
│   └── *.pdf                    ← chip datasheets
├── hardware/
│   ├── constraints/ebaz4205.xdc
│   ├── rtl/{adc_if,dac_if,clk_60mhz,nco,complex_mixer,
│   │        cic_*,hb_fir_*,ddc_top,duc_top,sdr_top}.v
│   ├── sim/tb_*.v
│   └── scripts/{create_project,create_bd,build}.tcl
├── firmware/                    ← Vitis 2022.2 application
│   └── src/{main.c, platform/, network/, protocol/, tasks/}
└── tools/                       ← PC-side helpers
    └── test_udp_*.py
```

## Build commands

```bash
# FPGA — from hardware/scripts/
vivado -mode batch -source create_project.tcl
vivado -mode batch -source create_bd.tcl       # inside open project
vivado -mode batch -source build.tcl           # synth+impl+bitstream

# Vitis app (run inside Vitis IDE or xsct)
xsct firmware/build.tcl                        # if/when added
```

## Coding rules I follow when extending this repo

- Verilog-2001 style, lower-case module names, ports listed input→output.
- All FSMs synchronous with active-low `resetn`. No latches.
- C: C11, no dynamic allocation in hot path; static buffers; `volatile`
  for AXI-Lite reads/writes; `Xil_Out32`/`Xil_In32` only.
- No new files / docs outside what the plan explicitly calls for.
- Comments stay short; explain WHY, not WHAT.

## Known caveats / TODO bookkeeping

- `complex_mixer.v` DDC path produces `Q = data·sin` (no negation). This
  yields a frequency-mirrored baseband; SDRAngel can flip via "swap I/Q".
  Acceptable for v1; revisit if real RF testing requires correct sense.
- `cm256` on Cortex-A9: leave SIMD off for v1, re-enable NEON later.
- DDC `m_axis_tlast` is **not** driven. AXI DMA in direct-register mode
  hangs (`[rx_task] DMA timeout`). Need to add a sample-counter in
  [`ddc_top.v`](hardware/rtl/ddc_top.v) that asserts TLAST every N
  samples (N from a new AXI-Lite register).

## EBAZ4205-specific bring-up notes (do NOT lose)

These were re-derived the hard way during initial bring-up. The board
files in [`hardware/Board files/ebaz4205/1.0/`](hardware/Board files/)
are the authoritative source.

- **DDR3 chip is `MT41K128M16 JT-125`, 16-bit bus**. The default
  Zynq-7010 PCW config produces a controller that "comes up" but throws
  AXI slave errors on every access — which wedges the JTAG DAP. Set
  `CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125}` and
  `CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit}` in `create_bd.tcl`.
- **Console UART is UART1 on MIO 24/25**, not UART0. Configure
  `bsp config stdout ps7_uart_1` (and `stdin`) when building the Vitis
  platform, otherwise `xil_printf` goes nowhere.
- **GEM0 is on EMIO** (PL pins, bank 34) — MII to IP101G. Don't put
  GEM0 on MIO. The PL-pin XDC entries restored in
  [`ebaz4205.xdc`](hardware/constraints/ebaz4205.xdc) are correct.
- **IP101G is strapped to MDIO address `0x00`**, not the datasheet
  default `0x01`.
- **LEDs are active-LOW** (output 0 = LED on). [`sdr_top.v`](hardware/rtl/sdr_top.v)
  inverts before driving the pins.

## Xilinx lwIP-on-FreeRTOS port quirks (already handled in `net_init.c`)

- `tcpip_init()` only calls `lwip_init()` when `LWIP_XINIT` is defined
  in `lwipopts.h` — and it isn't. Without `lwip_init()`, `mem_mutex`
  is uninitialised and the very first `mem_malloc` aborts in
  `queue.c:1507  configASSERT(pxQueue->uxItemSize == 0)`. Solution:
  call the lwIP init steps (`mem_init`, `memp_init`, ...) ourselves
  before `tcpip_init`. See [`net_init.c`](firmware/src/network/net_init.c).
- `lwip_sock_init()` calls `tcpip_init()` then busy-waits on a flag
  set by `tcpip_thread`. That deadlocks when the calling task has
  priority higher than `TCPIP_THREAD_PRIO` (3 by default). We call
  `tcpip_init()` directly and skip `lwip_sock_init()` entirely.
- The port already creates its own `XScuGic` — exposed as
  `extern XScuGic xInterruptController`. Calling `XScuGic_CfgInitialize`
  again corrupts the port's vector table and trips queue.c asserts.
- Default `configTOTAL_HEAP_SIZE = 65536` is too small for FreeRTOS +
  lwIP + four worker tasks; bump to ≥ 1 MB via `bsp config total_heap_size`.

## Build commands

```bash
# FPGA — from hardware/scripts/
vivado -mode batch -source create_project.tcl   # creates Vivado project
vivado -mode batch -source <run_bd.tcl>          # source create_bd.tcl
                                                 # into the open project
vivado -mode batch -source build.tcl             # synth+impl+bitstream
# then export hardware handoff:
vivado -mode batch -source <export_xsa.tcl>      # writes ../ebaz4205_sdr.xsa

# Vitis platform + sdr_app (FreeRTOS+lwIP) and sdr_fsbl (standalone):
xsct <vitis_build.tcl>                            # platform + sdr_app
xsct <vitis_fsbl.tcl>                             # adds Zynq FSBL app

# Build BOOT.bin for SD-card boot:
cd firmware/sd_boot && bootgen -arch zynq -image boot.bif -o BOOT.bin -w on
# Copy BOOT.bin to a FAT32-formatted SD card, set board to SD boot mode.
```

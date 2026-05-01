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
- `create_bd.tcl` clocks DDC/DUC from `FCLK_CLK0` (100 MHz). The 60 MHz
  domain comes from the toplevel `clk_60mhz` MMCM and must be wired into
  the BD-level clock pins via `sdr_top.v`. The current BD wiring is a
  placeholder until 1.12 is finalised.
- `cm256` on Cortex-A9: leave SIMD off for v1, re-enable NEON later.

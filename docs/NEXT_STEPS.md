# Next steps — forward plan

Each item is a self-contained task suitable for a fresh agent thread.
Pick one, open its prompt under [`docs/prompts/`](prompts/), paste the
contents into a new conversation, and let the agent run.

When you finish a step, **mark it ✅ here** so the next thread can see
what's already done.

| # | Status | Task | Prompt |
|---|---|---|---|
| 1 | ⬜ | DDC `m_axis_tlast` generator — clears `[rx_task] DMA timeout` | [prompts/01-ddc-tlast.md](prompts/01-ddc-tlast.md) |
| 2 | ⬜ | MDIO via `XEmacPs_PhyRead` — fix our IP101G read-zero | [prompts/02-mdio-xemacps.md](prompts/02-mdio-xemacps.md) |
| 3 | ⬜ | Real SDRAngel end-to-end test (Remote Output plugin) | [prompts/03-sdrangel-e2e.md](prompts/03-sdrangel-e2e.md) |
| 4 | ⬜ | Q-sign mirror fix in `complex_mixer.v` | [prompts/04-q-sign-fix.md](prompts/04-q-sign-fix.md) |
| 5 | ⬜ | cm256 FEC port from `f4exb/cm256cc` | [prompts/05-cm256-fec.md](prompts/05-cm256-fec.md) |
| 6 | ⬜ | ILA debug instrumentation (Phase 3.2) | [prompts/06-ila-debug.md](prompts/06-ila-debug.md) |
| 7 | ⬜ | Build-warning cleanup (rx_task packed-member, axi_dma parens) | [prompts/07-build-warnings.md](prompts/07-build-warnings.md) |

## Recommended order

**Critical path to a working SDR:** 1 → 2 → 3.

Items 4-7 are quality-of-life and can be done in parallel threads in
any order. They don't block the critical path.

## Suggested model per step

| Step | Model |
|---|---|
| 1 (DDC TLAST) | Sonnet — RTL change + Vivado rebuild + on-hardware verify |
| 2 (MDIO) | Haiku/Sonnet — single-file firmware tweak |
| 3 (SDRAngel) | Sonnet/Opus — protocol debugging, multi-file |
| 4 (Q-sign) | Haiku — one-line RTL change |
| 5 (cm256) | Sonnet/Opus — porting C++ → C, multi-hour |
| 6 (ILA) | Sonnet — Vivado scripting |
| 7 (warnings) | Haiku — trivial |

## Build helpers (committed to repo)

The reusable batch scripts every step needs are now in:

- `hardware/scripts/run_bd.tcl` — source `create_bd.tcl` into open project
- `hardware/scripts/run_synth_impl.tcl` — synth + impl + bitstream + status check
- `hardware/scripts/export_xsa.tcl` — write `ebaz4205_sdr.xsa`
- `hardware/scripts/elab_check.tcl` — fast syntax-only check of all leaf RTL
- `firmware/scripts/vitis_build.tcl` — fresh platform + sdr_app
- `firmware/scripts/vitis_fsbl.tcl` — add Zynq FSBL app
- `firmware/scripts/vitis_rebuild.tcl` — incremental sdr_app relink
  (or just `make all` in `firmware/vitis_ws/sdr_app/Release/`)

Boot image recipe lives at `firmware/sd_boot/boot.bif`. Build with:

```bash
source /home/user/Xilinx/Vitis/2022.2/settings64.sh
cd firmware/sd_boot && bootgen -arch zynq -image boot.bif -o BOOT.bin -w on
```

## Things every prompt should NOT need to re-derive

These are already documented and committed — fresh agents should
read them rather than re-discover them:

- **EBAZ4205 board specifics** (DDR3 part, UART1 console, EMIO GEM0,
  PHY addr 0, active-low LEDs) — see `CLAUDE.md` § "EBAZ4205-specific
  bring-up notes" and `hardware/Board files/ebaz4205/1.0/preset.xml`.
- **Xilinx lwIP-on-FreeRTOS quirks** (`LWIP_XINIT` gating, busy-waiting
  `lwip_sock_init`, shared `xInterruptController`, 64 KB default heap)
  — see `CLAUDE.md` § "Xilinx lwIP-on-FreeRTOS port quirks".
- **Address map** — see `CLAUDE.md`.
- **What works on hardware today** — see `docs/REVIEW.md`.

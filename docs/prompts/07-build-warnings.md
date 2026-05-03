# Step 7 — Build-warning cleanup

You're picking up `ebaz4205-sdr` (see `CLAUDE.md`). A few benign
warnings clutter the firmware build; clean them up so future
warnings stand out.

## Warnings to fix

### `firmware/src/tasks/rx_task.c`

```
warning: taking address of packed member of 'struct <anonymous>' may
result in an unaligned pointer value [-Waddress-of-packed-member]
warning: 's_tx_chan_unused' defined but not used [-Wunused-variable]
```

Fix:
- For `address-of-packed-member`: `memcpy` into/out of a local
  variable instead of `&`-ing the packed field.
- Delete the unused `s_tx_chan_unused`.

### `firmware/src/tasks/tx_task.c`

Same `address-of-packed-member` warning — same fix.

### `firmware/src/platform/axi_dma.c`

```
warning: suggest parentheses around arithmetic in operand of '|' [-Wparentheses]
```

Fix: add explicit parentheses around the `XAXIDMA_IRQ_IOC_MASK |
XAXIDMA_IRQ_ERROR_MASK` operand. Pure cosmetic.

## Build & verify

Firmware-only — `make all` in `firmware/vitis_ws/sdr_app/Release/`,
then re-bootgen if you want a new BOOT.bin. The relevant `make`
output should be **zero warnings**.

When done: short commit (`"firmware: clean compile warnings"`),
mark row 7 ✅ in `docs/NEXT_STEPS.md`.

Trivial. Haiku-class task.

# Step 2 — MDIO via `XEmacPs_PhyRead`

You're picking up `ebaz4205-sdr` (see `CLAUDE.md`). The firmware boots
end-to-end and Xilinx's xemacps driver successfully detects the IP101G
PHY at MDIO address 0 — but our own helper `firmware/src/platform/ip101g.c`
reads `0x0000` for the PHYID. Our accessor is wrong; the BSP one works.

## Read first

1. `CLAUDE.md`
2. `docs/REVIEW.md` (item "Our `ip101g.c` reads `0x0000`")
3. `firmware/src/platform/ip101g.c` and `.h` — the file you'll modify
4. `firmware/src/network/net_init.c` — `net_get_xemacps()` is exported
   from here

## What to do

Replace the current MDIO accessor in `ip101g.c` with the BSP API:

```c
#include "xemacps.h"
extern XEmacPs *net_get_xemacps(void);    // declared in net_init.h

static int phy_read(uint8_t phy, uint8_t reg, uint16_t *val) {
    u16 v = 0;
    if (XEmacPs_PhyRead(net_get_xemacps(), phy, reg, &v) != XST_SUCCESS)
        return -1;
    *val = v;
    return 0;
}
static int phy_write(uint8_t phy, uint8_t reg, uint16_t val) {
    return XEmacPs_PhyWrite(net_get_xemacps(), phy, reg, val) == XST_SUCCESS ? 0 : -1;
}
```

Use these in `ip101g_init`, `ip101g_link_up`, `ip101g_dump`. The
existing logic (BMCR reset, ANAR setup, BMSR poll) doesn't change.

## Build & verify

Firmware-only change; just relink:

```bash
source /home/user/Xilinx/Vitis/2022.2/settings64.sh
cd firmware/vitis_ws/sdr_app/Release && make all
cd ../../../sd_boot && bootgen -arch zynq -image boot.bif -o BOOT.bin -w on
```

Hardware check: `[ip101g] PHYID = 0243:0c54` (or similar non-zero) in
the UART boot log. (IP101G's expected PHYID is `0243:0c54`.)

When done: short commit (`"ip101g: use XEmacPs_PhyRead/Write for MDIO"`),
mark row 2 ✅ in `docs/NEXT_STEPS.md`.

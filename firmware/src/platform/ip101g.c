// firmware/src/platform/ip101g.c
// Tiny MDIO bring-up for IC+ IP101G — uses GEM0 EmacPs MDIO primitives.
// We don't need the full XEmacPs driver here; a single-shot init that
// configures auto-neg + 100BASE-TX full duplex is enough for lwIP, which
// will rely on its own GEM0 driver for the MAC side.

#include "ip101g.h"
#include "xil_printf.h"
#include "xemacps.h"
#include "xparameters.h"

extern XEmacPs *net_get_xemacps(void);  // exported by net_init.c

static int phy_read(uint8_t addr, uint8_t reg, uint16_t *val)
{
    XEmacPs *emac = net_get_xemacps();
    if (!emac) return -1;
    u16 data = 0;
    if (XEmacPs_PhyRead(emac, addr, reg, &data) != XST_SUCCESS)
        return -1;
    *val = data;
    return 0;
}

static int phy_write(uint8_t addr, uint8_t reg, uint16_t val)
{
    XEmacPs *emac = net_get_xemacps();
    if (!emac) return -1;
    return (XEmacPs_PhyWrite(emac, addr, reg, val) == XST_SUCCESS) ? 0 : -1;
}

int ip101g_init(uint8_t phy_addr)
{
    // The Xilinx lwIP port already drove auto-neg inside xemac_add().
    // Its speed-detect dispatches by PHYID: TI / Realtek / "everything
    // else == Marvell". The IP101G matches none of those, so the
    // Marvell parser is fed the wrong vendor-specific status register
    // and the boot log reports "10 Mbps" regardless of what was
    // actually negotiated. We re-read the PHY here to get the real
    // resolved speed/duplex and re-program the MAC accordingly.

    uint16_t id1 = 0, id2 = 0, bmcr = 0, bmsr = 0;

    // Force 100BASE-TX FD/HD only (skip 10 Mbit) and restart auto-neg
    // so a stuck-at-10 link partner gets re-negotiated to 100M.
    phy_write(phy_addr, IP101G_ANAR, (1<<8) | (1<<7) | 0x0001);
    phy_write(phy_addr, IP101G_BMCR, IP101G_BMCR_AN_EN | IP101G_BMCR_AN_RESTART);

    // Wait for AN_DONE + LINK (best-effort, ~3 s)
    for (int i = 0; i < 30; ++i) {
        phy_read(phy_addr, IP101G_BMSR, &bmsr);
        if ((bmsr & IP101G_BMSR_LINK) && (bmsr & IP101G_BMSR_AN_DONE))
            break;
        for (volatile int d = 0; d < 1000000; ++d) ;
    }

    phy_read(phy_addr, IP101G_PHYIDR1, &id1);
    phy_read(phy_addr, IP101G_PHYIDR2, &id2);
    phy_read(phy_addr, IP101G_BMCR,    &bmcr);

    // After auto-neg the IP101G reflects the resolved speed/duplex
    // back into BMCR: bit 13 = 100 Mbps, bit 8 = full duplex.
    int speed_mbps  = (bmcr & IP101G_BMCR_100M) ? 100 : 10;
    int full_duplex = (bmcr & IP101G_BMCR_FD)   ? 1   : 0;

    xil_printf("[ip101g] PHYID=%04x:%04x BMCR=%04x BMSR=%04x -> %d Mbps %s%s\r\n",
               id1, id2, bmcr, bmsr, speed_mbps,
               full_duplex ? "FD" : "HD",
               (bmsr & IP101G_BMSR_LINK) ? "" : " (no link)");

    // Sync the MAC speed bit (NWCFG.SPEED) with what the PHY actually
    // negotiated — otherwise the BSP's mis-detected value (typically 10)
    // remains and TX/RX runs at the wrong rate.
    XEmacPs *emac = net_get_xemacps();
    if (emac) XEmacPs_SetOperatingSpeed(emac, (u16)speed_mbps);

    return (bmsr & IP101G_BMSR_LINK) ? 0 : -1;
}

int ip101g_link_up(uint8_t phy_addr)
{
    uint16_t v = 0;
    if (phy_read(phy_addr, IP101G_BMSR, &v) < 0) return 0;
    return (v & IP101G_BMSR_LINK) ? 1 : 0;
}

void ip101g_dump(uint8_t phy_addr)
{
    uint16_t v;
    static const uint8_t regs[] = {
        IP101G_BMCR, IP101G_BMSR, IP101G_PHYIDR1, IP101G_PHYIDR2,
        IP101G_ANAR, IP101G_ANLPAR, IP101G_PSCR, IP101G_PSMR
    };
    for (size_t i = 0; i < sizeof(regs); ++i) {
        if (phy_read(phy_addr, regs[i], &v) == 0)
            xil_printf("[ip101g] reg[%02x] = %04x\r\n", regs[i], v);
    }
}

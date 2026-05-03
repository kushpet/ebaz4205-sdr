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
    // BSP's xemac_add() already drove auto-neg to completion (it prints
    // "autonegotiation complete" in the boot log). It only mis-decodes
    // the resolved speed: get_IEEE_phy_speed dispatches by PHYID and
    // the IP101G doesn't match TI/Realtek, so the Marvell parser ends
    // up reading the wrong vendor-specific status register and reports
    // "10 Mbps" no matter what. We must NOT restart auto-neg here (that
    // tore the link down in the previous build); instead, derive the
    // negotiated speed from the standard 802.3 way — ANAR ∩ ANLPAR —
    // and re-program the MAC's NWCFG.SPEED bit accordingly.

    uint16_t id1 = 0, id2 = 0, bmcr = 0, bmsr = 0;
    uint16_t anar = 0, anlpar = 0, psmr = 0;
    phy_read(phy_addr, IP101G_PHYIDR1, &id1);
    phy_read(phy_addr, IP101G_PHYIDR2, &id2);
    phy_read(phy_addr, IP101G_BMCR,    &bmcr);
    phy_read(phy_addr, IP101G_BMSR,    &bmsr);
    phy_read(phy_addr, IP101G_ANAR,    &anar);
    phy_read(phy_addr, IP101G_ANLPAR,  &anlpar);
    phy_read(phy_addr, IP101G_PSMR,    &psmr);

    // ANAR / ANLPAR bit map (IEEE 802.3 clause 28):
    //   [8]=100FD  [7]=100HD  [6]=10FD  [5]=10HD
    uint16_t common = anar & anlpar;
    int speed_mbps, full_duplex;
    if      (common & (1u << 8)) { speed_mbps = 100; full_duplex = 1; }
    else if (common & (1u << 7)) { speed_mbps = 100; full_duplex = 0; }
    else if (common & (1u << 6)) { speed_mbps = 10;  full_duplex = 1; }
    else                         { speed_mbps = 10;  full_duplex = 0; }

    xil_printf("[ip101g] PHYID=%04x:%04x BMCR=%04x BMSR=%04x "
               "ANAR=%04x ANLPAR=%04x PSMR=%04x\r\n",
               id1, id2, bmcr, bmsr, anar, anlpar, psmr);
    xil_printf("[ip101g] negotiated %d Mbps %s%s\r\n",
               speed_mbps, full_duplex ? "FD" : "HD",
               (bmsr & IP101G_BMSR_LINK) ? " LINK_UP" : " (no link)");

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

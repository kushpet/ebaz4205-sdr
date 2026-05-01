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
    uint16_t v = 0;

    // 1. Soft reset
    phy_write(phy_addr, IP101G_BMCR, IP101G_BMCR_RESET);
    for (int i = 0; i < 50; ++i) {
        if (phy_read(phy_addr, IP101G_BMCR, &v) == 0 && !(v & IP101G_BMCR_RESET))
            break;
        for (volatile int d = 0; d < 100000; ++d) ;
    }
    if (v & IP101G_BMCR_RESET) {
        xil_printf("[ip101g] reset timeout\r\n");
        return -1;
    }

    // 2. Read PHYID — sanity check we are talking to something
    uint16_t id1 = 0, id2 = 0;
    phy_read(phy_addr, IP101G_PHYIDR1, &id1);
    phy_read(phy_addr, IP101G_PHYIDR2, &id2);
    xil_printf("[ip101g] PHYID = %04x:%04x\r\n", id1, id2);

    // 3. Advertise 100BASE-TX FD/HD only (skip 10 Mbit to force 100M)
    //    ANAR bits: [8]=100FD, [7]=100HD, [6]=10FD, [5]=10HD; [0..4]=selector(0x01=802.3)
    phy_write(phy_addr, IP101G_ANAR, (1<<8) | (1<<7) | 0x0001);

    // 4. Restart auto-neg
    phy_write(phy_addr, IP101G_BMCR, IP101G_BMCR_AN_EN | IP101G_BMCR_AN_RESTART);

    // 5. Wait for link up (best-effort, 3 s)
    for (int i = 0; i < 30; ++i) {
        phy_read(phy_addr, IP101G_BMSR, &v);
        if ((v & IP101G_BMSR_LINK) && (v & IP101G_BMSR_AN_DONE))
            break;
        for (volatile int d = 0; d < 1000000; ++d) ;
    }
    xil_printf("[ip101g] BMSR = %04x %s\r\n", v,
               (v & IP101G_BMSR_LINK) ? "LINK_UP" : "(no link yet)");
    return 0;
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

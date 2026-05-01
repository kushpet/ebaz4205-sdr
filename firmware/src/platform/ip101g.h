#ifndef EBAZ_IP101G_H
#define EBAZ_IP101G_H

#include <stdint.h>

// IP101G register subset (datasheet docs/IP101GRI.PDF)
#define IP101G_BMCR     0x00  // Basic Mode Control
#define IP101G_BMSR     0x01  // Basic Mode Status
#define IP101G_PHYIDR1  0x02
#define IP101G_PHYIDR2  0x03
#define IP101G_ANAR     0x04  // auto-neg advertisement
#define IP101G_ANLPAR   0x05  // auto-neg link partner
#define IP101G_PSCR     0x10  // PHY-Specific Ctrl Reg (Page 0)
#define IP101G_PSMR     0x11  // PHY-Specific Modes
#define IP101G_INT_SR   0x1B  // INT/PHY status

#define IP101G_BMCR_RESET    0x8000
#define IP101G_BMCR_LOOPBACK 0x4000
#define IP101G_BMCR_AN_EN    0x1000
#define IP101G_BMCR_AN_RESTART 0x0200
#define IP101G_BMCR_FD       0x0100
#define IP101G_BMCR_100M     0x2000

#define IP101G_BMSR_LINK     0x0004
#define IP101G_BMSR_AN_DONE  0x0020

// Default MDIO PHY address on EBAZ4205 (board-strapping resistors).
#define IP101G_PHY_ADDR_DEFAULT 0x01

int  ip101g_init(uint8_t phy_addr);
int  ip101g_link_up(uint8_t phy_addr);
void ip101g_dump(uint8_t phy_addr);

#endif

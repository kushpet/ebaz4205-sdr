#ifndef EBAZ_NET_INIT_H
#define EBAZ_NET_INIT_H

#include <stdint.h>

#include "lwip/netif.h"
#include "xemacps.h"
#include "xscugic.h"

// MAC for the local board. Locally administered, so any private value
// works; change to suit your network.
#define EBAZ_MAC0  0x02
#define EBAZ_MAC1  0x12
#define EBAZ_MAC2  0x34
#define EBAZ_MAC3  0x56
#define EBAZ_MAC4  0x78
#define EBAZ_MAC5  0xAA

// Static IP. Set EBAZ_USE_DHCP to 1 to obtain via DHCP instead.
#define EBAZ_USE_DHCP   0
#define EBAZ_IP4_ADDR   "192.168.1.100"
#define EBAZ_IP4_MASK   "255.255.255.0"
#define EBAZ_IP4_GW     "192.168.1.1"

// Bring up GEM0, register the lwIP interface, start the tcpip_thread.
// Must be called from main() after platform_init().
int net_init(void);

// Accessors used by other modules so they don't have to know about
// the global lwIP / Xilinx structures.
struct netif *net_get_netif(void);
XEmacPs      *net_get_xemacps(void);
XScuGic      *net_get_gic(void);

#endif

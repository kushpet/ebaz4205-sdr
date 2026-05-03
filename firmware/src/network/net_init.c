// firmware/src/network/net_init.c
// Bring up the GEM0 / IP101G / lwIP stack on top of FreeRTOS.

#include "net_init.h"
#include "../platform/ip101g.h"

#include "lwip/init.h"
#include "lwip/dhcp.h"
#include "lwip/ip4_addr.h"
#include "lwip/mem.h"
#include "lwip/memp.h"
#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "lwip/ip4.h"
#include "lwip/etharp.h"
#include "lwip/udp.h"
#include "lwip/tcp.h"
#include "lwip/igmp.h"
#include "lwip/dns.h"
#include "lwip/timeouts.h"
#include "lwip/tcpip.h"
#include "netif/xadapter.h"
// netif/xemacpsif.h would give us the xemacpsif_s typedef directly, but
// it pulls in lwIP-port-private headers (debug.h, xpqueue.h) that aren't
// on the BSP public include path. We don't need the full struct — only
// that XEmacPs is its first member, which the Xilinx port documents.
// So we cast xemac->state straight to XEmacPs*.

extern void lwip_sock_init(void);
extern void sys_init(void);
extern void tcp_init(void);

#include "xparameters.h"
#include "xil_printf.h"

#include "FreeRTOS.h"
#include "task.h"

static struct netif s_netif;

// The Xilinx FreeRTOS port (freertos10_xilinx) already initialises one
// XScuGic instance and registers the IRQ exception vector. Reuse it via
// the global it exposes — calling XScuGic_CfgInitialize / Xil_Exception*
// ourselves would corrupt the port's state and trip queue.c assertions
// the moment any FreeRTOS API tries to block in a critical section.
extern XScuGic xInterruptController;

struct netif *net_get_netif(void)   { return &s_netif; }
XScuGic      *net_get_gic(void)     { return &xInterruptController; }

// xemac_add() owns the real XEmacPs — it lives as the first member of
// xemacpsif_s, reached via netif->state (struct xemac_s *) → xemac->state.
// Returning a separate static would give back an uninitialised struct and
// XEmacPs_PhyRead would read garbage (the 0x0000 PHYID we saw in v1).
XEmacPs *net_get_xemacps(void)
{
    if (!s_netif.state) return NULL;
    struct xemac_s *xemac = (struct xemac_s *)s_netif.state;
    if (!xemac->state)   return NULL;
    return (XEmacPs *)xemac->state;     /* XEmacPs is xemacpsif_s's 1st field */
}

static void main_thread(void *arg)
{
    (void)arg;

    ip4_addr_t ip, mask, gw;
    unsigned char mac[] = {EBAZ_MAC0, EBAZ_MAC1, EBAZ_MAC2,
                           EBAZ_MAC3, EBAZ_MAC4, EBAZ_MAC5};

    ip4addr_aton(EBAZ_IP4_ADDR, &ip);
    ip4addr_aton(EBAZ_IP4_MASK, &mask);
    ip4addr_aton(EBAZ_IP4_GW,   &gw);

    if (!xemac_add(&s_netif, &ip, &mask, &gw, mac, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("[net] xemac_add failed\r\n");
        vTaskDelete(NULL);
        return;
    }
    netif_set_default(&s_netif);
    netif_set_up(&s_netif);

    // Spawn the lwIP receive thread (drains the EMAC RX ring into pbufs)
    // xemacif_input_thread's prototype is void (*)(struct netif *), lwIP wants
    // void (*)(void *). Cast — both ABIs match on this platform.
    sys_thread_new("xemacif_input", (lwip_thread_fn)xemacif_input_thread,
                   &s_netif, TCPIP_THREAD_STACKSIZE, TCPIP_THREAD_PRIO);

    // Initialise the PHY now that the MAC is up (MDIO requires GEM0 enabled)
    ip101g_init(IP101G_PHY_ADDR_DEFAULT);

#if EBAZ_USE_DHCP
    dhcp_start(&s_netif);
#endif

    // ip4addr_ntoa returns a static buffer — print one at a time so the
    // three substitutions don't all share the same scratch.
    xil_printf("[net] up: ip=%s",  ip4addr_ntoa(&ip));
    xil_printf(" mask=%s",         ip4addr_ntoa(&mask));
    xil_printf(" gw=%s\r\n",       ip4addr_ntoa(&gw));

    vTaskDelete(NULL);
}

int net_wait_up(uint32_t timeout_ms)
{
    const uint32_t step = 50;
    for (uint32_t elapsed = 0; elapsed < timeout_ms; elapsed += step) {
        if (netif_is_up(&s_netif)) return 0;
        vTaskDelay(pdMS_TO_TICKS(step));
    }
    return -1;
}

int net_init(void)
{
    // Two Xilinx-lwip-port quirks we work around here:
    //   (1) tcpip_init() is patched to skip lwip_init() unless LWIP_XINIT
    //       is set — and it isn't. So we must run the initialisers
    //       ourselves before tcpip_init, otherwise mem_mutex is uninited
    //       and the first mem_malloc traps in queue.c:1507.
    //   (2) The Xilinx-added lwip_sock_init() calls tcpip_init() and
    //       then busy-waits for the tcpip_thread to set a flag. That
    //       deadlocks here because boot_task runs at priority 4 while
    //       TCPIP_THREAD_PRIO is 3 — the spin never yields, so the
    //       lower-priority tcpip_thread never runs. Calling tcpip_init
    //       directly (no spin) lets us yield via vTaskDelay below.
    sys_init();
    mem_init();
    memp_init();
    pbuf_init();
    netif_init();
    etharp_init();
    udp_init();
    tcp_init();
    sys_timeouts_init();

    tcpip_init(NULL, NULL);
    xil_printf("[net] tcpip_init returned\r\n");

    // Spawn a one-shot task to add the netif (needs to run after the
    // scheduler is ticking because xemacif_input_thread calls FreeRTOS
    // primitives during construction).
    if (xTaskCreate(main_thread, "net_init", 1024, NULL,
                    tskIDLE_PRIORITY + 1, NULL) != pdPASS)
        return -1;
    xil_printf("[net] main_thread spawned\r\n");
    return 0;
}

// firmware/src/network/net_init.c
// Bring up the GEM0 / IP101G / lwIP stack on top of FreeRTOS.

#include "net_init.h"
#include "../platform/ip101g.h"

#include "lwip/init.h"
#include "lwip/dhcp.h"
#include "lwip/ip4_addr.h"
#include "lwip/tcpip.h"
#include "netif/xadapter.h"

#include "xparameters.h"
#include "xil_printf.h"

#include "FreeRTOS.h"
#include "task.h"

static struct netif s_netif;
static XEmacPs      s_emac;

// The Xilinx FreeRTOS port (freertos10_xilinx) already initialises one
// XScuGic instance and registers the IRQ exception vector. Reuse it via
// the global it exposes — calling XScuGic_CfgInitialize / Xil_Exception*
// ourselves would corrupt the port's state and trip queue.c assertions
// the moment any FreeRTOS API tries to block in a critical section.
extern XScuGic xInterruptController;

struct netif *net_get_netif(void)   { return &s_netif; }
XEmacPs      *net_get_xemacps(void) { return &s_emac; }
XScuGic      *net_get_gic(void)     { return &xInterruptController; }

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

    xil_printf("[net] up: %s/%s gw=%s\r\n",
               ip4addr_ntoa(&ip), ip4addr_ntoa(&mask), ip4addr_ntoa(&gw));

    vTaskDelete(NULL);
}

int net_init(void)
{
    // Initialise lwIP and start the tcpip_thread
    tcpip_init(NULL, NULL);

    // Spawn a one-shot task to add the netif (needs to run after the
    // scheduler is ticking because xemacif_input_thread calls FreeRTOS
    // primitives during construction).
    if (xTaskCreate(main_thread, "net_init", 1024, NULL,
                    tskIDLE_PRIORITY + 1, NULL) != pdPASS)
        return -1;
    return 0;
}

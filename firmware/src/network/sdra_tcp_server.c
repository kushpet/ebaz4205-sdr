// firmware/src/network/sdra_tcp_server.c
// SDRangel RemoteTCPInput server (rtl_tcp-compatible).
//
// v0 skeleton: bind :1234, accept one client at a time, send the
// 12-byte RTL0 greeting, then write 0x80-filled bytes forever — a
// flat baseband under 8-bit RTL-SDR encoding. Real DMA data and the
// SDRA extended header land in subsequent steps (see
// docs/sdra-tcp-plan.md).

#include "sdra_tcp_server.h"

#include "lwip/api.h"
#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#include <string.h>

// rtl_tcp greeting: 4-byte magic + uint32 BE tuner_type + uint32 BE
// gain count. Tuner type 5 (R820T) is a generic stand-in that the
// SDRangel plugin accepts; gain count 0 because we don't expose
// hardware gain steps.
static const uint8_t s_greeting[12] = {
    'R', 'T', 'L', '0',
    0x00, 0x00, 0x00, 0x05,
    0x00, 0x00, 0x00, 0x00,
};

// 0x80 is the unsigned-byte zero point in 8-bit RTL framing.
static uint8_t s_zero_iq[4096];

static void serve_client(struct netconn *c)
{
    if (netconn_write(c, s_greeting, sizeof(s_greeting),
                      NETCONN_COPY) != ERR_OK)
        return;

    for (;;) {
        if (netconn_write(c, s_zero_iq, sizeof(s_zero_iq),
                          NETCONN_COPY) != ERR_OK)
            return;
    }
}

static void sdra_tcp_task(void *arg)
{
    uint16_t port = (uint16_t)(uintptr_t)arg;

    memset(s_zero_iq, 0x80, sizeof(s_zero_iq));

    struct netconn *lst = netconn_new(NETCONN_TCP);
    if (!lst) {
        xil_printf("[sdra_tcp] netconn_new failed\r\n");
        vTaskDelete(NULL);
        return;
    }
    if (netconn_bind(lst, IP4_ADDR_ANY, port) != ERR_OK) {
        xil_printf("[sdra_tcp] bind :%u failed\r\n", port);
        netconn_delete(lst);
        vTaskDelete(NULL);
        return;
    }
    netconn_listen(lst);
    xil_printf("[sdra_tcp] listening on :%u\r\n", port);

    for (;;) {
        struct netconn *c = NULL;
        if (netconn_accept(lst, &c) != ERR_OK || !c) continue;
        xil_printf("[sdra_tcp] client connected\r\n");
        serve_client(c);
        xil_printf("[sdra_tcp] client disconnected\r\n");
        netconn_close(c);
        netconn_delete(c);
    }
}

int sdra_tcp_start(uint16_t port)
{
    return (xTaskCreate(sdra_tcp_task, "sdra_tcp", 4 * 1024,
                        (void *)(uintptr_t)port,
                        tskIDLE_PRIORITY + 3, NULL) == pdPASS) ? 0 : -1;
}

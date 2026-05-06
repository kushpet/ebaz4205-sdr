// firmware/src/network/sdra_tcp_server.c
// SDRangel RemoteTCPInput server (rtl_tcp-compatible).
//
// Bind :1234, accept one client at a time, send the 12-byte RTL0
// greeting, then ship DDC DMA buffers as a continuous byte stream.
// The DMA wire format is 32-bit beats {Q[15:0], I[15:0]}; under the
// RTL0 greeting SDRangel will misinterpret these as 8-bit unsigned
// samples — the SDRA extended header in the next step fixes the
// per-sample framing. For now we just need to see data move.
// See docs/sdra-tcp-plan.md.

#include "sdra_tcp_server.h"
#include "../platform/axi_dma.h"

#include "lwip/api.h"
#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

extern ebaz_dma_chan_t g_rx_chan;

// rtl_tcp greeting: 4-byte magic + uint32 BE tuner_type + uint32 BE
// gain count. Tuner type 5 (R820T) is a generic stand-in that the
// SDRangel plugin accepts; gain count 0 because we don't expose
// hardware gain steps.
static const uint8_t s_greeting[12] = {
    'R', 'T', 'L', '0',
    0x00, 0x00, 0x00, 0x05,
    0x00, 0x00, 0x00, 0x00,
};

static void serve_client(struct netconn *c)
{
    if (netconn_write(c, s_greeting, sizeof(s_greeting),
                      NETCONN_COPY) != ERR_OK)
        return;

    // Prime the ping-pong: first transfer fills slot `cur`.
    if (ebaz_dma_start(&g_rx_chan) != 0) {
        xil_printf("[sdra_tcp] dma_start failed\r\n");
        return;
    }

    for (;;) {
        if (ebaz_dma_wait(&g_rx_chan, 1000) != 0) {
            xil_printf("[sdra_tcp] DMA timeout\r\n");
            // Leave channel in best-effort state; let next client
            // re-prime. (The DMA may still complete asynchronously,
            // which is benign — the buffer just gets overwritten.)
            return;
        }
        void *ready = ebaz_dma_swap(&g_rx_chan);
        // Rearm the alternate slot immediately so the FPGA never stalls.
        ebaz_dma_start(&g_rx_chan);

        if (netconn_write(c, ready, EBAZ_DMA_BUF_BYTES,
                          NETCONN_COPY) != ERR_OK) {
            // Drain the in-flight transfer before returning so the
            // next accept's prime sees a settled channel.
            ebaz_dma_wait(&g_rx_chan, 1000);
            ebaz_dma_swap(&g_rx_chan);
            return;
        }
    }
}

static void sdra_tcp_task(void *arg)
{
    uint16_t port = (uint16_t)(uintptr_t)arg;

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

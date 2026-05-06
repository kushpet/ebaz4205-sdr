// firmware/src/network/sdra_tcp_server.c
// SDRangel RemoteTCPInput server.
//
// Bind :1234, accept one client at a time, send a 128-byte SDRA
// metadata header, then ship DDC DMA buffers verbatim as little-
// endian int16 I/Q pairs. SDMA's 32-bit beats are stored as
// {I_lo, I_hi, Q_lo, Q_hi} in DDR by the AXI-Stream→DMA write,
// which matches SDRangel's 16-bit mode wire format directly.
// See docs/sdra-tcp-plan.md.

#include "sdra_tcp_server.h"
#include "../platform/axi_dma.h"

#include "lwip/api.h"
#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#include <string.h>

extern ebaz_dma_chan_t g_rx_chan;

// Defaults match main.c boot_task: 7.1 MHz @ 1 MS/s I/Q (R=30 ⇒
// 60 MHz / 30 / 2 = 1 MS/s). When step 5 wires in client commands
// these become live and writable.
static uint64_t s_freq_hz        = 7100000ULL;
static uint32_t s_sample_rate_hz = 1000000U;

static inline void be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static inline void be64(uint8_t *p, uint64_t v)
{
    be32(p,     (uint32_t)(v >> 32));
    be32(p + 4, (uint32_t)v);
}

// Build the 128-byte SDRA greeting per
// plugins/channelrx/remotetcpsink/remotetcpprotocol.h (v7.24.0).
// Field offsets cross-checked against
// remotetcpinputtcphandler.cpp::processMetaData. Big-endian.
//
//   [0..3]   "SDRA"
//   [4]      uint32  device type (5 = RTLSDR_R820T — generic)
//   [8]      uint64  centre frequency Hz
//   [16]     uint32  LO PPM correction      (0)
//   [20]     uint32  flags                  (0)
//   [24]     uint32  device sample rate Hz
//   [28]     uint32  log2 decimation        (0 — no host-side decim)
//   [32]     int16×3 tuner / IF gains       (0)
//   [40]     uint32  RF bandwidth           (0)
//   [44]     uint32  input frequency offset (0)
//   [48]     uint32  channel gain           (0)
//   [52]     uint32  channel sample rate Hz
//   [56]     uint32  sample bits            (16)
//   [60]     uint32  protocol revision      (0 — skip rev≥1 fields)
//   [64..127]                                reserved/zero
static void build_sdra_meta(uint8_t out[128])
{
    memset(out, 0, 128);
    out[0] = 'S'; out[1] = 'D'; out[2] = 'R'; out[3] = 'A';
    be32(&out[4],  5);
    be64(&out[8],  s_freq_hz);
    be32(&out[24], s_sample_rate_hz);
    be32(&out[52], s_sample_rate_hz);
    be32(&out[56], 16);
}

static void serve_client(struct netconn *c)
{
    uint8_t meta[128];
    build_sdra_meta(meta);
    if (netconn_write(c, meta, sizeof(meta),
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

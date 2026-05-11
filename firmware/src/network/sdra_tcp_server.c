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
#include "../platform/ddc_ctrl.h"

#include "lwip/api.h"
#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#include <string.h>

extern ebaz_dma_chan_t g_rx_chan;

// Live state, mirrored into the SDRA header on each accept and updated
// by client commands (setCenterFrequency / setSampleRate). Defaults
// match main.c boot_task: 7.1 MHz @ 1 MS/s I/Q (R=30 ⇒ 60 MHz / 30 / 2).
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

// Client→server command frames are 5 bytes:
//   [0]   command code (RemoteTCPProtocol::Command enum)
//   [1..4] uint32 BE param
// We honour only setCenterFrequency (0x01) and setSampleRate (0x02);
// every other code is read and discarded so the byte stream stays in
// sync.
typedef struct {
    uint8_t buf[5];
    int     have;   // 0..5
} cmd_acc_t;

// Channel sample rate = 60 MHz / R / 2. Snap an arbitrary requested
// rate to the nearest R ∈ {15, 30, 60, 120}.
static uint8_t rate_hz_to_r(uint32_t hz)
{
    uint32_t r = (hz > 0) ? (30000000U / hz) : 30U;
    if      (r <= 22)  return 15;
    else if (r <= 45)  return 30;
    else if (r <= 90)  return 60;
    else               return 120;
}

static void apply_command(uint8_t cmd, uint32_t param)
{
    switch (cmd) {
    case 0x01:  // setCenterFrequency
        s_freq_hz = (uint64_t)param;
        sdr_set_frequency((int32_t)param);
        xil_printf("[sdra_tcp] freq <- %u Hz\r\n", (unsigned)param);
        break;
    case 0x02: {  // setSampleRate
        uint8_t r = rate_hz_to_r(param);
        s_sample_rate_hz = 30000000U / r;
        sdr_set_rate(r);
        xil_printf("[sdra_tcp] rate <- %u Hz (R=%u)\r\n",
                   (unsigned)s_sample_rate_hz, (unsigned)r);
        break;
    }
    default:
        break;
    }
}

static void cmd_ingest(cmd_acc_t *acc, const uint8_t *data, size_t len)
{
    while (len > 0) {
        size_t take = (size_t)(5 - acc->have);
        if (take > len) take = len;
        memcpy(acc->buf + acc->have, data, take);
        acc->have += (int)take;
        data      += take;
        len       -= take;
        if (acc->have == 5) {
            uint32_t p = ((uint32_t)acc->buf[1] << 24) |
                         ((uint32_t)acc->buf[2] << 16) |
                         ((uint32_t)acc->buf[3] << 8)  |
                         ((uint32_t)acc->buf[4]);
            apply_command(acc->buf[0], p);
            acc->have = 0;
        }
    }
}

// Drain whatever the client has buffered. We flip the netconn into
// non-blocking mode around the recv calls only, then restore blocking
// before returning so the next netconn_write keeps its TCP-backpressure
// semantics. Returns 0 on "no more data right now", -1 on close/error.
//
// The Xilinx lwip211 BSP is built with LWIP_SO_RCVTIMEO=0, so
// netconn_set_recvtimeout doesn't link — this is the workaround.
static int drain_commands(struct netconn *c, cmd_acc_t *acc)
{
    netconn_set_nonblocking(c, 1);
    int rc = 0;
    for (;;) {
        struct netbuf *nb = NULL;
        err_t e = netconn_recv(c, &nb);
        if (e == ERR_WOULDBLOCK) break;
        if (e != ERR_OK || !nb)  { rc = -1; break; }
        void  *d;
        u16_t  n;
        if (netbuf_data(nb, &d, &n) == ERR_OK)
            cmd_ingest(acc, (const uint8_t *)d, n);
        netbuf_delete(nb);
    }
    netconn_set_nonblocking(c, 0);
    return rc;
}

static void serve_client(struct netconn *c)
{
    uint8_t   meta[128];
    cmd_acc_t cmd_acc = { .have = 0 };

    build_sdra_meta(meta);
    if (netconn_write(c, meta, sizeof(meta),
                      NETCONN_COPY) != ERR_OK)
        return;

    if (ebaz_dma_start(&g_rx_chan) != 0) {
        xil_printf("[sdra_tcp] dma_start failed\r\n");
        return;
    }

    int dbg_iter = 0;
    for (;;) {
        if (ebaz_dma_wait(&g_rx_chan, 1000) != 0) {
            xil_printf("[sdra_tcp] DMA timeout\r\n");
            return;  // no transfer in flight — clean exit
        }
        void *ready = ebaz_dma_swap(&g_rx_chan);
        // Rearm the alternate slot immediately so the FPGA never stalls.
        ebaz_dma_start(&g_rx_chan);

        // Debug: every ~100 buffers (~6.5 s at 1 MS/s, 64 KiB/buf),
        // print decoded DDC status + first 4 raw DMA words. Status bit
        // layout is documented in ddc_top.v.
        if ((dbg_iter++ & 0x7F) == 0) {
            const uint32_t *u  = (const uint32_t *)ready;
            uint32_t st        = ddc_get_status();
            unsigned ovf       = (st >>  0) & 0x1;
            unsigned lock      = (st >>  1) & 0x1;
            unsigned adc_min   = (st >>  2) & 0xFFF;
            unsigned adc_max   = (st >> 14) & 0xFFF;
            unsigned otr_or    = (st >> 26) & 0x1;
            unsigned otr_live  = (st >> 27) & 0x1;
            int      adc_range = (int)adc_max - (int)adc_min;
            xil_printf("[dbg] ovf=%u lock=%u "
                       "adc[min=%03x max=%03x range=%d] "
                       "otr[or=%u live=%u]  "
                       "buf=%p [0..3]=%08x %08x %08x %08x\r\n",
                       ovf, lock, adc_min, adc_max, adc_range,
                       otr_or, otr_live,
                       ready,
                       (unsigned)u[0], (unsigned)u[1],
                       (unsigned)u[2], (unsigned)u[3]);
        }

        if (netconn_write(c, ready, EBAZ_DMA_BUF_BYTES,
                          NETCONN_COPY) != ERR_OK)
            break;
        if (drain_commands(c, &cmd_acc) != 0)
            break;
    }

    // An armed transfer is still in flight; let it complete so the
    // next accept's prime sees a settled channel.
    ebaz_dma_wait(&g_rx_chan, 1000);
    ebaz_dma_swap(&g_rx_chan);
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

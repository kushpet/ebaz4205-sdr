// firmware/src/platform/axi_dma.c
// Thin wrapper over the Xilinx XAxiDma driver. Both channels run in
// "Simple mode" (no SG); this is enough for ping-pong streaming and keeps
// the BD small.  Each half-buffer is allocated from the non-cacheable DDR
// region carved out by platform_init() (EBAZ_DMA_REGION_BASE).

#include "axi_dma.h"
#include "platform_init.h"

#include "xaxidma.h"
#include "xil_exception.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xil_printf.h"

extern XScuGic *net_get_gic(void);  // shared GIC instance (created by main)

// Two driver instances kept here so ISRs can find them.
static XAxiDma s_dma_rx;
static XAxiDma s_dma_tx;
static ebaz_dma_chan_t *s_rx_ch;
static ebaz_dma_chan_t *s_tx_ch;

static void rx_isr(void *ctx)
{
    BaseType_t hpw = pdFALSE;
    XAxiDma   *d   = (XAxiDma *)ctx;
    uint32_t   sr  = XAxiDma_IntrGetIrq(d, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrAckIrq(d, sr, XAXIDMA_DEVICE_TO_DMA);
    if ((sr & XAXIDMA_IRQ_IOC_MASK) && s_rx_ch && s_rx_ch->done_sem)
        xSemaphoreGiveFromISR(s_rx_ch->done_sem, &hpw);
    portYIELD_FROM_ISR(hpw);
}

static void tx_isr(void *ctx)
{
    BaseType_t hpw = pdFALSE;
    XAxiDma   *d   = (XAxiDma *)ctx;
    uint32_t   sr  = XAxiDma_IntrGetIrq(d, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrAckIrq(d, sr, XAXIDMA_DMA_TO_DEVICE);
    if ((sr & XAXIDMA_IRQ_IOC_MASK) && s_tx_ch && s_tx_ch->done_sem)
        xSemaphoreGiveFromISR(s_tx_ch->done_sem, &hpw);
    portYIELD_FROM_ISR(hpw);
}

static int connect_irq(uint32_t intr_id, Xil_InterruptHandler isr, void *ctx)
{
    XScuGic *gic = net_get_gic();
    if (!gic) return -1;
    XScuGic_SetPriorityTriggerType(gic, intr_id, 0xA0, 0x3);
    if (XScuGic_Connect(gic, intr_id, isr, ctx) != XST_SUCCESS) return -1;
    XScuGic_Enable(gic, intr_id);
    return 0;
}

static int dma_open(XAxiDma *drv, uint32_t base)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfigBaseAddr(base);
    if (!cfg) return -1;
    if (XAxiDma_CfgInitialize(drv, cfg) != XST_SUCCESS) return -1;
    if (XAxiDma_HasSg(drv)) return -1;  // we configured simple-mode
    return 0;
}

int ebaz_dma_init(ebaz_dma_chan_t *rx, ebaz_dma_chan_t *tx)
{
    s_rx_ch = rx;
    s_tx_ch = tx;

    if (dma_open(&s_dma_rx, EBAZ_DMA0_BASE) != 0) return -1;
    if (dma_open(&s_dma_tx, EBAZ_DMA1_BASE) != 0) return -1;

    // Carve buffers from the non-cached region: 4 buffers total, contiguous.
    uint8_t *p = (uint8_t *)EBAZ_DMA_REGION_BASE;
    for (int i = 0; i < EBAZ_DMA_BUF_COUNT; ++i) {
        rx->buf[i] = p; p += EBAZ_DMA_BUF_BYTES;
        tx->buf[i] = p; p += EBAZ_DMA_BUF_BYTES;
    }
    rx->base = EBAZ_DMA0_BASE; rx->direction = 0;
    tx->base = EBAZ_DMA1_BASE; tx->direction = 1;
    rx->buf_len = EBAZ_DMA_BUF_BYTES;
    tx->buf_len = EBAZ_DMA_BUF_BYTES;
    rx->cur = 0; tx->cur = 0;
    rx->done_sem = xSemaphoreCreateBinary();
    tx->done_sem = xSemaphoreCreateBinary();
    if (!rx->done_sem || !tx->done_sem) return -1;

    XAxiDma_IntrEnable(&s_dma_rx, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK,
                       XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrEnable(&s_dma_tx, XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK,
                       XAXIDMA_DMA_TO_DEVICE);

    if (connect_irq(EBAZ_IRQ_DMA0_S2MM, rx_isr, &s_dma_rx) != 0) return -1;
    if (connect_irq(EBAZ_IRQ_DMA1_MM2S, tx_isr, &s_dma_tx) != 0) return -1;

    xil_printf("[dma] init OK; rx=%p,%p tx=%p,%p\r\n",
               rx->buf[0], rx->buf[1], tx->buf[0], tx->buf[1]);
    return 0;
}

int ebaz_dma_start(ebaz_dma_chan_t *ch)
{
    XAxiDma *drv = (ch->direction == 0) ? &s_dma_rx : &s_dma_tx;
    int dir      = (ch->direction == 0) ? XAXIDMA_DEVICE_TO_DMA : XAXIDMA_DMA_TO_DEVICE;
    int rc = XAxiDma_SimpleTransfer(drv,
                                    (UINTPTR)ch->buf[ch->cur],
                                    ch->buf_len, dir);
    if (rc != XST_SUCCESS) {
        xil_printf("[dma] SimpleTransfer dir=%d buf=%p len=%u failed: %d\r\n",
                   dir, ch->buf[ch->cur], (unsigned)ch->buf_len, rc);
        return -1;
    }
    return 0;
}

int ebaz_dma_wait(ebaz_dma_chan_t *ch, uint32_t timeout_ms)
{
    return (xSemaphoreTake(ch->done_sem, pdMS_TO_TICKS(timeout_ms)) == pdTRUE)
        ? 0 : -1;
}

void *ebaz_dma_swap(ebaz_dma_chan_t *ch)
{
    void *done_buf = ch->buf[ch->cur];
    ch->cur = (ch->cur + 1) % EBAZ_DMA_BUF_COUNT;
    return done_buf;
}

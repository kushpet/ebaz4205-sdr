// firmware/src/tasks/rx_task.c
// Pulls IQ from the DDC -> DMA buffer, packs SDRAngel super-frames, and
// streams them out via udp_tx.  No FEC for now (nb_fec_blocks = 0).

#include "rx_task.h"
#include "../platform/axi_dma.h"
#include "../platform/ddc_ctrl.h"
#include "../protocol/sdrangel_frame.h"
#include "../protocol/iq_convert.h"
#include "../network/udp_tx.h"

#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

static ebaz_dma_chan_t s_rx_chan;
static ebaz_dma_chan_t s_tx_chan_unused;

static ip4_addr_t      s_dst_ip;
static uint16_t        s_dst_port = SDRA_DEFAULT_UDP_PORT;
static rx_task_stats_t s_stats;

static uint16_t        s_frame_index;
static sdra_block_t    s_block;          // assembled before send

extern int  ebaz_dma_init(ebaz_dma_chan_t *rx, ebaz_dma_chan_t *tx);

void rx_task_set_dest(const ip4_addr_t *ip, uint16_t port)
{
    s_dst_ip   = *ip;
    s_dst_port = port;
}

void rx_task_get_stats(rx_task_stats_t *out)
{
    if (out) *out = s_stats;
}

// Decimation -> output sample rate (post HB-FIR ÷2).
static uint32_t current_sample_rate_hz(void)
{
    // Ideally read back from the DDC AXI-Lite register. For now mirror
    // a software-side variable; we set R from the REST handler.
    extern uint8_t g_dec_rate;
    return (uint32_t)(60000000U / (g_dec_rate ? g_dec_rate : 30) / 2U);
}

extern uint64_t g_center_frequency_hz;

static void send_frame(const uint32_t *samples, size_t total_samples)
{
    // Block 0: meta
    sdra_meta_fill(&s_block, s_frame_index,
                   g_center_frequency_hz, current_sample_rate_hz(), 0);
    if (udp_tx_send_block(&s_block) == 0) ++s_stats.blocks_sent;
    else                                   ++s_stats.blocks_dropped;

    // Blocks 1..127: IQ
    size_t off = 0;
    for (uint8_t bi = 1; bi < SDRA_NB_ORIGINAL_BLOCKS; ++bi) {
        if (off + SDRA_SAMPLES_PER_BLOCK > total_samples) break;
        sdra_iq_header_fill(&s_block, s_frame_index, bi);
        iq_copy_dma_to_wire(s_block.payload.samples.iq,
                            samples + off,
                            SDRA_SAMPLES_PER_BLOCK,
                            32767);
        if (udp_tx_send_block(&s_block) == 0) ++s_stats.blocks_sent;
        else                                   ++s_stats.blocks_dropped;
        off += SDRA_SAMPLES_PER_BLOCK;
    }
    ++s_stats.frames_built;
    ++s_frame_index;  // wraps mod 65536 naturally
}

static void rx_task_fn(void *arg)
{
    (void)arg;

    if (udp_tx_open(&s_dst_ip, s_dst_port) != 0) {
        xil_printf("[rx_task] udp_tx_open failed\r\n");
        vTaskDelete(NULL);
        return;
    }

    // Prime the ping-pong: kick the first transfer.
    ebaz_dma_start(&s_rx_chan);

    for (;;) {
        // Wait for the in-flight transfer to complete.
        if (ebaz_dma_wait(&s_rx_chan, 1000) != 0) {
            xil_printf("[rx_task] DMA timeout\r\n");
            continue;
        }
        void *ready = ebaz_dma_swap(&s_rx_chan);
        // Immediately rearm the alternate buffer so the FPGA never stalls.
        ebaz_dma_start(&s_rx_chan);

        // Pump as many super-frames as the buffer holds.
        size_t bytes        = EBAZ_DMA_BUF_BYTES;
        size_t total_samps  = bytes / sizeof(uint32_t);
        size_t per_frame    = SDRA_NB_IQ_BLOCKS * SDRA_SAMPLES_PER_BLOCK; // 16002
        const uint32_t *p   = (const uint32_t *)ready;

        while (total_samps >= per_frame) {
            send_frame(p, per_frame);
            p          += per_frame;
            total_samps -= per_frame;
        }
    }
}

int rx_task_start(void)
{
    // s_rx_chan/s_tx_chan_unused only used for the RX side here; tx_task
    // will share the same DMA structure by separately initialising it.
    // Calling ebaz_dma_init here would re-init both.  Caller (main) is
    // responsible for the one-time DMA init; we just grab a handle.
    extern ebaz_dma_chan_t g_rx_chan;
    s_rx_chan = g_rx_chan;

    return (xTaskCreate(rx_task_fn, "rx_task", 4 * 1024, NULL,
                        tskIDLE_PRIORITY + 3, NULL) == pdPASS) ? 0 : -1;
}

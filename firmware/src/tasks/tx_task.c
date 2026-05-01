// firmware/src/tasks/tx_task.c
// Receives SDRAngel super-frames over UDP, reassembles by frame_index,
// pushes IQ into the DUC DMA buffer.

#include "tx_task.h"
#include "../platform/axi_dma.h"
#include "../protocol/sdrangel_frame.h"
#include "../protocol/iq_convert.h"
#include "../network/udp_rx.h"

#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#include <string.h>

static ebaz_dma_chan_t s_tx_chan;
static tx_task_stats_t s_stats;

extern ebaz_dma_chan_t g_tx_chan;

static void assemble_frame_into(uint32_t *dma_dst, sdra_block_t *blocks)
{
    // Lay out 127 IQ blocks back-to-back.
    size_t off = 0;
    for (uint8_t bi = 1; bi < SDRA_NB_ORIGINAL_BLOCKS; ++bi) {
        const sdra_block_t *b = &blocks[bi];
        iq_copy_wire_to_dma(dma_dst + off,
                            b->payload.samples.iq,
                            SDRA_SAMPLES_PER_BLOCK,
                            32767);
        off += SDRA_SAMPLES_PER_BLOCK;
    }
}

static void tx_task_fn(void *arg)
{
    (void)arg;

    if (udp_rx_open(SDRA_DEFAULT_UDP_PORT) != 0) {
        xil_printf("[tx_task] udp_rx_open failed\r\n");
        vTaskDelete(NULL);
        return;
    }

    // Per-frame reassembly buffer (one super-frame = 128 blocks).
    static sdra_block_t blocks[SDRA_NB_ORIGINAL_BLOCKS];
    int      have_meta      = 0;
    uint16_t cur_frame_index = 0;
    uint8_t  filled[SDRA_NB_ORIGINAL_BLOCKS];
    memset(filled, 0, sizeof(filled));

    sdra_block_t inb;
    for (;;) {
        if (udp_rx_recv_block(&inb, 1000) != 0) continue;
        ++s_stats.blocks_received;

        uint16_t fi = inb.header.frame_index;
        uint8_t  bi = inb.header.block_index;

        if (!have_meta || fi != cur_frame_index) {
            // New frame: flush old (best-effort), reset state.
            cur_frame_index = fi;
            memset(filled, 0, sizeof(filled));
            have_meta = 0;
        }

        if (bi < SDRA_NB_ORIGINAL_BLOCKS) {
            blocks[bi] = inb;
            filled[bi] = 1;
            if (bi == 0) have_meta = 1;
        } else {
            // FEC parity — ignored until cm256 is wired in.
        }

        // Frame complete? Need at least all 128 originals (for now).
        int complete = 1;
        for (int i = 0; i < SDRA_NB_ORIGINAL_BLOCKS; ++i)
            if (!filled[i]) { complete = 0; break; }
        if (!complete) continue;

        // Push to DUC via DMA ping-pong
        void *dma_buf = s_tx_chan.buf[s_tx_chan.cur];
        assemble_frame_into((uint32_t *)dma_buf, blocks);
        if (ebaz_dma_start(&s_tx_chan) != 0) {
            ++s_stats.blocks_dropped;
        } else {
            ebaz_dma_wait(&s_tx_chan, 1000);
            ebaz_dma_swap(&s_tx_chan);
            ++s_stats.frames_consumed;
        }
        memset(filled, 0, sizeof(filled));
        have_meta = 0;
    }
}

void tx_task_get_stats(tx_task_stats_t *out) { if (out) *out = s_stats; }

int tx_task_start(void)
{
    s_tx_chan = g_tx_chan;
    return (xTaskCreate(tx_task_fn, "tx_task", 4 * 1024, NULL,
                        tskIDLE_PRIORITY + 3, NULL) == pdPASS) ? 0 : -1;
}

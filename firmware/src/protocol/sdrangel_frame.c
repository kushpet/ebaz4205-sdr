// firmware/src/protocol/sdrangel_frame.c
// Helpers for assembling/inspecting SDRAngel "Remote" wire blocks.

#include "sdrangel_frame.h"
#include "FreeRTOS.h"
#include "task.h"
#include <string.h>

// Standard CRC-32 table (poly 0xEDB88320, reflected).
static uint32_t s_crc_table[256];
static int      s_crc_init = 0;

static void crc_init_once(void)
{
    if (s_crc_init) return;
    for (uint32_t i = 0; i < 256; ++i) {
        uint32_t c = i;
        for (int k = 0; k < 8; ++k)
            c = (c & 1) ? (0xEDB88320U ^ (c >> 1)) : (c >> 1);
        s_crc_table[i] = c;
    }
    s_crc_init = 1;
}

uint32_t sdra_crc32(const void *data, size_t len)
{
    crc_init_once();
    const uint8_t *p = (const uint8_t *)data;
    uint32_t       c = 0xFFFFFFFFU;
    while (len--) c = s_crc_table[(c ^ *p++) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFU;
}

void sdra_meta_fill(sdra_block_t *blk,
                    uint16_t frame_index,
                    uint64_t center_frequency_hz,
                    uint32_t sample_rate,
                    uint8_t  nb_fec_blocks)
{
    memset(blk, 0, sizeof(*blk));

    blk->header.frame_index  = frame_index;
    blk->header.block_index  = 0;
    blk->header.sample_bytes = 2;
    blk->header.sample_bits  = 16;

    sdra_meta_t *m = &blk->payload.meta;
    m->center_frequency_hz = center_frequency_hz;
    m->sample_rate         = sample_rate;
    m->sample_bytes        = 2;
    m->sample_bits         = 16;
    m->nb_original_blocks  = SDRA_NB_ORIGINAL_BLOCKS;
    m->nb_fec_blocks       = nb_fec_blocks;
    m->device_index        = 0;
    m->channel_index       = 0;
    // SDRAngel divides by tv_sec/tv_usec deltas in its skew estimator;
    // constant zeros trip a SIGFPE. Use FreeRTOS tick (1 kHz) as a
    // monotonic substitute.
    uint32_t tick_ms = (uint32_t)xTaskGetTickCount();
    m->tv_sec              = tick_ms / 1000U;
    m->tv_usec             = (tick_ms % 1000U) * 1000U;

    // CRC is over everything up to (but not including) the crc32 field
    m->crc32 = sdra_crc32(m, sizeof(*m) - sizeof(m->crc32));
}

void sdra_iq_header_fill(sdra_block_t *blk,
                         uint16_t frame_index,
                         uint8_t  iq_block_index)
{
    blk->header.frame_index  = frame_index;
    blk->header.block_index  = iq_block_index;
    blk->header.sample_bytes = 2;
    blk->header.sample_bits  = 16;
    blk->header.filler       = 0;
    blk->header.filler2      = 0;
}

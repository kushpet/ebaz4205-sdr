// firmware/src/protocol/iq_convert.c
#include "iq_convert.h"

static inline int16_t sat16(int32_t v)
{
    if (v >  32767) return  32767;
    if (v < -32768) return -32768;
    return (int16_t)v;
}

void iq_copy_dma_to_wire(int16_t *wire_iq,
                         const uint32_t *dma_buf,
                         size_t n_samples,
                         int32_t gain_q15)
{
    for (size_t i = 0; i < n_samples; ++i) {
        uint32_t w = dma_buf[i];
        int16_t  I = (int16_t)(w & 0xFFFFu);
        int16_t  Q = (int16_t)(w >> 16);
        if (gain_q15 != 32767) {
            I = sat16(((int32_t)I * gain_q15) >> 15);
            Q = sat16(((int32_t)Q * gain_q15) >> 15);
        }
        wire_iq[2*i + 0] = I;
        wire_iq[2*i + 1] = Q;
    }
}

void iq_copy_wire_to_dma(uint32_t *dma_buf,
                         const int16_t *wire_iq,
                         size_t n_samples,
                         int32_t gain_q15)
{
    for (size_t i = 0; i < n_samples; ++i) {
        int16_t I = wire_iq[2*i + 0];
        int16_t Q = wire_iq[2*i + 1];
        if (gain_q15 != 32767) {
            I = sat16(((int32_t)I * gain_q15) >> 15);
            Q = sat16(((int32_t)Q * gain_q15) >> 15);
        }
        dma_buf[i] = ((uint32_t)(uint16_t)Q << 16) | (uint32_t)(uint16_t)I;
    }
}

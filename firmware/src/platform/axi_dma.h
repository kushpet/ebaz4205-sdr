#ifndef EBAZ_AXI_DMA_H
#define EBAZ_AXI_DMA_H

#include <stdint.h>
#include <stddef.h>

#include "FreeRTOS.h"
#include "semphr.h"

// Ring of two ping-pong buffers.  EBAZ_DMA_BUF_BYTES is the size of each
// half-buffer; pick something that maps to a useful number of IQ samples.
//
// Default: 64 KB per buffer = 16384 IQ samples (32-bit each) ≈ 16 ms at
// 1 MS/s I/Q (decimation R=60). Fits comfortably in the 128 MB DMA region.
#define EBAZ_DMA_BUF_BYTES   (64 * 1024)
#define EBAZ_DMA_BUF_COUNT   2

typedef struct {
    uint32_t base;        // EBAZ_DMA0_BASE / EBAZ_DMA1_BASE
    int      direction;   // 0 = S2MM (RX, ADC->DDR), 1 = MM2S (TX, DDR->DAC)
    void    *buf[EBAZ_DMA_BUF_COUNT];
    size_t   buf_len;
    int      cur;         // current ping/pong index
    SemaphoreHandle_t done_sem;  // given by ISR on transfer complete
} ebaz_dma_chan_t;

// Initialise both channels and connect ISRs to the GIC.
// On success returns 0 and fills the two channel handles.
int  ebaz_dma_init(ebaz_dma_chan_t *rx, ebaz_dma_chan_t *tx);

// Kick off a transfer on the current ping/pong slot. Returns 0 on success.
int  ebaz_dma_start(ebaz_dma_chan_t *ch);

// Wait (blocking) until the in-flight transfer completes.  Returns 0 on
// success, -1 on timeout.
int  ebaz_dma_wait(ebaz_dma_chan_t *ch, uint32_t timeout_ms);

// Switch ping/pong and return pointer to the *just-completed* buffer (the
// one safe to read for RX or write for TX).
void *ebaz_dma_swap(ebaz_dma_chan_t *ch);

#endif

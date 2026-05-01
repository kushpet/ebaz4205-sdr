#ifndef EBAZ_IQ_CONVERT_H
#define EBAZ_IQ_CONVERT_H

#include <stdint.h>
#include <stddef.h>

// FPGA <-> wire format helpers.
//
// On the FPGA AXI-Stream side, the DDC outputs 32-bit words packed as
//   bits[31:16] = Q (signed 16-bit), bits[15:0] = I (signed 16-bit).
// The wire format is the same little-endian layout (host & ARM are
// little-endian, and the FPGA writes 32-bit words to DDR in the same
// order), so the "conversion" is mostly a memcpy with optional gain.
//
// Helpers are kept in case we later need byte-swap or 12-bit packing.

// Copy `n_samples` complex samples from a DMA buffer into an IQ payload
// (interleaved I,Q int16 little-endian).  `gain_q15` scales by gain/32768
// (use 32767 for unity gain, or 0 to mute).
void iq_copy_dma_to_wire(int16_t       *wire_iq,
                         const uint32_t *dma_buf,
                         size_t          n_samples,
                         int32_t         gain_q15);

void iq_copy_wire_to_dma(uint32_t       *dma_buf,
                         const int16_t  *wire_iq,
                         size_t          n_samples,
                         int32_t         gain_q15);

#endif

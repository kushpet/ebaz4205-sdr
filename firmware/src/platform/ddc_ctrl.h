#ifndef EBAZ_DDC_CTRL_H
#define EBAZ_DDC_CTRL_H

#include <stdint.h>

// AXI-Lite register offsets — match ddc_top.v / duc_top.v.
#define DDC_REG_NCO_FREQ           0x00
#define DDC_REG_DEC_RATE           0x04
#define DDC_REG_STATUS             0x08
#define DDC_REG_SAMPLES_PER_PACKET 0x0C

#define DUC_REG_NCO_FREQ   0x00
#define DUC_REG_INT_RATE   0x04
#define DUC_REG_DAC_CTRL   0x08

// Sample rate at the ADC/DAC pins. Used to compute NCO frequency word.
#define EBAZ_FS_HZ         60000000ULL

// Convert Hz to 32-bit phase-increment for the NCO LUT
// (freq_word = fc * 2^32 / fs).
static inline uint32_t ebaz_freq_to_word(int32_t fc_hz)
{
    int64_t  s = (int64_t)fc_hz;
    uint64_t w = ((s < 0 ? -s : s) * (1ULL << 32)) / EBAZ_FS_HZ;
    return (uint32_t)(s < 0 ? -(int32_t)w : (int32_t)w);
}

// DDC (RX) controls
void     ddc_set_frequency(int32_t fc_hz);
void     ddc_set_decimation(uint8_t r);    // 15, 30, 60, 120
uint32_t ddc_get_status(void);              // bit0 overflow, bit1 lock
// Number of 32-bit AXI-Stream beats between TLAST pulses; must equal the
// AXI DMA buffer length (in samples) — direct-register mode needs TLAST
// on the last beat to signal completion.
void     ddc_set_samples_per_packet(uint32_t n);

// DUC (TX) controls
void duc_set_frequency(int32_t fc_hz);
void duc_set_interpolation(uint8_t r);
void duc_set_pd(int on);
// Debug: when on, DAC outputs offset-binary cos(2π·DUC_NCO·t) directly
// (bypasses HB/CIC/mixer). Use for DAC→ADC loopback stimulus.
void duc_set_dac_test_mode(int on);

// Convenience: set both NCOs to the same frequency (transceiver mode)
static inline void sdr_set_frequency(int32_t fc_hz)
{
    ddc_set_frequency(fc_hz);
    duc_set_frequency(fc_hz);
}

// Convenience: pick the same decimation/interpolation
static inline void sdr_set_rate(uint8_t r)
{
    ddc_set_decimation(r);
    duc_set_interpolation(r);
}

#endif

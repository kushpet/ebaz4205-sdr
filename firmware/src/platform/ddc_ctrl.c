// firmware/src/platform/ddc_ctrl.c
#include "ddc_ctrl.h"
#include "platform_init.h"
#include "xil_io.h"

void ddc_set_frequency(int32_t fc_hz)
{
    Xil_Out32(EBAZ_DDC_BASE + DDC_REG_NCO_FREQ, ebaz_freq_to_word(fc_hz));
}

void ddc_set_decimation(uint8_t r)
{
    Xil_Out32(EBAZ_DDC_BASE + DDC_REG_DEC_RATE, (uint32_t)r);
}

uint32_t ddc_get_status(void)
{
    return Xil_In32(EBAZ_DDC_BASE + DDC_REG_STATUS);
}

void ddc_set_samples_per_packet(uint32_t n)
{
    Xil_Out32(EBAZ_DDC_BASE + DDC_REG_SAMPLES_PER_PACKET, n);
}

void duc_set_frequency(int32_t fc_hz)
{
    Xil_Out32(EBAZ_DUC_BASE + DUC_REG_NCO_FREQ, ebaz_freq_to_word(fc_hz));
}

void duc_set_interpolation(uint8_t r)
{
    Xil_Out32(EBAZ_DUC_BASE + DUC_REG_INT_RATE, (uint32_t)r);
}

void duc_set_pd(int on)
{
    uint32_t v = Xil_In32(EBAZ_DUC_BASE + DUC_REG_DAC_CTRL);
    v = (v & ~1U) | (on ? 1U : 0U);
    Xil_Out32(EBAZ_DUC_BASE + DUC_REG_DAC_CTRL, v);
}

void duc_set_dac_test_mode(int on)
{
    uint32_t v = Xil_In32(EBAZ_DUC_BASE + DUC_REG_DAC_CTRL);
    v = (v & ~(1U << 4)) | (on ? (1U << 4) : 0U);
    Xil_Out32(EBAZ_DUC_BASE + DUC_REG_DAC_CTRL, v);
}

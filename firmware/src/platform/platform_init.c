// firmware/src/platform/platform_init.c
// Zynq-7010 platform setup for the SDR firmware.

#include "platform_init.h"

#include "xil_cache.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xparameters.h"

// ARMv7-A 1 MB MMU sections; mark whole DMA region as
// "Shared device" -> non-cacheable, non-bufferable.
//
// Xilinx Xil_SetTlbAttributes() takes a 1 MB-aligned VA and a 32-bit
// attribute word. Constants from xil_mmu.h:
//   NORM_NONCACHE = 0x11DE2 (Shared, Non-cached)
#ifndef NORM_NONCACHE
#define NORM_NONCACHE 0x11DE2U
#endif

int platform_init(void)
{
    // 1. Caches: L1 D/I + L2 — enabled by default by FSBL/translation_table.
    Xil_DCacheEnable();
    Xil_ICacheEnable();

    // 2. Mark the DMA region non-cacheable (1 MB granularity).
    for (uint32_t va = EBAZ_DMA_REGION_BASE;
         va < EBAZ_DMA_REGION_BASE + EBAZ_DMA_REGION_SIZE;
         va += 0x100000U) {
        Xil_SetTlbAttributes(va, NORM_NONCACHE);
    }

    // 3. Flush after attribute change.
    Xil_DCacheFlush();
    return 0;
}

void platform_banner(void)
{
    xil_printf("\r\n");
    xil_printf("====================================================\r\n");
    xil_printf("  EBAZ4205 SDR firmware (bare-metal + FreeRTOS)\r\n");
    xil_printf("  Build: " __DATE__ " " __TIME__ "\r\n");
    xil_printf("  DMA non-cached region: 0x%08x .. 0x%08x\r\n",
               EBAZ_DMA_REGION_BASE,
               EBAZ_DMA_REGION_BASE + EBAZ_DMA_REGION_SIZE - 1);
    xil_printf("  DDC base: 0x%08x   DUC base: 0x%08x\r\n",
               EBAZ_DDC_BASE, EBAZ_DUC_BASE);
    xil_printf("====================================================\r\n");
}

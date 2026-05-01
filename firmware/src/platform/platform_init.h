#ifndef EBAZ_PLATFORM_INIT_H
#define EBAZ_PLATFORM_INIT_H

#include <stdint.h>

// PS-side hardware addresses (from create_bd.tcl, see CLAUDE.md address map)
#define EBAZ_DMA0_BASE     0x40400000U  // ADC -> DDR (S2MM)
#define EBAZ_DMA1_BASE     0x40420000U  // DDR -> DAC (MM2S)
#define EBAZ_DDC_BASE      0x43C00000U
#define EBAZ_DUC_BASE      0x43C01000U

// IRQ_F2P[1:0] from xlconcat in create_bd.tcl
//   bit 0 -> dma0.s2mm_introut  -> XPAR_FABRIC_AXI_DMA_0_S2MM_INTROUT_INTR (61)
//   bit 1 -> dma1.mm2s_introut  -> XPAR_FABRIC_AXI_DMA_1_MM2S_INTROUT_INTR (62)
#define EBAZ_IRQ_DMA0_S2MM 61U
#define EBAZ_IRQ_DMA1_MM2S 62U

// DDR layout. EBAZ4205 has 256 MB DDR (0x0000_0000 .. 0x0FFF_FFFF).
// Linker (lscript.ld) keeps code/heap/stack below 0x0800_0000.
// Above 0x0800_0000 is reserved for non-cached DMA buffers (mapped via
// platform_init_dma_region()).
#define EBAZ_DMA_REGION_BASE   0x08000000U
#define EBAZ_DMA_REGION_SIZE   0x08000000U  // 128 MB

// Initialise:
//   - cache (L1, L2)
//   - MMU translation: mark EBAZ_DMA_REGION_BASE as Strongly Ordered / non-cached
//   - GIC for FreeRTOS interrupts
//   - UART0 for stdout
// Must be called once from main() *before* any FreeRTOS API.
int platform_init(void);

// Optional: dump simple status to UART (uses xil_printf).
void platform_banner(void);

#endif

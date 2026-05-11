// firmware/src/main.c
// EBAZ4205 SDR firmware entry point.
//
// Order of operations:
//   1. Bare-metal hardware init (caches, MMU, UART)
//   2. FreeRTOS scheduler boots a one-shot init task
//   3. Init task: GIC -> lwIP/GEM0/IP101G -> DMA -> sdra_tcp_server
//   4. Init task self-deletes; the SDR runs off the TCP server task.

#include "FreeRTOS.h"
#include "task.h"

#include "platform/platform_init.h"
#include "platform/axi_dma.h"
#include "platform/ddc_ctrl.h"
#include "network/net_init.h"
#include "network/sdra_tcp_server.h"

#include "xil_printf.h"

// DMA channel handles. Populated by ebaz_dma_init below; sdra_tcp_server
// reads g_rx_chan to pump IQ. g_tx_chan is left initialised but unused
// until the TX path is rebuilt.
ebaz_dma_chan_t g_rx_chan;
ebaz_dma_chan_t g_tx_chan;

static void boot_task(void *arg)
{
    (void)arg;

    // Networking first (creates the GIC + lwIP and runs GEM0 init in
    // its own helper task). Block until the netif is administratively
    // up so the TCP listener doesn't try to bind before there's a
    // route.
    net_init();
    if (net_wait_up(8000) != 0)
        xil_printf("[boot] netif still down after 8 s — continuing\r\n");

    // DMA needs the GIC, which net_init set up.
    if (ebaz_dma_init(&g_rx_chan, &g_tx_chan) != 0) {
        xil_printf("[boot] DMA init failed\r\n");
        vTaskDelete(NULL);
        return;
    }

    // Default DSP settings: 7.1 MHz centre, R=30 (1 MS/s I/Q out).
    sdr_set_frequency(7100000);
    sdr_set_rate(30);
    duc_set_pd(0);

    // For DAC→ADC loopback debug, call duc_set_dac_test_mode(1) here;
    // off by default so the DAC doesn't radiate the NCO carrier in-band
    // during antenna RX testing.

    // Match TLAST burst to the DMA buffer: 64 KiB / 4 B per beat = 16384.
    ddc_set_samples_per_packet(EBAZ_DMA_BUF_BYTES / 4);

    // Serve SDRangel RemoteTCPInput on :1234 (rtl_tcp-compatible).
    sdra_tcp_start(1234);

    xil_printf("[boot] SDR firmware ready\r\n");
    vTaskDelete(NULL);
}

// Override the BSP's weak vApplicationAssert: scan the stack for code
// pointers so the call chain to a failed configASSERT is recoverable
// without a debugger. (Keep it — used to find the lwip_init / mem_mutex
// initialisation bug; useful next time something else asserts.)
__attribute__((noinline))
void vApplicationAssert(const char *file, uint32_t line)
{
    register uintptr_t sp_now asm ("sp");
    const uintptr_t text_lo = 0x00100000;     // our DDR text base
    const uintptr_t text_hi = 0x00400000;

    xil_printf("Assert failed in file %s, line %lu  sp=0x%08x\r\n",
               file, (unsigned long)line, (unsigned)sp_now);

    uint32_t *p = (uint32_t *)sp_now;
    int found = 0;
    for (int i = 0; i < 64 && found < 8; i++) {
        uint32_t v = p[i];
        if (v >= text_lo && v < text_hi && (v & 1) == 0) {
            xil_printf("  stack[%2d] = 0x%08x  (code ptr)\r\n", i, v);
            found++;
        }
    }
    for (;;) { __asm volatile("nop"); }
}

int main(void)
{
    platform_init();
    platform_banner();

    if (xTaskCreate(boot_task, "boot", 4 * 1024, NULL,
                    tskIDLE_PRIORITY + 4, NULL) != pdPASS) {
        xil_printf("[main] boot task creation failed\r\n");
        return -1;
    }

    vTaskStartScheduler();

    // Should never reach here.
    for (;;) ;
    return 0;
}

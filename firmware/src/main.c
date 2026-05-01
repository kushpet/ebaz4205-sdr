// firmware/src/main.c
// EBAZ4205 SDR firmware entry point.
//
// Order of operations:
//   1. Bare-metal hardware init (caches, MMU, UART)
//   2. FreeRTOS scheduler boots a one-shot init task
//   3. Init task: GIC -> lwIP/GEM0/IP101G -> DMA -> tasks (rx, tx, http)
//   4. Init task self-deletes; the SDR runs entirely off the workers.

#include "FreeRTOS.h"
#include "task.h"

#include "platform/platform_init.h"
#include "platform/axi_dma.h"
#include "platform/ddc_ctrl.h"
#include "network/net_init.h"
#include "network/http_rest.h"
#include "tasks/rx_task.h"
#include "tasks/tx_task.h"

#include "lwip/ip4_addr.h"
#include "xil_printf.h"

// DMA channel handles shared with tasks/rx_task.c and tasks/tx_task.c.
ebaz_dma_chan_t g_rx_chan;
ebaz_dma_chan_t g_tx_chan;

static void boot_task(void *arg)
{
    (void)arg;

    // Networking first (creates the GIC + lwIP and runs GEM0 init in
    // its own helper task — wait briefly for the netif to come up).
    net_init();
    vTaskDelay(pdMS_TO_TICKS(2000));

    // DMA needs the GIC, which net_init set up.
    if (ebaz_dma_init(&g_rx_chan, &g_tx_chan) != 0) {
        xil_printf("[boot] DMA init failed\r\n");
        vTaskDelete(NULL);
        return;
    }

    // Default DSP settings: 7.1 MHz centre, R=30 (1 MS/s I/Q out)
    sdr_set_frequency(7100000);
    sdr_set_rate(30);
    duc_set_pd(0);

    // Where to send the IQ stream (host PC running SDRAngel)
    ip4_addr_t host;
    IP4_ADDR(&host, 192, 168, 1, 10);
    rx_task_set_dest(&host, 9090);

    // Spawn workers
    rx_task_start();
    tx_task_start();
    http_rest_start(8888);

    xil_printf("[boot] SDR firmware ready\r\n");
    vTaskDelete(NULL);
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

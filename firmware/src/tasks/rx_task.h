#ifndef EBAZ_RX_TASK_H
#define EBAZ_RX_TASK_H

#include <stdint.h>
#include "lwip/ip4_addr.h"

// Configure remote endpoint that will receive the IQ stream from this
// device. Defaults: 192.168.1.10:9090 (set in rx_task.c).
void rx_task_set_dest(const ip4_addr_t *ip, uint16_t port);

// Spawn the RX-path FreeRTOS task. Runs forever; call after net_init().
int  rx_task_start(void);

// Snapshot of running rate / drops, useful for the REST GET handler.
typedef struct {
    uint64_t blocks_sent;
    uint64_t blocks_dropped;
    uint64_t frames_built;
} rx_task_stats_t;

void rx_task_get_stats(rx_task_stats_t *out);

#endif

#ifndef EBAZ_TX_TASK_H
#define EBAZ_TX_TASK_H

#include <stdint.h>

int tx_task_start(void);

typedef struct {
    uint64_t blocks_received;
    uint64_t blocks_dropped;
    uint64_t frames_consumed;
} tx_task_stats_t;

void tx_task_get_stats(tx_task_stats_t *out);

#endif

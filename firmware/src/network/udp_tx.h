#ifndef EBAZ_UDP_TX_H
#define EBAZ_UDP_TX_H

#include <stdint.h>

#include "lwip/ip4_addr.h"

// One-shot init: configures the destination of the IQ stream we send to
// SDRAngel's "Remote Source" plugin. Call from rx_task before the loop.
int udp_tx_open(const ip4_addr_t *dst, uint16_t port);

// Send one already-built 512-byte super-block. Returns 0 on success, -1
// on lwIP error.  Safe to call from a FreeRTOS task; uses NETCONN.
int udp_tx_send_block(const void *block512);

void udp_tx_close(void);

#endif

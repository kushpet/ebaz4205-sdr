#ifndef EBAZ_UDP_RX_H
#define EBAZ_UDP_RX_H

#include <stdint.h>

// Bind a UDP listener and pull the next 512-byte super-block into `out`.
// Blocks until a datagram arrives or `timeout_ms` elapses.
// Returns 0 on success, -1 on timeout/error.
int udp_rx_open(uint16_t port);
int udp_rx_recv_block(void *out_block512, uint32_t timeout_ms);
void udp_rx_close(void);

#endif

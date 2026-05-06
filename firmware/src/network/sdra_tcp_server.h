#ifndef EBAZ_SDRA_TCP_SERVER_H
#define EBAZ_SDRA_TCP_SERVER_H

#include <stdint.h>

// Start the SDRangel RemoteTCPInput-compatible TCP server task.
// Listens on `port` (canonically 1234), accepts one client at a time,
// sends an rtl_tcp RTL0 greeting, then streams I/Q.
//
// v0 (skeleton): writes 0x80-filled zero baseband forever.
// v1 (step 3):   pumps DDC DMA buffers.
// v2 (step 4):   prepends SDRA extended header for native int16 I/Q.
// v3 (step 5):   handles 5-byte client commands (set freq / rate).
//
// Returns 0 on task creation success, -1 otherwise.
int sdra_tcp_start(uint16_t port);

#endif

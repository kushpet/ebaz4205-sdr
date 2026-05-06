#ifndef EBAZ_SDRA_TCP_SERVER_H
#define EBAZ_SDRA_TCP_SERVER_H

#include <stdint.h>

// Start the SDRangel RemoteTCPInput-compatible TCP server task.
// Listens on `port` (canonically 1234), accepts one client at a time,
// sends a 128-byte SDRA metadata header, streams little-endian int16
// I/Q pairs straight from the DDC DMA buffer, and honours 5-byte
// client commands (setCenterFrequency / setSampleRate).
//
// Returns 0 on task creation success, -1 otherwise.
int sdra_tcp_start(uint16_t port);

#endif

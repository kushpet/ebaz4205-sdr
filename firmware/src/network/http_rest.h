#ifndef EBAZ_HTTP_REST_H
#define EBAZ_HTTP_REST_H

#include <stdint.h>

// Minimal HTTP/1.0 server on TCP port 8888 for SDRAngel-style control.
// Endpoints implemented:
//   GET  /sdrangel
//        -> {"name":"EBAZ4205","version":"...","capabilities":...}
//
//   GET  /sdrangel/deviceset/0/device/run
//        -> {"state":"ok","frequency":fc,"sampleRate":fs}
//
//   PATCH /sdrangel/deviceset/0/device/settings
//        body: {"centerFrequency":12345678, "log2Decim":N}
//        -> 200 {"state":"ok"}
//
// Returns immediately after spawning the listener task.
int http_rest_start(uint16_t port);

#endif

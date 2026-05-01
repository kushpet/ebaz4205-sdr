// firmware/src/network/http_rest.c
// Bare-minimum HTTP/1.0 server. Not a real REST framework — just enough
// for SDRAngel's "Remote Output" / "Remote Input" device-set commands.
// Body parsing is line-based "key:value" / tiny JSON; we look for the
// two fields we care about ("centerFrequency", "log2Decim") and ignore
// anything else.

#include "http_rest.h"
#include "../platform/ddc_ctrl.h"

#include "lwip/api.h"
#include "FreeRTOS.h"
#include "task.h"
#include "xil_printf.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Globals shared with rx_task.c (used to stamp the meta block).
uint64_t g_center_frequency_hz = 7100000;  // default 7.1 MHz (40m band)
uint8_t  g_dec_rate            = 30;       // default = 1 MS/s I/Q

static int find_field_int(const char *body, const char *key, long *out)
{
    const char *p = strstr(body, key);
    if (!p) return -1;
    p = strchr(p, ':');
    if (!p) return -1;
    *out = strtol(p + 1, NULL, 10);
    return 0;
}

static void apply_settings(const char *body)
{
    long v;
    if (find_field_int(body, "centerFrequency", &v) == 0) {
        g_center_frequency_hz = (uint64_t)v;
        sdr_set_frequency((int32_t)v);
    }
    if (find_field_int(body, "log2Decim", &v) == 0) {
        // SDRAngel uses log2 of decimation; convert to linear (clamped).
        long r = 1L << v;
        if (r < 15)  r = 15;
        if (r > 120) r = 120;
        g_dec_rate = (uint8_t)r;
        sdr_set_rate(g_dec_rate);
    }
}

static void send_response(struct netconn *c,
                          const char     *status,
                          const char     *body)
{
    char hdr[160];
    int  blen = (int)strlen(body);
    int  hlen = snprintf(hdr, sizeof(hdr),
        "HTTP/1.0 %s\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %d\r\n"
        "Connection: close\r\n\r\n",
        status, blen);
    netconn_write(c, hdr, hlen, NETCONN_COPY);
    netconn_write(c, body, blen, NETCONN_COPY);
}

static void handle_one(struct netconn *c, const char *req, size_t len)
{
    // Find body (CRLFCRLF)
    const char *body = "";
    const char *crlf = strstr(req, "\r\n\r\n");
    if (crlf) body = crlf + 4;
    (void)len;

    if (!strncmp(req, "GET /sdrangel ", 14) ||
        !strncmp(req, "GET /sdrangel\r", 14)) {
        send_response(c, "200 OK",
            "{\"name\":\"EBAZ4205\",\"version\":\"1.0\","
             "\"streamRate\":1000000,\"deviceHwId\":\"EBAZ4205\"}");
    } else if (!strncmp(req, "GET /sdrangel/deviceset/0/device/run", 36)) {
        char body_buf[128];
        snprintf(body_buf, sizeof(body_buf),
                 "{\"state\":\"running\",\"frequency\":%llu,\"sampleRate\":%u}",
                 (unsigned long long)g_center_frequency_hz,
                 (unsigned)(60000000U / (g_dec_rate * 2U)));
        send_response(c, "200 OK", body_buf);
    } else if (!strncmp(req, "PATCH /sdrangel/deviceset/0/device/settings", 43)) {
        apply_settings(body);
        send_response(c, "200 OK", "{\"state\":\"ok\"}");
    } else {
        send_response(c, "404 Not Found", "{\"error\":\"unknown\"}");
    }
}

static void http_task(void *arg)
{
    uint16_t        port = (uint16_t)(uintptr_t)arg;
    struct netconn *lst  = netconn_new(NETCONN_TCP);
    if (!lst) { vTaskDelete(NULL); return; }
    netconn_bind(lst, IP4_ADDR_ANY, port);
    netconn_listen(lst);

    xil_printf("[http] listening on :%u\r\n", port);

    for (;;) {
        struct netconn *c = NULL;
        if (netconn_accept(lst, &c) != ERR_OK || !c) continue;

        // Read up to 4 KB request
        struct netbuf *nb = NULL;
        char           req[4096];
        size_t         got = 0;
        while (got < sizeof(req) - 1 &&
               netconn_recv(c, &nb) == ERR_OK && nb) {
            void *d; u16_t n;
            if (netbuf_data(nb, &d, &n) == ERR_OK) {
                size_t take = (got + n < sizeof(req) - 1) ? n : (sizeof(req) - 1 - got);
                memcpy(req + got, d, take);
                got += take;
            }
            netbuf_delete(nb); nb = NULL;
            // Stop after we have headers+body (cheap heuristic)
            req[got] = 0;
            if (strstr(req, "\r\n\r\n")) break;
        }
        req[got] = 0;
        if (got > 0) handle_one(c, req, got);
        netconn_close(c);
        netconn_delete(c);
    }
}

int http_rest_start(uint16_t port)
{
    return (xTaskCreate(http_task, "http_rest", 4 * 1024,
                        (void *)(uintptr_t)port,
                        tskIDLE_PRIORITY + 1, NULL) == pdPASS) ? 0 : -1;
}

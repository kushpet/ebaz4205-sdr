// firmware/src/network/udp_rx.c
#include "udp_rx.h"
#include "../protocol/sdrangel_frame.h"

#include "lwip/api.h"
#include <string.h>

static struct netconn *s_conn;

int udp_rx_open(uint16_t port)
{
    s_conn = netconn_new(NETCONN_UDP);
    if (!s_conn) return -1;
    if (netconn_bind(s_conn, IP4_ADDR_ANY, port) != ERR_OK) return -1;
    return 0;
}

int udp_rx_recv_block(void *out_block512, uint32_t timeout_ms)
{
    if (!s_conn) return -1;
#if LWIP_SO_RCVTIMEO
    netconn_set_recvtimeout(s_conn, timeout_ms);
#else
    (void)timeout_ms;       // recv blocks indefinitely if SO_RCVTIMEO is off
#endif
    struct netbuf *nb = NULL;
    if (netconn_recv(s_conn, &nb) != ERR_OK) return -1;
    void *data; u16_t len;
    if (netbuf_data(nb, &data, &len) != ERR_OK || len != SDRA_BLOCK_SIZE) {
        netbuf_delete(nb);
        return -1;
    }
    memcpy(out_block512, data, SDRA_BLOCK_SIZE);
    netbuf_delete(nb);
    return 0;
}

void udp_rx_close(void)
{
    if (s_conn) { netconn_delete(s_conn); s_conn = NULL; }
}

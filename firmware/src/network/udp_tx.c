// firmware/src/network/udp_tx.c
// UDP datagram sink (LWIP NETCONN, blocking send).

#include "udp_tx.h"
#include "../protocol/sdrangel_frame.h"

#include "lwip/api.h"
#include "lwip/netbuf.h"
#include "xil_printf.h"

static struct netconn *s_conn;
static ip4_addr_t      s_dst;
static uint16_t        s_port;

int udp_tx_open(const ip4_addr_t *dst, uint16_t port)
{
    s_dst  = *dst;
    s_port = port;
    s_conn = netconn_new(NETCONN_UDP);
    if (!s_conn) return -1;
    if (netconn_bind(s_conn, IP4_ADDR_ANY, 0) != ERR_OK) return -1;
    return 0;
}

int udp_tx_send_block(const void *block512)
{
    if (!s_conn) return -1;
    struct netbuf *nb = netbuf_new();
    if (!nb) return -1;
    // Reference the caller's buffer (no copy). Caller must keep it alive
    // until this function returns.
    if (netbuf_ref(nb, block512, SDRA_BLOCK_SIZE) != ERR_OK) {
        netbuf_delete(nb);
        return -1;
    }
    err_t e = netconn_sendto(s_conn, nb, &s_dst, s_port);
    netbuf_delete(nb);
    if (e != ERR_OK) {
        // Transient errors are common when the host rate-limits the UDP
        // pipe; log occasionally and drop.
        static int seen;
        if ((seen++ & 0x3FF) == 0) xil_printf("[udp_tx] send err=%d\r\n", e);
        return -1;
    }
    return 0;
}

void udp_tx_close(void)
{
    if (s_conn) {
        netconn_delete(s_conn);
        s_conn = NULL;
    }
}

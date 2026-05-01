#!/usr/bin/env python3
"""
Minimal SDRAngel Remote-Input emulator (PC side).

Listens on UDP for 512-byte super-blocks coming from the EBAZ4205, parses
them, and writes the IQ stream to a raw little-endian int16 file.
Useful for verifying the device end-to-end before plugging real SDRAngel.

Usage:
    ./test_udp_rx.py --port 9090 --out iq.s16
"""

import argparse
import socket
import struct
import sys
import time
import zlib

BLOCK_SIZE        = 512
HEADER_SIZE       = 8
PAYLOAD_SIZE      = BLOCK_SIZE - HEADER_SIZE
NB_ORIGINAL       = 128
SAMPLES_PER_BLOCK = PAYLOAD_SIZE // 4   # 4 bytes per (I,Q) at 16-bit


def parse_header(buf):
    frame_index, block_index, sb, bits, _, _ = struct.unpack('<HBBBBH', buf[:HEADER_SIZE])
    return frame_index, block_index, sb, bits


def parse_meta(payload):
    fmt = '<QIBBBBBBII I'
    fields = struct.unpack(fmt, payload[:30])
    (cf, sr, sb, bits, nbo, nbf, di, ci, tvs, tvu, crc) = fields
    crc_calc = zlib.crc32(payload[:26]) & 0xFFFFFFFF
    return {
        "center_frequency_hz": cf,
        "sample_rate":         sr,
        "sample_bytes":        sb,
        "sample_bits":         bits,
        "nb_original_blocks":  nbo,
        "nb_fec_blocks":       nbf,
        "device_index":        di,
        "channel_index":       ci,
        "tv_sec":              tvs,
        "tv_usec":             tvu,
        "crc_ok":              crc == crc_calc,
        "crc":                 crc,
        "crc_calc":            crc_calc,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=9090)
    ap.add_argument('--bind', default='0.0.0.0')
    ap.add_argument('--out',  default=None, help='write raw int16 IQ here')
    ap.add_argument('--frames', type=int, default=0, help='stop after N frames (0=forever)')
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.bind, args.port))
    sock.settimeout(2.0)
    print(f"listening on {args.bind}:{args.port}")

    out = open(args.out, 'wb') if args.out else None
    cur_frame = None
    have = [None] * NB_ORIGINAL
    seen = 0
    frames_done = 0
    t0 = time.time()
    bytes_recv = 0

    try:
        while True:
            try:
                pkt, _ = sock.recvfrom(2048)
            except socket.timeout:
                print("[timeout — no packet for 2 s]")
                continue
            if len(pkt) != BLOCK_SIZE:
                continue
            bytes_recv += BLOCK_SIZE
            seen += 1

            fi, bi, sb, bits = parse_header(pkt)
            if cur_frame is None or fi != cur_frame:
                if cur_frame is not None:
                    # Flush whatever we have for the previous frame
                    iq_bytes = b''.join(have[1:NB_ORIGINAL] if all(x is not None for x in have[1:NB_ORIGINAL]) else [])
                    if iq_bytes and out:
                        out.write(iq_bytes)
                    if iq_bytes:
                        frames_done += 1
                cur_frame = fi
                have = [None] * NB_ORIGINAL

            if bi < NB_ORIGINAL:
                have[bi] = pkt[HEADER_SIZE:]

            if bi == 0:
                m = parse_meta(pkt[HEADER_SIZE:])
                if not m["crc_ok"]:
                    print(f"[meta CRC FAIL: got {m['crc']:08x} calc {m['crc_calc']:08x}]")
                else:
                    print(f"[meta] frame={fi} fc={m['center_frequency_hz']/1e6:.3f} MHz "
                          f"fs={m['sample_rate']} bytes={sb} bits={bits} "
                          f"nbo={m['nb_original_blocks']} nbf={m['nb_fec_blocks']}")
            if args.frames and frames_done >= args.frames:
                break
            if seen % 1000 == 0:
                dt = time.time() - t0
                print(f"  rx {seen} blocks ({bytes_recv/1024:.1f} KiB, "
                      f"{bytes_recv*8/(dt*1e6):.2f} Mbit/s)")
    finally:
        if out: out.close()
        sock.close()


if __name__ == '__main__':
    main()

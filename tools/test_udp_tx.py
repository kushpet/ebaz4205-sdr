#!/usr/bin/env python3
"""
Minimal SDRAngel Remote-Output emulator (PC side).

Reads a raw little-endian int16 IQ file (interleaved I,Q,I,Q,...) and
sends it to the EBAZ4205 as a stream of 512-byte SDRAngel super-blocks.
For each super-frame:
    block 0     = RemoteMetaDataFEC (with CRC32)
    blocks 1..127 = 126 IQ samples each (504 bytes)
No FEC for now.

Usage:
    ./test_udp_tx.py --host 192.168.1.100 --port 9090 \\
                     --in tone.s16 --fs 1000000 --fc 7100000
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
SAMPLES_PER_BLOCK = PAYLOAD_SIZE // 4

def build_header(frame_index, block_index):
    return struct.pack('<HBBBBH', frame_index & 0xFFFF,
                       block_index & 0xFF, 2, 16, 0, 0)

def build_meta(frame_index, fc_hz, fs_hz):
    h = build_header(frame_index, 0)
    body = bytearray(PAYLOAD_SIZE)
    meta_no_crc = struct.pack('<QIBBBBBBII',
                              int(fc_hz), int(fs_hz),
                              2, 16, NB_ORIGINAL, 0, 0, 0, 0, 0)
    crc = zlib.crc32(meta_no_crc) & 0xFFFFFFFF
    body[:30] = meta_no_crc + struct.pack('<I', crc)
    return h + bytes(body)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', required=True)
    ap.add_argument('--port', type=int, default=9090)
    ap.add_argument('--in',   dest='in_file', required=True)
    ap.add_argument('--fs',   type=int, default=1_000_000)
    ap.add_argument('--fc',   type=int, default=7_100_000)
    ap.add_argument('--rate-pace', type=float, default=1.0,
                    help='multiplier on the natural send pace')
    args = ap.parse_args()

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = (args.host, args.port)

    with open(args.in_file, 'rb') as f:
        data = f.read()

    samples_per_frame = (NB_ORIGINAL - 1) * SAMPLES_PER_BLOCK   # 16002
    bytes_per_frame_iq = samples_per_frame * 4
    nframes = len(data) // bytes_per_frame_iq
    print(f"sending {nframes} super-frames "
          f"({samples_per_frame * nframes / args.fs * 1000:.1f} ms of audio) "
          f"to {target}")

    period = (samples_per_frame / args.fs) / args.rate_pace
    fi = 0
    off = 0
    t0 = time.time()
    for k in range(nframes):
        s.sendto(build_meta(fi, args.fc, args.fs), target)
        for bi in range(1, NB_ORIGINAL):
            blk = data[off:off + 4*SAMPLES_PER_BLOCK]
            off += 4*SAMPLES_PER_BLOCK
            s.sendto(build_header(fi, bi) + blk, target)
        fi = (fi + 1) & 0xFFFF
        # Pace
        target_t = t0 + (k+1)*period
        dt = target_t - time.time()
        if dt > 0: time.sleep(dt)

    print("done.")

if __name__ == '__main__':
    main()

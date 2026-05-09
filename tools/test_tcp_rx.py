#!/usr/bin/env python3
# tools/test_tcp_rx.py
# Connect to the EBAZ4205 SDRangel-RemoteTCPInput server, parse the
# 128-byte SDRA header, optionally send setCenterFrequency /
# setSampleRate commands, and report on a couple seconds of int16 I/Q.
# Use this to verify the firmware data path independent of SDRangel —
# zero/near-zero variance points the finger at the DDC, not transport.
#
# Usage:
#   ./test_tcp_rx.py [--freq HZ] [--rate HZ] [--seconds N] [HOST] [PORT]
# Defaults: 192.168.2.100 1234, 2 seconds, no command sent.

import argparse
import socket
import struct

import numpy as np


parser = argparse.ArgumentParser()
parser.add_argument("--freq", type=int, default=None,
                    help="setCenterFrequency Hz before reading")
parser.add_argument("--rate", type=int, default=None,
                    help="setSampleRate Hz before reading")
parser.add_argument("--seconds", type=float, default=2.0)
parser.add_argument("host", nargs="?", default="192.168.2.100")
parser.add_argument("port", nargs="?", type=int, default=1234)
args = parser.parse_args()

HOST = args.host
PORT = args.port
CAPTURE_SECONDS = args.seconds


def be_u32(b, off):
    return struct.unpack(">I", b[off : off + 4])[0]


def be_u64(b, off):
    return struct.unpack(">Q", b[off : off + 8])[0]


def parse_meta(meta: bytes):
    assert len(meta) == 128, len(meta)
    magic = meta[:4].decode("ascii", errors="replace")
    return {
        "magic": magic,
        "device": be_u32(meta, 4),
        "freq_hz": be_u64(meta, 8),
        "device_sr": be_u32(meta, 24),
        "log2_decim": be_u32(meta, 28),
        "channel_sr": be_u32(meta, 52),
        "sample_bits": be_u32(meta, 56),
        "proto_rev": be_u32(meta, 60),
    }


def recv_exact(sock, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise EOFError(f"server closed after {len(buf)}/{n} bytes")
        buf.extend(chunk)
    return bytes(buf)


def send_cmd(sock, cmd, param):
    sock.sendall(struct.pack(">BI", cmd, param))


def main():
    print(f"connecting to {HOST}:{PORT}")
    s = socket.create_connection((HOST, PORT))
    s.settimeout(5.0)

    meta = recv_exact(s, 128)
    info = parse_meta(meta)
    for k, v in info.items():
        print(f"  {k:>12s} = {v}")

    if args.freq is not None:
        print(f"sending setCenterFrequency = {args.freq} Hz")
        send_cmd(s, 0x01, args.freq & 0xFFFFFFFF)
    if args.rate is not None:
        print(f"sending setSampleRate = {args.rate} Hz")
        send_cmd(s, 0x02, args.rate & 0xFFFFFFFF)

    bits = info["sample_bits"]
    if bits != 16:
        print(f"unexpected sample_bits={bits}; aborting")
        return

    sr = info["channel_sr"]
    if args.rate is not None:
        # Server snaps to R∈{15,30,60,120}; recompute what it actually picked.
        r = max(15, min(120, 30000000 // max(1, args.rate)))
        for snap in (15, 30, 60, 120):
            if r <= (15 if snap == 15 else (snap + (snap // 2)) // 1):
                r = snap
                break
        sr = 30000000 // r
        print(f"  (rate snapped to R={r} → channel_sr≈{sr})")
    n_samples = int(sr * CAPTURE_SECONDS)
    n_bytes = n_samples * 4  # 2 bytes I + 2 bytes Q
    print(f"capturing {n_samples} IQ samples ({n_bytes} B) at {sr} Sa/s")

    raw = recv_exact(s, n_bytes)
    s.close()

    iq = np.frombuffer(raw, dtype="<i2").reshape(-1, 2)
    i = iq[:, 0].astype(np.int32)
    q = iq[:, 1].astype(np.int32)

    print()
    print(f"  I  min={i.min():6d}  max={i.max():6d}  mean={i.mean():+8.2f}  "
          f"std={i.std():.2f}")
    print(f"  Q  min={q.min():6d}  max={q.max():6d}  mean={q.mean():+8.2f}  "
          f"std={q.std():.2f}")
    nonzero = np.count_nonzero(i) + np.count_nonzero(q)
    print(f"  nonzero samples: {nonzero}/{2 * len(i)} "
          f"({100.0 * nonzero / (2 * len(i)):.1f}%)")

    print()
    print("first 16 IQ samples (I, Q):")
    for k in range(16):
        print(f"    [{k:2d}]  I={i[k]:+6d}  Q={q[k]:+6d}")


if __name__ == "__main__":
    main()

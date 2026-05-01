#ifndef EBAZ_SDRANGEL_FRAME_H
#define EBAZ_SDRANGEL_FRAME_H

#include <stdint.h>
#include <stddef.h>

// SDRAngel "Remote Sink" / "Remote Source" UDP wire format.
// Source of truth: f4exb/sdrangel sdrbase/channel/remotedatablock.h
//
// One UDP datagram = one "super-block" of exactly 512 bytes:
//   [8-byte header] [504-byte payload]
//
// Block 0 of each super-frame carries `RemoteMetaDataFEC` (30 bytes
// followed by zeros).  Blocks 1..127 carry IQ samples (504 bytes / 4 B
// per complex sample = 126 samples per block at 16-bit I/Q).  Blocks
// 128..127+N are CM256 FEC parity (where N = nbFECBlocks).

#define SDRA_BLOCK_SIZE          512u
#define SDRA_HEADER_SIZE         8u
#define SDRA_PAYLOAD_SIZE        (SDRA_BLOCK_SIZE - SDRA_HEADER_SIZE)  // 504
#define SDRA_NB_ORIGINAL_BLOCKS  128u
#define SDRA_NB_IQ_BLOCKS        (SDRA_NB_ORIGINAL_BLOCKS - 1u)        // 127
#define SDRA_SAMPLES_PER_BLOCK   (SDRA_PAYLOAD_SIZE / 4u)              // 126

// CM256 maximum recovery (parity) block count.
#define SDRA_MAX_FEC_BLOCKS      128u

#define SDRA_DEFAULT_UDP_PORT    9090u

// 8-byte header. Little-endian on the wire (no byte-swap on x86/ARM).
typedef struct __attribute__((packed)) {
    uint16_t frame_index;     // wraps mod 65536
    uint8_t  block_index;     // 0..127 = original (0 = meta), 128..255 = parity
    uint8_t  sample_bytes;    // 2 or 4
    uint8_t  sample_bits;     // 8/16/24
    uint8_t  filler;          // 0
    uint16_t filler2;         // 0
} sdra_header_t;

_Static_assert(sizeof(sdra_header_t) == SDRA_HEADER_SIZE,
               "sdra_header_t must be 8 bytes");

// 30-byte metadata payload. Sits at the start of block 0's 504-byte
// payload (rest is zero-padded).
typedef struct __attribute__((packed)) {
    uint64_t center_frequency_hz;  // Hz
    uint32_t sample_rate;          // Hz, post-decimation
    uint8_t  sample_bytes;         // 2 or 4
    uint8_t  sample_bits;          // 8/16/24
    uint8_t  nb_original_blocks;   // = 128
    uint8_t  nb_fec_blocks;        // 0..128
    uint8_t  device_index;
    uint8_t  channel_index;
    uint32_t tv_sec;
    uint32_t tv_usec;
    uint32_t crc32;                // boost CRC-32 over preceding 26 bytes
} sdra_meta_t;

_Static_assert(sizeof(sdra_meta_t) == 30, "sdra_meta_t must be 30 bytes");

// Whole-block view: header + payload, 512 bytes total.
typedef struct __attribute__((packed)) {
    sdra_header_t header;
    union {
        uint8_t      raw[SDRA_PAYLOAD_SIZE];
        sdra_meta_t  meta;       // valid only for block 0
        struct __attribute__((packed)) {
            int16_t  iq[SDRA_SAMPLES_PER_BLOCK * 2]; // I,Q,I,Q,...
        } samples;                // valid for blocks 1..127
    } payload;
} sdra_block_t;

_Static_assert(sizeof(sdra_block_t) == SDRA_BLOCK_SIZE,
               "sdra_block_t must be 512 bytes");

// boost-style CRC-32 (poly 0xEDB88320, init 0xFFFFFFFF, refin/refout, xorout 0xFFFFFFFF).
uint32_t sdra_crc32(const void *data, size_t len);

// Fill a meta block. tv_sec/tv_usec are 0 if no RTC; SDRAngel tolerates this.
void sdra_meta_fill(sdra_block_t *blk,
                    uint16_t frame_index,
                    uint64_t center_frequency_hz,
                    uint32_t sample_rate,
                    uint8_t  nb_fec_blocks);

// Stamp an IQ block header in place.  `iq_block_index` ∈ 1..127.
void sdra_iq_header_fill(sdra_block_t *blk,
                         uint16_t frame_index,
                         uint8_t  iq_block_index);

#endif

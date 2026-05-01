#ifndef EBAZ_CM256_H
#define EBAZ_CM256_H

#include <stdint.h>
#include <stddef.h>

// Minimal CM256 façade for the SDR firmware.
//
// CM256 is a Cauchy-MDS Reed-Solomon block-erasure code over GF(256).
// Upstream: https://github.com/catid/cm256 (MIT) — re-used by SDRAngel
// via https://github.com/f4exb/cm256cc (GPLv3 fork with a C++ shim).
//
// Why this façade is intentionally minimal:
//   - The default super-frame has nb_fec_blocks = 0 (no FEC); the
//     `cm256_encode` / `cm256_decode` paths are dead in that case.
//   - Porting the full upstream implementation cleanly to bare metal
//     requires either the catid/cm256 submodule (drop-in C, no NEON
//     issues) or the cm256cc port (C++, drops SIMD).
//   - The build integration and Vitis BSP work is straightforward but
//     out of scope for the initial bring-up pass — see README/ports
//     section in CLAUDE.md.
//
// When FEC is enabled, replace this file with the upstream sources
// (drop catid/cm256 into firmware/third_party/cm256/ and link). The
// API below is compatible with that drop-in replacement.

typedef struct {
    uint8_t  original_count;     // <= 128
    uint8_t  recovery_count;     // <= 128
    uint16_t block_bytes;        // 504 in our use
} cm256_params_t;

typedef struct {
    void   *block;               // pointer to the 504-byte block payload
    uint8_t index;               // 0..255 (original or recovery index)
} cm256_block_t;

// Initialise GF(256) tables. Idempotent.
int  cm256_init(void);

// Compute m parity blocks given k originals.
// Returns 0 on success.
int  cm256_encode(cm256_params_t  params,
                  const cm256_block_t *originals,   // k blocks
                  void                 *recovery);   // m * block_bytes

// Recover missing originals.  `blocks` is an array of `k` blocks (any
// mix of originals and recovery, identified by `index`).
// On success, the original-indexed block payloads are filled in place.
int  cm256_decode(cm256_params_t  params,
                  cm256_block_t  *blocks);

#endif

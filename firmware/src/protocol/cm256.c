// firmware/src/protocol/cm256.c
// Stub implementation — see cm256.h for context.  Returns success when
// recovery_count == 0 (the only mode used during initial bring-up) and
// fails fast otherwise so we can wire FEC in later without changing
// callers.

#include "cm256.h"
#include <string.h>

int cm256_init(void) { return 0; }

int cm256_encode(cm256_params_t params,
                 const cm256_block_t *originals,
                 void *recovery)
{
    (void)originals;
    if (params.recovery_count == 0) return 0;          // nothing to encode
    if (recovery) memset(recovery, 0,                  // zero so the wire is well-defined
                         (size_t)params.recovery_count * params.block_bytes);
    return -1;                                         // not implemented yet
}

int cm256_decode(cm256_params_t params, cm256_block_t *blocks)
{
    (void)blocks;
    return (params.recovery_count == 0) ? 0 : -1;      // pass-through if no FEC
}

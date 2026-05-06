#ifndef CArgon2_h
#define CArgon2_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int mayn_argon2id_hash_raw(
    uint32_t t_cost,
    uint32_t m_cost_kb,
    uint32_t parallelism,
    const void *pwd,
    size_t pwd_len,
    const void *salt,
    size_t salt_len,
    void *hash,
    size_t hash_len
);

#ifdef __cplusplus
}
#endif
#endif

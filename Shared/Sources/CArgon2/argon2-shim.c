#include "include/CArgon2.h"
#include "argon2/include/argon2.h"

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
) {
    return argon2id_hash_raw(t_cost, m_cost_kb, parallelism,
                             pwd, pwd_len, salt, salt_len,
                             hash, hash_len);
}

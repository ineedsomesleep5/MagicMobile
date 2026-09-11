#ifndef MM_RUNTIME_H
#define MM_RUNTIME_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define MM_MAX_JSON_BYTES (4u * 1024u * 1024u)
#define MM_BACKEND_ABI_VERSION 2u
typedef struct mm_runtime mm_runtime;
typedef enum { MM_OK=0, MM_NOT_LINKED=1, MM_BAD_ARGUMENT=2, MM_ALLOCATION_FAILED=3, MM_ENGINE_FAILED=4, MM_BUSY=5 } mm_status;
/* All backend calls are serialized. Backend owns its isolate and allocation policy. */
typedef struct {
    uint32_t abi_version;
    void* (*create)(void);
    char* (*request)(void*,const char*,size_t,size_t*);
    void (*free_response)(void*,char*);
    /* Free state only on MM_OK. On failure retain it for a later destroy attempt. */
    mm_status (*destroy)(void*);
} mm_backend;
/* Install once at app startup, before constructing any runtime. No dlopen/downloaded code. */
mm_status mm_install_backend(mm_backend backend);
mm_status mm_runtime_create(mm_runtime** out);
mm_status mm_runtime_request(mm_runtime*,const uint8_t*,size_t,uint8_t**,size_t*);
void mm_response_free(uint8_t*);
/* Caller must have exclusive ownership: no concurrent request/destroy may use r.
 * MM_OK frees r (NULL is also OK). Any failure retains r; the caller may retry.
 * MM_BUSY means the engine worker is still alive. Never free r on failure. */
mm_status mm_runtime_destroy(mm_runtime*);
#ifdef __cplusplus
}
#endif
#endif

#include "io.magicmobile.nativebridge.ioslibrarymain.h"

/* Compile-only iOS caller: this does not execute a probe or an XMage engine. */
int mm_verify_probe_abi(graal_isolatethread_t *thread) {
    return mm_toolchain_probe(thread);
}

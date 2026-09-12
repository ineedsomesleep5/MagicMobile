#include "io.magicmobile.nativebridge.ioslibrarymain.h"
#include <stdio.h>

/* Link-only caller with its own main, not Gluon's application delegate.
 * A linked binary is not runtime evidence; no XMage engine is present. */
int main(void) {
    puts("TOOLCHAIN_ONLY entered_main"); fflush(stdout);
    graal_isolatethread_t *thread = 0;
    int created = graal_create_isolate(0, 0, &thread);
    printf("TOOLCHAIN_ONLY isolate_create=%d\n", created); fflush(stdout);
    if (created != 0) return 1;
    int result = mm_toolchain_probe(thread);
    int destroyed = graal_tear_down_isolate(thread);
    printf("TOOLCHAIN_ONLY result=%d isolate_teardown=%d\n", result, destroyed); fflush(stdout);
    if (destroyed != 0) return 2;
    return result == 42 ? 0 : 3;
}

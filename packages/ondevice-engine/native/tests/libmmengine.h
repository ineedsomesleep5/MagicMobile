/* TEST-ONLY entry declarations. Never use this header in a production build. */
#ifndef MM_TEST_LIBMMENGINE_H
#define MM_TEST_LIBMMENGINE_H
#ifdef MM_TEST_USE_GRAAL_SDK
#include "graal_isolate.h"
#else
/* Opaque test doubles only: no real isolate is constructed. SDK mode separately
 * checks these call signatures against the pinned Graal header when available. */
typedef struct __graal_isolate_t graal_isolate_t;
typedef struct __graal_isolatethread_t graal_isolatethread_t;
typedef struct __graal_create_isolate_params_t graal_create_isolate_params_t;
int graal_create_isolate(graal_create_isolate_params_t*,graal_isolate_t**,graal_isolatethread_t**);
int graal_attach_thread(graal_isolate_t*,graal_isolatethread_t**);
int graal_detach_thread(graal_isolatethread_t*);
int graal_tear_down_isolate(graal_isolatethread_t*);
#endif
char* mm_engine_request(graal_isolatethread_t*,char*,int);
void mm_engine_free(graal_isolatethread_t*,char*);
int mm_engine_shutdown_v2(graal_isolatethread_t*);
#endif

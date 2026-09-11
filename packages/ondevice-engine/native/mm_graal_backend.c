/* Production builds require the REAL generated libmmengine.h and matching ABI v2 AOT library. */
#include "mm_runtime.h"
#include "libmmengine.h"
#include <stdlib.h>
#include <string.h>
#include <limits.h>
typedef struct {graal_isolate_t* isolate;graal_isolatethread_t* attached;int unsafe;} backend_state;
static int detach_backend(backend_state* s) {
    int status=graal_detach_thread(s->attached);
    // A failed detach may leave an attachment on a different actor executor thread.
    // Do not use that thread pointer again or attempt a teardown that could wait forever.
    if(status!=0)s->unsafe=1;
    s->attached=NULL;return status;
}
static void* create_backend(void) {
    backend_state* s=calloc(1,sizeof(*s));if(!s)return NULL;
    if(graal_create_isolate(NULL,&s->isolate,&s->attached)!=0){free(s);return NULL;}
    if(graal_detach_thread(s->attached)!=0){
        // No Java entry point or worker has run yet. Retain on ambiguous teardown failure.
        if(graal_tear_down_isolate(s->attached)==0)free(s);
        return NULL;
    }
    s->attached=NULL;return s;
}
static char* request_backend(void* context,const char* data,size_t n,size_t* result_n) {
    backend_state* s=context;*result_n=0;
    if(s->unsafe || n>INT_MAX || graal_attach_thread(s->isolate,&s->attached)!=0)return NULL;
    char* result=mm_engine_request(s->attached,(char*)data,(int)n);
    if(!result){detach_backend(s);return NULL;}
    *result_n=strnlen(result,MM_MAX_JSON_BYTES+1u);return result;
}
static void free_backend(void* context,char* data) {
    backend_state* s=context;mm_engine_free(s->attached,data);
    detach_backend(s);
}
static mm_status destroy_backend(void* context) {
    backend_state* s=context;
    if(s->unsafe || graal_attach_thread(s->isolate,&s->attached)!=0)return MM_ENGINE_FAILED;
    int status=mm_engine_shutdown_v2(s->attached);
    if(status!=MM_OK) {
        if(detach_backend(s)!=0)return MM_ENGINE_FAILED;
        return status==MM_BUSY?MM_BUSY:MM_ENGINE_FAILED;
    }
    if(graal_tear_down_isolate(s->attached)!=0) {
        // The SDK does not guarantee a reusable isolate after a teardown failure.
        // Retain it, fail closed, and never dereference potentially invalid Graal state.
        s->unsafe=1;s->attached=NULL;return MM_ENGINE_FAILED;
    }
    free(s);return MM_OK;
}
mm_status mm_install_graal_backend(void) {
    mm_backend b={MM_BACKEND_ABI_VERSION,create_backend,request_backend,free_backend,destroy_backend};
    return mm_install_backend(b);
}

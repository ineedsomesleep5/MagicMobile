/* TEST-ONLY Graal lifecycle fixture, linked to the production C adapter/runtime.
 * Does not execute Java, AOT code, XMage, or an actual Graal isolate. */
#include "mm_graal_backend.h"
#include "libmmengine.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct __graal_isolate_t {int unused;};
struct __graal_isolatethread_t {int unused;};
static graal_isolate_t isolate;
static graal_isolatethread_t thread;
static int alive,attached,busy,attach_fail,detach_fail,teardown_fail,shutdown_error;
static int shutdowns,teardowns,allocations,releases;
static mm_runtime* volatile intentionally_retained;
int graal_create_isolate(graal_create_isolate_params_t* p,graal_isolate_t** i,graal_isolatethread_t** t) {
    (void)p;assert(!alive);alive=attached=1;*i=&isolate;*t=&thread;return 0;
}
int graal_attach_thread(graal_isolate_t* i,graal_isolatethread_t** t) {
    assert(alive && i==&isolate);if(attach_fail)return 1;attached=1;*t=&thread;return 0;
}
int graal_detach_thread(graal_isolatethread_t* t) {
    assert(alive && attached && t==&thread);if(detach_fail)return 1;attached=0;return 0;
}
int graal_tear_down_isolate(graal_isolatethread_t* t) {
    assert(alive && attached && t==&thread);assert(!busy);teardowns++;
    if(teardown_fail)return 1;alive=attached=0;return 0;
}
char* mm_engine_request(graal_isolatethread_t* t,char* data,int n) {
    assert(alive && attached && t==&thread);char* result=malloc((size_t)n+1);
    memcpy(result,data,(size_t)n);result[n]=0;allocations++;return result;
}
void mm_engine_free(graal_isolatethread_t* t,char* data) {
    assert(alive && attached && t==&thread);free(data);releases++;
}
int mm_engine_shutdown_v2(graal_isolatethread_t* t) {
    assert(alive && attached && t==&thread);shutdowns++;
    return shutdown_error?MM_ENGINE_FAILED:(busy?MM_BUSY:MM_OK);
}
static void request(mm_runtime* r,mm_status expected) {
    const uint8_t data[]="{}";uint8_t* out=NULL;size_t n=0;
    assert(mm_runtime_request(r,data,2,&out,&n)==expected);
    if(expected==MM_OK){assert(n==2 && memcmp(data,out,n)==0);mm_response_free(out);}
    else assert(!out && n==0);
    assert(allocations==releases);
}
int main(int argc,char** argv) {
    assert(argc==2);assert(mm_install_graal_backend()==MM_OK);
    mm_runtime* r=NULL;assert(mm_runtime_create(&r)==MM_OK);
    if(strcmp(argv[1],"busy")==0) {
        busy=1;assert(mm_runtime_destroy(r)==MM_BUSY);
        assert(alive && !attached && teardowns==0);request(r,MM_OK);
        busy=0;assert(mm_runtime_destroy(r)==MM_OK);assert(!alive && shutdowns==2 && teardowns==1);
    } else if(strcmp(argv[1],"attach")==0) {
        attach_fail=1;assert(mm_runtime_destroy(r)==MM_ENGINE_FAILED);
        assert(alive && !attached && shutdowns==0 && teardowns==0);
        request(r,MM_ENGINE_FAILED);attach_fail=0;request(r,MM_OK);
        assert(mm_runtime_destroy(r)==MM_OK);assert(!alive);
    } else if(strcmp(argv[1],"shutdown")==0) {
        shutdown_error=1;assert(mm_runtime_destroy(r)==MM_ENGINE_FAILED);
        assert(alive && !attached && teardowns==0);request(r,MM_OK);
        shutdown_error=0;assert(mm_runtime_destroy(r)==MM_OK);assert(!alive);
    } else if(strcmp(argv[1],"teardown")==0) {
        teardown_fail=1;assert(mm_runtime_destroy(r)==MM_ENGINE_FAILED);
        assert(alive && teardowns==1);request(r,MM_ENGINE_FAILED);
        assert(mm_runtime_destroy(r)==MM_ENGINE_FAILED);assert(teardowns==1);
        intentionally_retained=r;
        // Intentionally retained: an ambiguous teardown must never be retried unsafely.
    } else if(strcmp(argv[1],"detach")==0) {
        busy=detach_fail=1;assert(mm_runtime_destroy(r)==MM_ENGINE_FAILED);
        assert(alive && attached && teardowns==0);request(r,MM_ENGINE_FAILED);
        assert(mm_runtime_destroy(r)==MM_ENGINE_FAILED);assert(teardowns==0);
        intentionally_retained=r;
        // Intentionally retained: the prior executor thread may still be attached.
    } else {assert(!"unknown scenario");}
    printf("PASS: %s C adapter shutdown fixture (not native execution)\n",argv[1]);return 0;
}

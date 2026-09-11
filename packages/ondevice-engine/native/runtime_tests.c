/* TEST-ONLY byte echo backend. Exercises ownership and limits, never gameplay. */
#include "mm_runtime.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <stdatomic.h>
static atomic_int active=0;
static int allocated=0,released=0,destroyed=0;
static void* create(void){return malloc(1);}
static char* request(void* s,const char* input,size_t n,size_t* out){(void)s;assert(atomic_fetch_add(&active,1)==0);char* p=malloc(n);memcpy(p,input,n);*out=n;allocated++;return p;}
static void release(void* s,char* p){(void)s;free(p);released++;assert(atomic_fetch_sub(&active,1)==1);}
static int busy=0;
static mm_status destroy(void* s){assert(active==0);if(busy)return MM_BUSY;free(s);destroyed++;return MM_OK;}
static void* call_loop(void* p){
    mm_runtime* r=p;
    for(int i=0;i<1000;i++){
        const uint8_t input[]={123,125};uint8_t* out=NULL;size_t n=0;
        assert(mm_runtime_request(r,input,2,&out,&n)==MM_OK);assert(n==2&&memcmp(out,input,2)==0);mm_response_free(out);
    }
    return NULL;
}
int main(void){
    mm_runtime* r=NULL;
    assert(mm_runtime_create(NULL)==MM_BAD_ARGUMENT);
    assert(mm_runtime_create(&r)==MM_NOT_LINKED&&r==NULL);
    mm_backend invalid={0,NULL,NULL,NULL,NULL};assert(mm_install_backend(invalid)==MM_BAD_ARGUMENT);
    mm_backend b={1,create,request,release,destroy};assert(mm_install_backend(b)==MM_BAD_ARGUMENT);
    b.abi_version=MM_BACKEND_ABI_VERSION;assert(mm_install_backend(b)==MM_OK);
    assert(mm_install_backend(b)==MM_BAD_ARGUMENT);
    assert(mm_runtime_create(&r)==MM_OK&&r);
    uint8_t* out=NULL;size_t n=0;
    assert(mm_runtime_request(r,NULL,0,&out,&n)==MM_BAD_ARGUMENT);
    const uint8_t input[]={123,125};
    assert(mm_runtime_request(r,input,MM_MAX_JSON_BYTES+1u,&out,&n)==MM_BAD_ARGUMENT);
    pthread_t threads[8];for(int i=0;i<8;i++)assert(pthread_create(&threads[i],NULL,call_loop,r)==0);
    for(int i=0;i<8;i++)pthread_join(threads[i],NULL);
    /* A live backend worker refuses shutdown. Its runtime must survive for retry. */
    assert(allocated==8000 && released==8000);
    busy=1;assert(mm_runtime_destroy(r)==MM_BUSY);assert(destroyed==0);
    call_loop(r);
    busy=0;
    assert(mm_runtime_destroy(r)==MM_OK);assert(destroyed==1);
    assert(allocated==9000 && released==9000);
    assert(mm_runtime_destroy(NULL)==MM_OK);mm_response_free(NULL);
    puts("PASS: C ABI v2 limits/ownership, 8,000 serialized concurrent requests, busy retention + 1,000 requests + successful retry (fixture only)");return 0;
}

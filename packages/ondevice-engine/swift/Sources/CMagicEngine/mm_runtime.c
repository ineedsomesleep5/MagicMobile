#include "mm_runtime.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
struct mm_runtime { mm_backend backend; void* state; pthread_mutex_t mutex; };
static mm_backend installed;
static int ready=0;
static pthread_mutex_t install_lock=PTHREAD_MUTEX_INITIALIZER;
mm_status mm_install_backend(mm_backend b) {
    if(b.abi_version!=MM_BACKEND_ABI_VERSION || !b.create || !b.request || !b.free_response || !b.destroy) return MM_BAD_ARGUMENT;
    pthread_mutex_lock(&install_lock);
    if(ready) {pthread_mutex_unlock(&install_lock);return MM_BAD_ARGUMENT;}
    installed=b;ready=1;pthread_mutex_unlock(&install_lock);return MM_OK;
}
mm_status mm_runtime_create(mm_runtime** out) {
    if(!out)return MM_BAD_ARGUMENT;*out=NULL;
    pthread_mutex_lock(&install_lock);
    if(!ready){pthread_mutex_unlock(&install_lock);return MM_NOT_LINKED;}
    mm_backend b=installed;pthread_mutex_unlock(&install_lock);
    mm_runtime* r=calloc(1,sizeof(*r));if(!r)return MM_ALLOCATION_FAILED;
    r->backend=b;
    if(pthread_mutex_init(&r->mutex,NULL)!=0){free(r);return MM_ENGINE_FAILED;}
    r->state=b.create();
    if(!r->state){pthread_mutex_destroy(&r->mutex);free(r);return MM_ENGINE_FAILED;}
    *out=r;return MM_OK;
}
mm_status mm_runtime_request(mm_runtime* r,const uint8_t* input,size_t size,uint8_t** out,size_t* out_size) {
    if(out)*out=NULL;if(out_size)*out_size=0;
    if(!r || !input || !out || !out_size || size==0 || size>MM_MAX_JSON_BYTES)return MM_BAD_ARGUMENT;
    pthread_mutex_lock(&r->mutex);
    size_t n=0;char* result=r->backend.request(r->state,(const char*)input,size,&n);
    if(!result || n==0 || n>MM_MAX_JSON_BYTES){
        if(result)r->backend.free_response(r->state,result);
        pthread_mutex_unlock(&r->mutex);return MM_ENGINE_FAILED;
    }
    uint8_t* copy=malloc(n);
    if(copy)memcpy(copy,result,n);
    r->backend.free_response(r->state,result);
    pthread_mutex_unlock(&r->mutex);
    if(!copy)return MM_ALLOCATION_FAILED;
    *out=copy;*out_size=n;return MM_OK;
}
void mm_response_free(uint8_t* p){free(p);}
mm_status mm_runtime_destroy(mm_runtime* r){
    if(!r)return MM_OK;
    pthread_mutex_lock(&r->mutex);
    mm_status status=r->backend.destroy(r->state);
    pthread_mutex_unlock(&r->mutex);
    if(status!=MM_OK)return status;
    pthread_mutex_destroy(&r->mutex);free(r);return MM_OK;
}

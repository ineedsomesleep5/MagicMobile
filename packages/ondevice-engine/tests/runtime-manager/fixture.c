/* TEST ONLY. A deterministic native-ABI fixture, not Graal, Java or XMage. */
#include "fixture.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
static atomic_int mode=0,busy=0,closes=0;
void fixture_mode(int value){atomic_store(&mode,value);atomic_store(&closes,0);atomic_store(&busy,0);}
void fixture_busy_closes(int value){atomic_store(&busy,value);}
int fixture_close_calls(void){return atomic_load(&closes);}
static void *create(void){return calloc(1,1);}
static char *request(void *state,const char *input,size_t length,size_t *output_length){
    (void)state;
    char *copy=calloc(length+1,1);if(!copy)return NULL;
    memcpy(copy,input,length);
    const char *reply;
    if(strstr(copy,"capabilities"))reply=atomic_load(&mode)?
        "{\"protocol\":1,\"ok\":false,\"error\":{\"code\":\"engine_failure\",\"message\":\"Engine operation failed.\"}}":
        "{\"protocol\":1,\"ok\":true,\"result\":{\"engine\":\"xmage\",\"execution\":\"native-aot\",\"protocol\":1,\"upstream\":\"fixture-upstream\",\"catalogueHash\":\"fixture-catalogue\",\"maxPlayers\":4}}";
    else if(strstr(copy,"clearDiagnostics")){
        atomic_store(&mode,0);reply="{\"protocol\":1,\"ok\":true,\"result\":{\"cleared\":true}}";
    }else if(strstr(copy,"diagnostics"))reply=atomic_load(&mode)?
        "{\"protocol\":1,\"ok\":true,\"result\":{\"report\":\"PRIVATE-startup-fixture\"}}":
        "{\"protocol\":1,\"ok\":true,\"result\":{\"report\":null}}";
    else reply="{\"protocol\":1,\"ok\":false,\"error\":{\"code\":\"fixture_only\",\"message\":\"Only lifecycle fixture operations are supported\"}}";
    free(copy);
    size_t size=strlen(reply);char *result=malloc(size+1);if(!result)return NULL;
    memcpy(result,reply,size+1);*output_length=size;return result;
}
static void release(void *state,char *response){(void)state;free(response);}
static mm_status destroy(void *state){
    atomic_fetch_add(&closes,1);
    if(atomic_load(&busy)>0){atomic_fetch_sub(&busy,1);return MM_BUSY;}
    free(state);return MM_OK;
}
mm_status mm_install_graal_backend(void){
    mm_backend backend={MM_BACKEND_ABI_VERSION,create,request,release,destroy};
    return mm_install_backend(backend);
}

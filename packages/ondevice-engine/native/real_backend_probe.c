/* Must link the REAL Graal/XMage library. No fixture backend is linked here. */
#include "mm_runtime.h"
#include "mm_graal_backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int finish(mm_runtime* runtime,int result) {
    mm_status status=mm_runtime_destroy(runtime);
    if(status!=MM_OK) {
        fprintf(stderr,"Native shutdown failed (%d); retained runtime/isolate, no forced free\n",status);
        return 6;
    }
    return result;
}
int main(void) {
    if(mm_install_graal_backend()!=MM_OK) return 1;
    mm_runtime *runtime=NULL;
    if(mm_runtime_create(&runtime)!=MM_OK)return 2;
    const char *input="{\"protocol\":1,\"op\":\"capabilities\"}";
    unsigned char *out=NULL;size_t n=0;
    mm_status status=mm_runtime_request(runtime,(const unsigned char *)input,strlen(input),&out,&n);
    if(status!=MM_OK)return finish(runtime,3);
    fwrite(out,1,n,stdout);putchar('\n');
    char *text=malloc(n+1);
    if(!text){mm_response_free(out);return finish(runtime,5);}
    memcpy(text,out,n);text[n]='\0';
    int good=strstr(text,"\"native-aot\"")!=NULL && strstr(text,"\"xmage\"")!=NULL;
    free(text);mm_response_free(out);
    return finish(runtime,good?0:4);
}

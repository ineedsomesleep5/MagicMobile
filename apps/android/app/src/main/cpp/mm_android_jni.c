#include <jni.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include "mm_runtime.h"
#include "mm_graal_backend.h"

/* One process-owned runtime. A Kotlin token is never treated as an address. */
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static mm_runtime *runtime;
static jlong generation;
static int registered;
static void fail(JNIEnv *env, const char *text) {
    jclass type = (*env)->FindClass(env, "java/lang/IllegalStateException");
    if(type) (*env)->ThrowNew(env,type,text);
}
JNIEXPORT jlong JNICALL Java_io_magicmobile_android_NativeBridge_open(JNIEnv *env, jobject self) {
    (void)self; pthread_mutex_lock(&gate);
    if(runtime){pthread_mutex_unlock(&gate);fail(env,"An engine session is still owned; finish cleanup first.");return 0;}
    if(!registered){if(mm_install_graal_backend()!=MM_OK){pthread_mutex_unlock(&gate);fail(env,"Could not register the native engine.");return 0;} registered=1;}
    if(mm_runtime_create(&runtime)!=MM_OK){pthread_mutex_unlock(&gate);fail(env,"Could not initialize full native XMage.");return 0;}
    generation = generation == INT64_MAX ? 1 : generation+1;
    jlong result=generation; pthread_mutex_unlock(&gate); return result;
}
JNIEXPORT jbyteArray JNICALL Java_io_magicmobile_android_NativeBridge_request(JNIEnv *env,jobject self,jlong token,jbyteArray input) {
    (void)self;
    if(!input){fail(env,"Missing request");return NULL;}
    jsize size=(*env)->GetArrayLength(env,input);
    if(size<=0 || (size_t)size>MM_MAX_JSON_BYTES){fail(env,"Request exceeds engine bounds");return NULL;}
    uint8_t *bytes=malloc((size_t)size); if(!bytes){fail(env,"Allocation failed");return NULL;}
    (*env)->GetByteArrayRegion(env,input,0,size,(jbyte*)bytes);
    if((*env)->ExceptionCheck(env)){free(bytes);return NULL;}
    pthread_mutex_lock(&gate);
    if(!runtime || token!=generation){pthread_mutex_unlock(&gate);free(bytes);fail(env,"Stale engine session");return NULL;}
    uint8_t *output=NULL; size_t length=0;
    mm_status status=mm_runtime_request(runtime,bytes,(size_t)size,&output,&length); free(bytes);
    if(status!=MM_OK || !output || length>MM_MAX_JSON_BYTES){if(output)mm_response_free(output);pthread_mutex_unlock(&gate);fail(env,"Native request failed; no response was fabricated.");return NULL;}
    jbyteArray result=(*env)->NewByteArray(env,(jsize)length);
    if(result)(*env)->SetByteArrayRegion(env,result,0,(jsize)length,(const jbyte*)output);
    mm_response_free(output); pthread_mutex_unlock(&gate);return result;
}
JNIEXPORT jint JNICALL Java_io_magicmobile_android_NativeBridge_close(JNIEnv *env,jobject self,jlong token) {
    (void)env;(void)self; pthread_mutex_lock(&gate);
    if(!runtime){pthread_mutex_unlock(&gate);return MM_OK;}
    if(token!=generation){pthread_mutex_unlock(&gate);return MM_BAD_ARGUMENT;}
    mm_status status=mm_runtime_destroy(runtime);
    if(status==MM_OK)runtime=NULL;
    pthread_mutex_unlock(&gate);return status;
}

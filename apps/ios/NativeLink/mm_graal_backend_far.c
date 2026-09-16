/* Product-only long-call routing. Renaming before the generated declarations
 * preserves their exact ABI; the underlying backend and AOT inputs are unchanged.
 * Apple ARM64 branch islands cannot cross the indivisible full Graal code image.
 */
#define graal_create_isolate mm_far_graal_create_isolate
#define graal_attach_thread mm_far_graal_attach_thread
#define graal_detach_thread mm_far_graal_detach_thread
#define graal_tear_down_isolate mm_far_graal_tear_down_isolate
#define mm_engine_request mm_far_engine_request
#define mm_engine_free mm_far_engine_free
#define mm_engine_shutdown_v2 mm_far_engine_shutdown_v2
#include "../../../packages/ondevice-engine/native/mm_graal_backend.c"

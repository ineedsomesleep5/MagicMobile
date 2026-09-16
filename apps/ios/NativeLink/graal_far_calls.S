/* Keep these veneers beside native callers, after the intact Graal code image.
 * x16 is the ABI scratch register; BR preserves the original return address,
 * arguments and result convention. PAGE relocations reach beyond B/BL's 128 MiB.
 */
#if !defined(__aarch64__) || !defined(__APPLE__)
#error Product Graal veneers require Apple ARM64
#endif
.text
.p2align 2
.macro FAR_CALL wrapper, target
.globl \wrapper
\wrapper:
    adrp x16, \target@PAGE
    add x16, x16, \target@PAGEOFF
    br x16
.endm
FAR_CALL _mm_far_graal_create_isolate, _graal_create_isolate
FAR_CALL _mm_far_graal_attach_thread, _graal_attach_thread
FAR_CALL _mm_far_graal_detach_thread, _graal_detach_thread
FAR_CALL _mm_far_graal_tear_down_isolate, _graal_tear_down_isolate
FAR_CALL _mm_far_engine_request, _mm_engine_request
FAR_CALL _mm_far_engine_free, _mm_engine_free
FAR_CALL _mm_far_engine_shutdown_v2, _mm_engine_shutdown_v2
.subsections_via_symbols

#ifndef JBYTEVM_H
#define JBYTEVM_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(JBV_BUILD_DLL)
#define JBV_API __declspec(dllexport)
#elif defined(_WIN32) && defined(JBV_USE_DLL)
#define JBV_API __declspec(dllimport)
#else
#define JBV_API
#endif
#if defined(_WIN32)
#define JBV_CALL __cdecl
#else
#define JBV_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JbvVM JbvVM;
enum {
    JBV_FEATURE_NATIVE=1, JBV_FEATURE_MONITORS=2, JBV_FEATURE_ACCESS=4,
    JBV_FEATURE_TEXT=8, JBV_FEATURE_CLASSPATH=16,
    JBV_FEATURE_CONDY=32, /* Reserved former runtime feature; now always absent. */
    JBV_FEATURE_TRACES=64, JBV_FEATURE_REFLECTION=128
};
/* Available runtime feature groups; the C ABI stays the same across profiles. */
JBV_API uint32_t JBV_CALL jbv_features(void);
typedef enum JbvStatus {
    JBV_OK = 0,
    JBV_BAD_ARGUMENT,
    JBV_OUT_OF_MEMORY,
    JBV_BAD_CLASS,
    JBV_UNSUPPORTED_VERSION,
    JBV_INDY_DISABLED,
    JBV_UNSUPPORTED_FEATURE,
    JBV_NOT_FOUND,
    JBV_LINKAGE_ERROR,
    JBV_DIVIDE_BY_ZERO,
    JBV_LIMIT_EXCEEDED,
    JBV_BUSY,
    JBV_NULL_REFERENCE,
    JBV_ARRAY_BOUNDS,
    JBV_NEGATIVE_ARRAY_SIZE,
    JBV_ARRAY_STORE,
    JBV_CLASS_CAST,
    JBV_BAD_REFERENCE,
    JBV_MONITOR_STATE = 18,
    JBV_ILLEGAL_STATE = 19,
    JBV_NATIVE_ERROR = 21,
    JBV_EXCEPTION = 22
} JbvStatus;

/* The host owns allocator state; alloc must provide malloc-compatible alignment.
 * All allocations are freed by the matching free callback, including on failure. */
typedef void *(JBV_CALL *JbvAlloc)(void *user, size_t bytes);
typedef void (JBV_CALL *JbvFree)(void *user, void *memory);
typedef struct JbvConfig {
    JbvAlloc alloc;
    JbvFree free;
    void *allocator_user;
    uint32_t max_slots;       /* zero selects 16384 int32 slots */
    uint32_t max_depth;       /* zero selects 64; maximum 256 */
    uint64_t max_instructions; /* zero selects 10000000 per outer call */
    size_t max_memory;        /* total live allocator bytes; zero selects 10 MiB */
    size_t max_heap;          /* Java heap bytes; zero uses the total memory limit */
} JbvConfig;

/* Includes VM state, VM allocation headers, slots, class images/metadata,
 * handles, monitors, temporary buffers and objects. Excludes the host allocator's
 * own overhead, native call stacks, mapped DLL pages and native-owned memory.
 * Limits do not reserve memory. Recompile hosts after this config extension. */
typedef struct JbvMemoryStats {
    size_t used, peak, limit;
} JbvMemoryStats;
JBV_API JbvStatus JBV_CALL jbv_memory_stats(JbvVM *vm, JbvMemoryStats *out);

/* References are positive, VM-local generational handles, never addresses.
 * Null is zero. Do not transfer handles between VMs. */
typedef int32_t JbvRef;
typedef struct JbvHeapStats {
    size_t bytes;
    uint32_t objects;
    uint64_t collections;
} JbvHeapStats;

/* Compact native ABI for static native methods only. Callbacks may invoke Java on this same VM,
 * synchronously on the same OS thread; nested reentry is supported.
 * args is borrowed and rooted until return. Reference parameters/results use
 * JbvRef bits in the same int32 ABI. Write result on success for non-void methods.
 * Allocator callbacks must not reenter the VM. */
typedef JbvStatus (JBV_CALL *JbvNative)(JbvVM *vm, void *user,
    const int32_t *args, uint16_t count, int32_t *result);
/* Raw JVM slots: long/double occupy two slots, low 32 bits first. Floating
 * values are IEEE bits. Result holds one value, up to 64 bits; references are
 * still 32-bit handles. Registered methods are static: count covers only their
 * explicit Java arguments, with no implicit receiver. */
typedef JbvStatus (JBV_CALL *JbvNativeSlots)(JbvVM *vm, void *user,
    const int32_t *args, uint16_t count, uint64_t *result);

JBV_API JbvStatus JBV_CALL jbv_create(const JbvConfig *config, JbvVM **out);
/* Returns BUSY without destroying the VM while a Java/native call is active. */
JBV_API JbvStatus JBV_CALL jbv_destroy(JbvVM *vm);
/* Copies a trusted, valid Java 25 class image. There is no bytecode verifier:
 * code, operand/local types, max_stack/max_locals and CP references must be
 * correct. Malformed executable bytecode has undefined behavior.
 * Loading/binding during execution is BUSY. */
JBV_API JbvStatus JBV_CALL jbv_load_class(JbvVM *vm, const void *bytes, size_t size);
/* Instance native methods return UNSUPPORTED_FEATURE without changing binding. */
JBV_API JbvStatus JBV_CALL jbv_bind_native(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvNative callback, void *user);
JBV_API JbvStatus JBV_CALL jbv_bind_native_slots(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvNativeSlots callback, void *user);
/* Static methods using raw JVM slots (long/double: low word, high word).
 * jbv_call supports one-slot results; jbv_call_slots supports all results.
 * Floating parameters/results use IEEE bits. count is a slot count.
 * result is required even for void calls and is unchanged on failure.
 * Names use JVM internal form (e.g. sample/Counter); ASCII names are tested.
 * A successful reference result is retained for the host: release it exactly
 * once with jbv_release, including results from reentrant calls inside native.
 * Arguments are rooted through class initialization and the entire call.
 * One VM is single-threaded; the host must enforce same-thread access. */
JBV_API JbvStatus JBV_CALL jbv_call(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, const int32_t *args,
    uint16_t count, int32_t *result);
JBV_API JbvStatus JBV_CALL jbv_call_slots(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, const int32_t *args,
    uint16_t count, uint64_t *result);
JBV_API JbvStatus JBV_CALL jbv_retain(JbvVM *vm, JbvRef ref);
JBV_API JbvStatus JBV_CALL jbv_release(JbvVM *vm, JbvRef ref);
/* Safe from a native callback: scans every suspended Java/native frame. */
JBV_API JbvStatus JBV_CALL jbv_collect(JbvVM *vm);
/* Optional lower Java object heap budget, also configurable with max_heap.
 * The total max_memory limit always applies, including to emergency exceptions.
 * A heap-budget OutOfMemoryError may allocate one small emergency exception
 * beyond this budget. Host allocation failure can still return a bare C status.
 * Changing the limit requires an idle VM. On failure the old limit is kept. */
JBV_API JbvStatus JBV_CALL jbv_set_heap_limit(JbvVM *vm, size_t bytes);
JBV_API JbvStatus JBV_CALL jbv_heap_stats(JbvVM *vm, JbvHeapStats *out);
/* Retains the pending Java exception (or returns null). Release the returned
 * handle. The next outer jbv_call clears the VM's pending exception root. */
JBV_API JbvStatus JBV_CALL jbv_exception(JbvVM *vm, JbvRef *out);
JBV_API const char *JBV_CALL jbv_status_string(JbvStatus status);

#ifdef __cplusplus
}
#endif
#endif

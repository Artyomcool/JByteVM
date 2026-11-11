#ifndef JBYTEVM_NATIVE_H
#define JBYTEVM_NATIVE_H
#include "jbytevm.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Typed Windows x86 native ABI: R JBV_CALL function(JbvVM *, Java arguments...).
 * Only static native methods can be registered. C types: Z=uint8_t (0/1),
 * B=int8_t, C=uint16_t, S=int16_t, I=int32_t, J=int64_t, F=float, D=double,
 * references/arrays=JbvRef, V=void. No varargs, structs, or implicit receiver.
 * JBV_NATIVE_FN erases the pointer type for storage only; the descriptor must
 * exactly match the real C prototype. Functions must use JBV_CALL (__cdecl).
 * Native code must not unwind C++/SEH exceptions across the VM. */
/* x86 Java execution establishes nearest-even rounding, 53-bit x87 precision,
 * and gradual underflow. VM boundaries preserve the caller's x87 environment
 * and MXCSR, including across nested native -> Java calls. */
typedef void (JBV_CALL *JbvNativeFunction)(void);
#define JBV_NATIVE_FN(function) ((JbvNativeFunction)(function))
typedef struct JbvNativeEntry {
    const char *name;
    const char *descriptor;
    JbvNativeFunction function;
} JbvNativeEntry;

/* Register one class's table atomically. Reject duplicate keys and unsupported
 * methods; on failure every old binding remains intact. Rebinding requires an
 * idle VM. Table/strings are borrowed only during registration; functions and
 * user context must remain valid while bound. Non-x86 returns UNSUPPORTED_FEATURE.
 * Native reference parameters are borrowed roots until return. Reference
 * results are borrowed too: release a host-owned result immediately before
 * returning it, with no intervening VM calls (same rule as slot callbacks). */
JBV_API JbvStatus JBV_CALL jbv_register_natives(JbvVM *vm, const char *class_name,
    const JbvNativeEntry *entries, uint32_t count, void *user);
/* Context is scoped to the current typed native call; nested calls restore it.
 * Returns null outside a typed native call (or if registered with null user).
 * jbv_throw propagates a pending Java exception on return from typed native.
 * For other errors, report a non-OK status with jbv_native_fail before returning
 * a dummy value. A nested call's error must be propagated or explicitly handled.
 * Failure status belongs to this native frame, not a process-global slot. */
JBV_API void *JBV_CALL jbv_native_context(JbvVM *vm);
JBV_API JbvStatus JBV_CALL jbv_native_fail(JbvVM *vm, JbvStatus status);

/* IDs are opaque VM-local metadata pointers, valid until jbv_destroy. Resolve
 * once, then reuse; resolution allocates no per-ID objects. Never edit an ID,
 * forge it, or use it in another VM. The host is trusted native code.
 * No JNI binary compatibility or automatic library discovery. */
typedef struct JbvMethodId { void *owner, *method; } JbvMethodId;
typedef struct JbvFieldId { void *owner, *field; } JbvFieldId;
typedef union JbvValue {
    int32_t i;
    int64_t j;
    float f;
    double d;
    JbvRef ref;
    uint64_t bits;
} JbvValue;

/* Optional host services, installed while idle. No OS imports are added by VM.
 * clock: milliseconds since Unix epoch, or monotonic nanoseconds when flag=1.
 * write: borrowed String, rooted for the callback; error=1 selects System.err.
 * Full profile only: calls without the required callback report NATIVE_ERROR.
 * Other profiles accept the configuration but contain no Java System services.
 * The host serializes VM access and owns callbacks/user until replacement. */
typedef struct JbvHostServices {
    int64_t (JBV_CALL *clock)(void *user, int monotonic);
    JbvStatus (JBV_CALL *write)(JbvVM *vm, void *user, JbvRef text, int error);
    void *user;
} JbvHostServices;
JBV_API JbvStatus JBV_CALL jbv_set_host_services(JbvVM *vm, const JbvHostServices *services);

/* String constructors copy input and return a retained reference. Lengths are
 * explicit: embedded NUL is preserved, no terminator is added or required.
 * UTF-16 accepts any code units, including isolated surrogates. UTF-8 input is
 * strict Unicode UTF-8 (not JNI modified UTF-8); invalid input is BAD_ARGUMENT.
 * UTF-8 output replaces isolated surrogates with U+FFFD. Read with out=NULL,
 * capacity=0 to query required bytes. Too-small capacity is BAD_ARGUMENT.
 * Failed calls leave output parameters/buffers unchanged. */
JBV_API JbvStatus JBV_CALL jbv_string_new_utf16(JbvVM *vm, const uint16_t *text, uint32_t length, JbvRef *out);
JBV_API JbvStatus JBV_CALL jbv_string_new_utf8(JbvVM *vm, const char *text, uint32_t bytes, JbvRef *out);
JBV_API JbvStatus JBV_CALL jbv_string_length(JbvVM *vm, JbvRef string, uint32_t *length);
JBV_API JbvStatus JBV_CALL jbv_string_read_utf16(JbvVM *vm, JbvRef string, uint32_t start, uint32_t count, uint16_t *out);
JBV_API JbvStatus JBV_CALL jbv_string_read_utf8(JbvVM *vm, JbvRef string, char *out, uint32_t capacity, uint32_t *bytes);

JBV_API JbvStatus JBV_CALL jbv_resolve_method(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvMethodId *out);
/* Static calls initialize the declaring class. Instance args include receiver
 * at slot 0; ordinary instance methods dispatch virtually, constructors and
 * private methods directly. A constructor must be resolved on its own class.
 * Argument layout/result ownership are the same as jbv_call_slots.
 * An outer invocation clears the previous pending exception; nested invocations
 * share instruction/depth limits. Propagate a failing status from callbacks. */
JBV_API JbvStatus JBV_CALL jbv_invoke(JbvVM *vm, const JbvMethodId *method,
    const int32_t *args, uint16_t count, uint64_t *result);
/* Convenient static Java calls from C, without packing JVM slots. Values must
 * match the resolved descriptor: J takes int64_t, F/D take promoted double,
 * Z/B/C/S/I take promoted int, references take JbvRef. This is a C varargs
 * convenience API; registered typed native targets themselves are never varargs.
 * Read result.i/j/f/d/ref according to the Java return type; void yields zero.
 * Reference ownership and status semantics are the same as jbv_invoke. */
JBV_API JbvStatus JBV_CALL jbv_invoke_args(JbvVM *vm, const JbvMethodId *method,
    JbvValue *result, ...);

/* Initializes the class, allocates zeroed fields, and retains the result.
 * Does not run an instance constructor: invoke <init> explicitly, or use a Java
 * factory through jbv_call_slots. Failed constructors leave host-owned refs for
 * the host to release. Array descriptors use JVM syntax: [I, [Lpkg/Type;, [[I. */
JBV_API JbvStatus JBV_CALL jbv_alloc_object(JbvVM *vm, const char *class_name, JbvRef *out);
JBV_API JbvStatus JBV_CALL jbv_new_array(JbvVM *vm, const char *descriptor, int32_t length, JbvRef *out);

JBV_API JbvStatus JBV_CALL jbv_resolve_field(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvFieldId *out);
/* Static fields require receiver=0; instance fields require a compatible object.
 * Values are raw bits: long/double use 64 bits, others low 32 bits. Reference
 * reads retain the result; release it once. Writes check reference types and
 * narrow Z/B/C/S just like bytecode. Static access initializes the owner. */
JBV_API JbvStatus JBV_CALL jbv_get_field(JbvVM *vm, const JbvFieldId *field, JbvRef receiver, uint64_t *out);
JBV_API JbvStatus JBV_CALL jbv_set_field(JbvVM *vm, const JbvFieldId *field, JbvRef receiver, uint64_t value);

/* kind is optional: Z/B/C/S/I/J/F/D for primitives, L for references (also
 * nested arrays). Copies use one uint64_t raw-bits value per element, never a
 * pointer into VM storage. Reference reads retain each returned occurrence.
 * Writes validate the whole range and all references before modifying it.
 * Buffers may be null only for count=0; out parameters are unchanged on error. */
JBV_API JbvStatus JBV_CALL jbv_array_info(JbvVM *vm, JbvRef array, uint32_t *length, char *kind);
JBV_API JbvStatus JBV_CALL jbv_array_read(JbvVM *vm, JbvRef array, uint32_t start, uint32_t count, uint64_t *out);
JBV_API JbvStatus JBV_CALL jbv_array_write(JbvVM *vm, JbvRef array, uint32_t start, uint32_t count, const uint64_t *values);

/* Set a pending Throwable (rooted by VM) and return JBV_EXCEPTION. The caller
 * still owns any retained reference. Return this status to propagate into Java.
 * Clear a nested Java exception explicitly before recovering in native code. */
JBV_API JbvStatus JBV_CALL jbv_throw(JbvVM *vm, JbvRef exception);
JBV_API JbvStatus JBV_CALL jbv_clear_exception(JbvVM *vm);

#ifdef __cplusplus
}
#endif
#endif

#ifndef JBV_INTERNAL_H
#define JBV_INTERNAL_H
#include "jbytevm_native.h"

#define JBV_STATIC 0x0008
#define JBV_NATIVE 0x0100
#define JBV_ABSTRACT 0x0400
#define JBV_SYNCHRONIZED 0x0020
#define JBV_INTERFACE 0x0200
#define JBV_FINAL 0x0010
#define JBV_TYPED_NATIVE 0x8000 /* VM-only method flag; native_slots holds typed address. */

typedef struct JbvText { const uint8_t *data; uint16_t size; } JbvText;
/* Inflated jbv/classes.bin of a JAR; parsed classes reference it in place. */
typedef struct JbvArchive { uint8_t *data; size_t size; } JbvArchive;
typedef struct JbvConstant {
    uint8_t tag;
    uint16_t a, b;
    uint32_t bits, bits_hi;
    JbvText text;
} JbvConstant;
typedef struct JbvMethod {
    uint16_t flags, max_stack, max_locals;
    JbvText name, descriptor;
#if JBV_PROFILE_FULL
    const uint8_t *attributes; /* Original attribute_count + bounded attribute table. */
#endif
    const uint8_t *code;
    const uint8_t *exception_table;
    uint16_t argument_slots; /* Includes the receiver for instance methods. */
    uint8_t result_kind;     /* Zero for void, otherwise JBV_* + 1. */
    uint16_t handlers;
    uint16_t line_count;
    const uint8_t *lines;
    uint8_t intrinsic;
    JbvNative native;
    JbvNativeSlots native_slots;
    void *native_user;
} JbvMethod;
typedef struct JbvField {
    uint16_t flags, constant;
    JbvText name, descriptor;
#if JBV_PROFILE_FULL
    const uint8_t *attributes;
#endif
    int32_t value, value_hi;
    uint32_t slot;
} JbvField;
typedef struct JbvClass {
    struct JbvClass *next;
    uint8_t *image;
    JbvConstant *pool;
    uint16_t pool_size, method_count, field_count;
    JbvText name, super_name;
    JbvText source_file;
#if JBV_PROFILE_FULL
    const uint8_t *attributes;
#endif
    JbvMethod *methods;
    JbvField *fields;
    uint16_t flags, interface_count;
    const uint8_t *interface_indices;
    uint16_t nest_host, nest_count;
    const uint8_t *nest_members;
    struct JbvClass **interfaces;
    struct JbvClass *super, *component;
    uint32_t instance_slots;
    uint8_t link_state, array_kind;
    uint8_t init_state; /* 0=uninitialized, 1=in progress, 2=done, 3=failed */
    uint8_t builtin, primitive;
    uint16_t monitor_depth;
    int32_t mirror;
    JbvStatus init_error;
} JbvClass;
typedef struct JbvObject {
    JbvClass *type;
    uint32_t length, gc_next;
    size_t bytes;
    uint8_t mark;
    uint8_t interned; /* Weak intern membership; literals are rooted by their CP. */
    uint16_t monitor_depth;
    /* int32 fields/elements follow this header (zero initialized). */
} JbvObject;
typedef struct JbvHandle {
    JbvObject *object;
    uint32_t generation, pins, next_free;
} JbvHandle;
typedef struct JbvFrame {
    struct JbvFrame *previous;
    JbvClass *owner;
    JbvMethod *method;
    const uint32_t *pc;
    uint32_t base, locals;
    const uint32_t *sp;
    uint8_t has_monitors;
} JbvFrame;

typedef struct JbvFPEnv { uint32_t control,status,tag,ip,cs,data,ds,mxcsr; } JbvFPEnv;
typedef struct JbvMonitor { uint16_t *counter; JbvFrame *frame; } JbvMonitor;
typedef struct JbvNativeFrame {
    struct JbvNativeFrame *previous;
    void *user;
    JbvStatus status;
} JbvNativeFrame;
struct JbvVM {
    JbvConfig config;
    size_t memory_used, memory_peak;
    JbvClass *classes;
    int32_t *slots;
    uint32_t used_slots, depth;
    uint64_t remaining;
    uint8_t *slot_refs; /* GC reference bits (0/1), not operand verification tags. */
    JbvFrame *frames;
    JbvNativeFrame *native_frame;
    JbvHandle *handles;
    uint32_t handle_capacity, free_handle, object_count;
    size_t heap_bytes, heap_limit;
    uint64_t collections;
    int32_t exception;
    int32_t emergency_oom; /* Weak handle: at most one live emergency exception. */
    JbvStatus exception_status;
    JbvHostServices services;
    uint8_t fp_ready;
    JbvMonitor *monitors;
    uint32_t monitor_capacity;
    JbvArchive library, app; /* Built-in class library and the application JAR. */
};

void *jbv_alloc(JbvVM *vm, size_t bytes);
void jbv_free(JbvVM *vm, void *memory);
int jbv_text_eq(JbvText a, JbvText b);
int jbv_text_is(JbvText a, const char *s);
JbvText jbv_text(const char *s);
JbvConstant *jbv_cp(JbvClass *c, uint16_t index, uint8_t tag);
JbvClass *jbv_find_class(JbvVM *vm, JbvText name);
JbvMethod *jbv_find_method(JbvClass *c, JbvText name, JbvText descriptor);
JbvField *jbv_find_field(JbvClass *c, JbvText name, JbvText descriptor);
JbvStatus jbv_bootstrap(JbvVM *vm);
JbvStatus jbv_library_object(JbvVM *vm, JbvClass *type);
#if JBV_PROFILE_FULL
/* JBV_OK if the built-in library has the class, JBV_NOT_FOUND, or a load error. */
JbvStatus jbv_classpath_find(JbvVM *vm, JbvText name, const uint8_t **data, uint32_t *size);
#else /* No embedded library. */
#define jbv_classpath_find(vm, name, data, size) JBV_NOT_FOUND
#endif
JbvStatus jbv_archive_open(JbvVM *vm, JbvArchive *archive, const uint8_t *jar, size_t size);
JbvStatus jbv_archive_find(const JbvArchive *archive, JbvText name, const uint8_t **data, uint32_t *size);
/* Built-in library class, then a class of the application JAR (linked). */
JbvStatus jbv_lazy_class(JbvVM *vm, JbvText name, JbvClass **out);
void jbv_free_image(JbvVM *vm, uint8_t *image);
uint8_t jbv_library_id(JbvText name);
JbvStatus jbv_library_class(JbvVM *vm, JbvText name, JbvClass **out);
JbvStatus jbv_library_initialize(JbvVM *vm, JbvClass *type);
JbvStatus jbv_literal(JbvVM *vm, JbvClass *owner, uint16_t index, int32_t *out);
JbvStatus jbv_mirror(JbvVM *vm, JbvClass *type, int32_t *out);
JbvStatus jbv_link(JbvVM *vm, JbvClass *c, uint32_t depth);
JbvStatus jbv_resolve_class(JbvVM *vm, JbvText name, JbvClass **out);
JbvStatus jbv_array_class(JbvVM *vm, JbvClass *component, uint8_t kind, JbvClass **out);
JbvStatus jbv_class_constant(JbvVM *vm, JbvClass *c, uint16_t index, JbvClass **out);
int jbv_assignable(JbvClass *from, JbvClass *to);
JbvMethod *jbv_lookup_method(JbvClass **owner, JbvText name, JbvText descriptor);
JbvField *jbv_lookup_field(JbvClass **owner, JbvText name, JbvText descriptor);
int jbv_same_package(JbvClass *a, JbvClass *b);
JbvStatus jbv_class_access(JbvVM *vm, JbvClass *caller, JbvClass *target);
JbvStatus jbv_member_access(JbvVM *vm, JbvClass *caller, JbvClass *owner, uint16_t flags, JbvClass *receiver);
JbvMethod *jbv_virtual_method(JbvClass **owner, JbvClass *resolved, JbvMethod *method);
JbvStatus jbv_constant(JbvVM *vm, JbvClass *owner, uint16_t index, uint64_t *out, uint8_t *kind);
JbvStatus jbv_dynamic_native(JbvVM *vm, uint32_t op, const int32_t *args, uint64_t *out);
JbvStatus jbv_polymorphic(JbvVM *vm, int32_t handle, JbvText descriptor, const int32_t *args, int exact, uint64_t *out);
int jbv_reference_type(JbvText descriptor);
JbvStatus jbv_check_reference(JbvVM *vm, int32_t ref, JbvText descriptor);
JbvStatus jbv_new(JbvVM *vm, JbvClass *type, int32_t length, int32_t *ref);
JbvStatus jbv_multi_array(JbvVM *vm, JbvClass *type, const int32_t *sizes, uint8_t dimensions, int32_t *ref);
JbvStatus jbv_object(JbvVM *vm, int32_t ref, JbvObject **out);
void jbv_free_heap(JbvVM *vm);
void jbv_free_class(JbvVM *vm, JbvClass *c);
JbvStatus jbv_parse(JbvVM *vm, const void *bytes, size_t size, JbvClass **out);
/* Adopts image: a jbv_alloc buffer or a slice of vm->library; released on failure. */
JbvStatus jbv_parse_owned(JbvVM *vm, uint8_t *image, size_t size, JbvClass **out);
JbvStatus jbv_signature(JbvText descriptor, uint16_t *args, int *returns);
int jbv_descriptor_type(JbvText descriptor, uint32_t *pos, uint32_t *width);
void jbv_prepare_method(JbvMethod *method);
void jbv_begin_call(JbvVM *vm);
JbvStatus jbv_typed_call(JbvVM *vm, JbvMethod *method, const int32_t *args, uint16_t count, uint64_t *out);
JbvStatus jbv_native_call(JbvVM *vm, JbvMethod *method, const int32_t *args, uint16_t count, uint64_t *out);
void jbv_fp_enter(JbvFPEnv *state);
void jbv_fp_restore(const JbvFPEnv *state);
JbvStatus jbv_monitor(JbvVM *vm, JbvClass *type, int32_t ref, int action);
void jbv_release_monitors(JbvVM *vm, JbvFrame *frame);
int32_t jbv_narrow(int32_t value, uint8_t type);
JbvText jbv_return_type(JbvText descriptor);
JbvStatus jbv_arguments(JbvVM *vm, JbvClass *owner, JbvMethod *method,
    const int32_t *args, uint16_t count, uint8_t *refs, int pin);
JbvStatus jbv_initialize(JbvVM *vm, JbvClass *c);
JbvStatus jbv_execute(JbvVM *vm, JbvClass *c, JbvMethod *m,
    const int32_t *args, const uint8_t *refs, uint16_t count, uint64_t *result);
enum { JBV_INT, JBV_REF, JBV_LONG, JBV_HIGH, JBV_FLOAT, JBV_DOUBLE, JBV_DHIGH, JBV_TOP };
uint8_t jbv_kind(uint8_t descriptor);
#ifdef _MSC_VER
#define JBV_INLINE static __forceinline
#else
#define JBV_INLINE static inline
#endif
JBV_INLINE int32_t *jbv_data(JbvObject *object) { return (int32_t *)(object + 1); }
JBV_INLINE uint16_t *jbv_chars(JbvObject *object) { return (uint16_t *)(object + 1); }
/* Preserve the modulo-2^32 result without an out-of-line call at every
 * integer operation. Both supported Windows ABIs use two's complement. */
JBV_INLINE int32_t jbv_i32(uint32_t n) {
    return n <= INT32_MAX ? (int32_t)n : -1 - (int32_t)(UINT32_MAX - n);
}
JBV_INLINE uint32_t jbv_width(uint8_t kind) { return kind == JBV_LONG || kind == JBV_DOUBLE ? 2u : 1u; }
JBV_INLINE uint64_t jbv_slot_bits(const int32_t *slots, uint8_t kind) {
    uint64_t bits = (uint32_t)slots[0];
    if (jbv_width(kind) == 2) bits |= (uint64_t)(uint32_t)slots[1] << 32;
    return bits;
}
JBV_INLINE void jbv_put_bits(int32_t *slots, uint64_t bits, uint8_t kind) {
    slots[0] = jbv_i32((uint32_t)bits);
    if (jbv_width(kind) == 2) slots[1] = jbv_i32((uint32_t)(bits >> 32));
}
uint32_t jbv_numeric_types(uint8_t op);
JbvStatus jbv_numeric(uint8_t op, uint64_t a, uint64_t b, uint64_t *out);
int jbv_exception_name(JbvText name);
JbvStatus jbv_exception_class(JbvVM *vm, JbvText name, JbvClass **out);
JbvStatus jbv_raise(JbvVM *vm, JbvStatus status);
JbvStatus jbv_capture_trace(JbvVM *vm, int32_t *out);
JbvStatus jbv_throw_named(JbvVM *vm, const char *name, int32_t cause, JbvStatus status);
/* Like jbv_throw_named with detail message owner[.member][descriptor]; '/' in owner
 * becomes '.' when dots is set. The core profile has no strings: no message. */
JbvStatus jbv_throw_detail(JbvVM *vm, const char *name, JbvText owner, JbvText member, JbvText descriptor, int dots, JbvStatus status);
uint16_t jbv_u16(const uint8_t *p);
uint32_t jbv_u32(const uint8_t *p);
#endif

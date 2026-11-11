#include "internal.h"
#include "classpath.h"

typedef struct ExceptionSpec { const char *name, *parent; } ExceptionSpec;
#define L "java/lang/"
static const ExceptionSpec types[] = {
    {L "Throwable", L "Object"}, {L "Exception", L "Throwable"},
    {L "RuntimeException", L "Exception"}, {L "Error", L "Throwable"},
    {L "ArithmeticException", L "RuntimeException"},
    {L "NullPointerException", L "RuntimeException"},
    {L "IndexOutOfBoundsException", L "RuntimeException"},
    {L "ArrayIndexOutOfBoundsException", L "IndexOutOfBoundsException"},
    {L "StringIndexOutOfBoundsException", L "IndexOutOfBoundsException"},
    {L "NegativeArraySizeException", L "RuntimeException"},
    {L "ArrayStoreException", L "RuntimeException"},
    {L "ClassCastException", L "RuntimeException"},
    {L "IllegalArgumentException", L "RuntimeException"},
    {L "NumberFormatException", L "IllegalArgumentException"},
    {L "IllegalStateException", L "RuntimeException"},
    {L "IllegalMonitorStateException", L "RuntimeException"},
    {L "UnsupportedOperationException", L "RuntimeException"},
    {L "LinkageError", L "Error"}, {L "UnsatisfiedLinkError", L "LinkageError"},
    {L "NoClassDefFoundError", L "LinkageError"},
    {L "IncompatibleClassChangeError", L "LinkageError"},
    {L "IllegalAccessError", L "IncompatibleClassChangeError"},
    {L "AbstractMethodError", L "IncompatibleClassChangeError"},
    {L "InstantiationError", L "IncompatibleClassChangeError"},
    {L "NoSuchMethodError", L "IncompatibleClassChangeError"},
    {L "NoSuchFieldError", L "IncompatibleClassChangeError"},
    {L "BootstrapMethodError", L "LinkageError"},
    {L "ExceptionInInitializerError", L "LinkageError"},
    {L "VirtualMachineError", L "Error"}, {L "OutOfMemoryError", L "VirtualMachineError"},
    {L "StackOverflowError", L "VirtualMachineError"},
    {L "AssertionError", L "Error"},
    {L "ReflectiveOperationException", L "Exception"},
    {L "NoSuchMethodException", L "ReflectiveOperationException"},
    {L "NoSuchFieldException", L "ReflectiveOperationException"},
#if JBV_PROFILE_FULL
    {L "ClassNotFoundException", L "ReflectiveOperationException"},
    {L "InstantiationException", L "ReflectiveOperationException"},
    {"java/lang/annotation/IncompleteAnnotationException", L "RuntimeException"},
    {L "EnumConstantNotPresentException", L "RuntimeException"},
#endif
    {"java/lang/invoke/WrongMethodTypeException", L "RuntimeException"},
    {L "IllegalAccessException", L "ReflectiveOperationException"},
    {L "CloneNotSupportedException", L "Exception"},
    {"java/util/NoSuchElementException", L "RuntimeException"},
    {"java/util/ConcurrentModificationException", L "RuntimeException"}
};
enum { E_INIT, E_MESSAGE, E_CAUSE_INIT, E_BOTH, E_OPTIONS, E_GET_MESSAGE, E_GET_CAUSE,
    E_INIT_CAUSE, E_ADD_SUPPRESSED, E_GET_SUPPRESSED };
typedef struct ExceptionMethod { const char *name, *descriptor; } ExceptionMethod;
static const ExceptionMethod methods[] = {
    {"<init>", "()V"}, {"<init>", "(Ljava/lang/String;)V"},
    {"<init>", "(Ljava/lang/Throwable;)V"},
    {"<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V"},
    {"<init>", "(Ljava/lang/String;Ljava/lang/Throwable;ZZ)V"},
    {"getMessage", "()Ljava/lang/String;"}, {"getCause", "()Ljava/lang/Throwable;"},
    {"initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;"},
    {"addSuppressed", "(Ljava/lang/Throwable;)V"},
    {"getSuppressed", "()[Ljava/lang/Throwable;"}
};
/* Throwable payload is ordinary traced fields: message, cause, suppressed. */
JBV_GC static JbvStatus JBV_CALL exception_native(JbvVM *vm, void *user, const int32_t *a, uint16_t count, int32_t *out) {
    JbvObject *object, *old = 0, *array = 0;
    int32_t *fields, ref = 0;
    uint32_t id = (uint32_t)(uintptr_t)user, i, length = 0;
    JbvClass *throwable, *array_type = 0;
    JbvStatus status = jbv_object(vm, a[0], &object);
    if (status != JBV_OK) return status;
    fields = jbv_data(object);
    throwable = jbv_find_class(vm, jbv_text(L "Throwable"));
    if (throwable && throwable->instance_slots > 3 && id <= E_OPTIONS) {
        JbvMethod *ctor = jbv_find_method(throwable, jbv_text("<init>"), jbv_text(methods[id].descriptor));
        uint64_t ignored;
        return ctor ? jbv_execute(vm, throwable, ctor, a, 0, count, &ignored) : JBV_NOT_FOUND;
    }
    switch (id) {
    case E_INIT: case E_MESSAGE: case E_CAUSE_INIT: case E_BOTH: case E_OPTIONS:
        fields[0] = id == E_MESSAGE || id == E_BOTH || id == E_OPTIONS ? a[1] : 0;
        fields[1] = id == E_CAUSE_INIT ? a[1] : id == E_BOTH || id == E_OPTIONS ? a[2] : a[0];
        fields[2] = 0;
        jbv_barrier_checked(vm, object, fields[0]); jbv_barrier_checked(vm, object, fields[1]);
        return JBV_OK;
    case E_GET_MESSAGE: *out = fields[0]; return JBV_OK;
    case E_GET_CAUSE: *out = fields[1] == a[0] ? 0 : fields[1]; return JBV_OK;
    case E_INIT_CAUSE:
        if (fields[1] != a[0]) return JBV_ILLEGAL_STATE; /* IllegalStateException */
        if (a[1] == a[0]) return JBV_BAD_ARGUMENT;
        fields[1] = a[1]; jbv_barrier_checked(vm, object, a[1]); *out = a[0]; return JBV_OK;
    case E_ADD_SUPPRESSED:
        if (!a[1]) return JBV_NULL_REFERENCE;
        if (a[1] == a[0]) return JBV_BAD_ARGUMENT;
        break;
    case E_GET_SUPPRESSED: break;
    default: return JBV_UNSUPPORTED_FEATURE;
    }
    if (fields[2]) {
        status = jbv_object(vm, fields[2], &old);
        if (status != JBV_OK) return status;
        length = jbv_length(old);
    }
    status = jbv_exception_class(vm, jbv_text(L "Throwable"), &throwable);
    if (status == JBV_OK) status = jbv_array_class(vm, throwable, 'L', &array_type);
    if (status == JBV_OK) status = jbv_new(vm, array_type, (int32_t)(length + (id == E_ADD_SUPPRESSED)), &ref);
    if (status == JBV_OK) status = jbv_object(vm, ref, &array);
    if (status != JBV_OK) return status;
    /* jbv_new may have moved everything: fetch the receiver and the old array again. */
    (void)jbv_object(vm, a[0], &object); fields = jbv_data(object);
    if (length) (void)jbv_object(vm, fields[2], &old);
    for (i = 0; i < length; ++i) jbv_data(array)[i] = jbv_data(old)[i];
    if (id == E_ADD_SUPPRESSED) { jbv_data(array)[length] = a[1]; jbv_barrier_checked(vm, array, a[1]); fields[2] = ref; jbv_barrier_checked(vm, object, ref); }
    else *out = ref;
    return JBV_OK;
}
int jbv_exception_name(JbvText name) {
    uint32_t i;
    for (i = 0; i < sizeof(types) / sizeof(types[0]); ++i)
        if (jbv_text_is(name, types[i].name)) return 1;
    return 0;
}
JbvStatus jbv_exception_class(JbvVM *vm, JbvText name, JbvClass **out) {
    JbvClass *c = jbv_find_class(vm, name), *parent;
    JbvStatus status;
    uint32_t i, j;
    if (c) { *out = c; return jbv_link(vm, c, 0); }
    status = jbv_classpath_find(vm, name, 0, 0);
    if (status == JBV_OK) return jbv_classpath_load(vm, name, out);
    if (status != JBV_NOT_FOUND) return status;
    for (i = 0; i < sizeof(types) / sizeof(types[0]); ++i) if (jbv_text_is(name, types[i].name)) break;
    if (i == sizeof(types) / sizeof(types[0])) return JBV_NOT_FOUND;
    status = jbv_resolve_class(vm, jbv_text(types[i].parent), &parent);
    if (status != JBV_OK) return status;
    c = (JbvClass *)jbv_alloc(vm, sizeof(*c));
    if (!c) return JBV_OUT_OF_MEMORY;
    c->name = jbv_text(types[i].name); c->super = parent;
    c->flags = 1; c->instance_slots = parent->instance_slots > 3 ? parent->instance_slots : 3; c->init_state = c->link_state = 2;
    c->next = vm->classes; vm->classes = c;
    c->methods = (JbvMethod *)jbv_alloc(vm, sizeof(methods) / sizeof(methods[0]) * sizeof(*c->methods));
    if (!c->methods) { status = JBV_OUT_OF_MEMORY; goto fail; }
    c->method_count = c->instance_slots > 3 ? 5 : sizeof(methods) / sizeof(methods[0]);
    for (j = 0; j < c->method_count; ++j) {
        c->methods[j].name = jbv_text(methods[j].name);
        c->methods[j].descriptor = jbv_text(methods[j].descriptor);
        c->methods[j].flags = (j == E_OPTIONS ? 4 : 1) | JBV_NATIVE;
        c->methods[j].intrinsic = 2;
        c->methods[j].native = exception_native;
        c->methods[j].native_user = (void *)(uintptr_t)j;
        jbv_prepare_method(&c->methods[j]);
    }
    if (!i) {
        c->fields = (JbvField *)jbv_alloc(vm, 3 * sizeof(*c->fields));
        if (!c->fields) { status = JBV_OUT_OF_MEMORY; goto fail; }
        c->field_count = 3;
        for (j = 0; j < 3; ++j) {
            c->fields[j].name = jbv_text(j == 0 ? "detailMessage" : j == 1 ? "cause" : "suppressed");
            c->fields[j].descriptor = jbv_text(j == 0 ? "Ljava/lang/String;" : j == 1 ? "Ljava/lang/Throwable;" : "[Ljava/lang/Throwable;");
            c->fields[j].slot = j;
        }
    }
    *out = c; return JBV_OK;
fail:
    vm->classes = c->next; jbv_free_class(vm, c); return status;
}
JbvStatus jbv_throw_named(JbvVM *vm, const char *name, int32_t cause, JbvStatus status) {
    JbvClass *type;
    JbvObject *object;
    int32_t ref;
    size_t limit;
    int emergency = jbv_text_is(jbv_text(name), L "OutOfMemoryError");
    if (emergency && jbv_object(vm, vm->emergency_oom, &object) == JBV_OK) {
        vm->exception = vm->emergency_oom; vm->exception_status = status; return status;
    }
    if (jbv_exception_class(vm, jbv_text(name), &type) != JBV_OK) return status;
    limit = vm->heap_limit;
    /* A heap-limit OOME may use one small emergency object beyond the limit.
     * Host allocator failure still reports the original C status. */
    if (emergency) vm->heap_limit = SIZE_MAX;
    { JbvStatus allocated = jbv_new(vm, type, 0, &ref); vm->heap_limit = limit; if (allocated != JBV_OK) return status; }
    vm->exception = ref; vm->exception_status = status;
    if (emergency) vm->emergency_oom = ref;
    if (jbv_object(vm, ref, &object) == JBV_OK) {
        int32_t *fields=jbv_data(object), trace = 0;
        fields[1] = cause ? cause : ref;
        jbv_barrier_checked(vm, object, fields[1]);
        if (type->instance_slots > 3) {
            fields[4]=fields[5]=1;
            /* Capturing allocates (the exception stays rooted in vm->exception): store afterwards. */
            if (jbv_capture_trace(vm,&trace) == JBV_OK && jbv_object(vm, ref, &object) == JBV_OK) { jbv_data(object)[3] = trace; jbv_barrier_checked(vm, object, trace); }
        }
    }
    return status;
}
JbvStatus jbv_throw_detail(JbvVM *vm, const char *name, JbvText owner, JbvText member, JbvText descriptor, int dots, JbvStatus status) {
#if JBV_PROFILE_CORE
    (void)owner; (void)member; (void)descriptor; (void)dots;
    return jbv_throw_named(vm, name, 0, status);
#else
    JbvObject *object;
    JbvText text;
    uint8_t *buffer;
    int32_t message;
    uint32_t size = (uint32_t)owner.size + member.size + descriptor.size + 1, i, n = 0;
    status = jbv_throw_named(vm, name, 0, status);
    if (!vm->exception || vm->exception == vm->emergency_oom || size > 0xffff) return status;
    buffer = (uint8_t *)jbv_alloc(vm, size);
    if (!buffer) return status;
    for (i = 0; i < owner.size; ++i) buffer[n++] = dots && owner.data[i] == '/' ? '.' : owner.data[i];
    if (member.size) { buffer[n++] = '.'; for (i = 0; i < member.size; ++i) buffer[n++] = member.data[i]; }
    for (i = 0; i < descriptor.size; ++i) buffer[n++] = descriptor.data[i];
    text.data = buffer; text.size = (uint16_t)n;
    if (jbv_string_mutf(vm, text, &message) == JBV_OK && jbv_object(vm, vm->exception, &object) == JBV_OK) jbv_data(object)[0] = message;
    jbv_free(vm, buffer);
    return status;
#endif
}
JbvStatus jbv_raise(JbvVM *vm, JbvStatus status) {
    const char *name;
    if (vm->exception && vm->exception_status == status) return status;
    vm->exception = 0; vm->exception_status = JBV_OK;
    switch (status) {
    case JBV_OUT_OF_MEMORY: name = L "OutOfMemoryError"; break;
    case JBV_DIVIDE_BY_ZERO: { JbvText none = {0, 0}; return jbv_throw_detail(vm, L "ArithmeticException", jbv_text("/ by zero"), none, none, 0, status); }
    case JBV_NULL_REFERENCE: name = L "NullPointerException"; break;
    case JBV_ARRAY_BOUNDS: name = L "ArrayIndexOutOfBoundsException"; break;
    case JBV_NEGATIVE_ARRAY_SIZE: name = L "NegativeArraySizeException"; break;
    case JBV_ARRAY_STORE: name = L "ArrayStoreException"; break;
    case JBV_CLASS_CAST: name = L "ClassCastException"; break;
    case JBV_MONITOR_STATE: name = L "IllegalMonitorStateException"; break;
    case JBV_BAD_ARGUMENT: name = L "IllegalArgumentException"; break;
    case JBV_ILLEGAL_STATE: case JBV_BUSY: name = L "IllegalStateException"; break;
    case JBV_NATIVE_ERROR: name = L "UnsatisfiedLinkError"; break;
    default: return status;
    }
    return jbv_throw_named(vm, name, 0, status);
}
JBV_API JbvStatus JBV_CALL jbv_exception(JbvVM *vm, JbvRef *out) {
    JbvStatus status;
    if (!vm || !out) return JBV_BAD_ARGUMENT;
    status = jbv_retain(vm, vm->exception);
    if (status == JBV_OK) *out = vm->exception;
    return status;
}

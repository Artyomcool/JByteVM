#include "internal.h"
#include <stdarg.h>

void jbv_fp_enter(JbvFPEnv *state) {
#if defined(_M_IX86)
    __asm mov eax,state
    __asm fnstenv [eax]
    __asm stmxcsr [eax+28]
    __asm fnclex
    __asm push 027fh
    __asm fldcw word ptr [esp]
    __asm mov dword ptr [esp],01f80h
    __asm ldmxcsr [esp]
    __asm add esp,4
#else
    (void)state;
#endif
}
void jbv_fp_restore(const JbvFPEnv *state) {
#if defined(_M_IX86)
    __asm mov eax,state
    __asm fldenv [eax]
    __asm ldmxcsr [eax+28]
#else
    (void)state;
#endif
}
/* The stack blob is written only by fixed-size FNSTENV/STMXCSR instructions. */
__declspec(safebuffers)
JbvStatus jbv_native_call(JbvVM *vm, JbvMethod *m, const int32_t *args, uint16_t count, uint64_t *out) {
    JbvFPEnv state;
    JbvStatus status;
    jbv_fp_enter(&state); vm->fp_ready = 0;
    if (m->flags & JBV_TYPED_NATIVE) status = jbv_typed_call(vm,m,args,count,out);
    else if (m->native_slots) status = m->native_slots(vm,m->native_user,args,count,out);
    else if (m->native) {
        int32_t result = 0;
        if (m->result_kind && jbv_width((uint8_t)(m->result_kind-1)) == 2) status = JBV_UNSUPPORTED_FEATURE;
        else { status = m->native(vm,m->native_user,args,count,&result); *out = (uint32_t)result; }
    } else status = JBV_NOT_FOUND;
    jbv_fp_restore(&state); vm->fp_ready = 1;
    return status;
}

JBV_API JbvStatus JBV_CALL jbv_register_natives(JbvVM *vm, const char *class_name,
    const JbvNativeEntry *entries, uint32_t count, void *user) {
#if defined(_M_IX86)
    JbvClass *c;
    uint32_t i, j;
    if (!vm || !class_name || (count && !entries)) return JBV_BAD_ARGUMENT;
    if (vm->depth) return JBV_BUSY;
    c = jbv_find_class(vm, jbv_text(class_name));
    if (!c) { JbvStatus status = jbv_lazy_class(vm, jbv_text(class_name), &c); if (status != JBV_OK) return status; }
    if (count > c->method_count) return JBV_BAD_ARGUMENT;
    /* Validate the entire table before mutating any method. No allocations,
     * class initialization or callbacks occur between these two passes. */
    for (i = 0; i < count; ++i) {
        const JbvNativeEntry *e = &entries[i];
        JbvMethod *m;
        if (!e->name || !e->descriptor || !e->function) return JBV_BAD_ARGUMENT;
        m = jbv_find_method(c, jbv_text(e->name), jbv_text(e->descriptor));
        if (!m) return JBV_NOT_FOUND;
        if (!(m->flags & JBV_NATIVE) || m->intrinsic) return JBV_LINKAGE_ERROR;
        if (!(m->flags & JBV_STATIC)) return JBV_UNSUPPORTED_FEATURE;
        for (j = 0; j < i; ++j)
            if (jbv_text_is(m->name, entries[j].name) && jbv_text_is(m->descriptor, entries[j].descriptor))
                return JBV_BAD_ARGUMENT;
    }
    for (i = 0; i < count; ++i) {
        JbvMethod *m = jbv_find_method(c, jbv_text(entries[i].name), jbv_text(entries[i].descriptor));
        m->native_slots = (JbvNativeSlots)entries[i].function;
        m->native = 0; m->native_user = user;
        m->flags |= JBV_TYPED_NATIVE;
    }
    return JBV_OK;
#else
    (void)vm; (void)class_name; (void)entries; (void)count; (void)user;
    return JBV_UNSUPPORTED_FEATURE;
#endif
}

#if defined(_M_IX86)
/* Explicit cdecl boundary: internal C code is otherwise built with /Gr. */
uint64_t JBV_CALL jbv_native_x86(JbvNativeFunction function, JbvVM *vm,
    const int32_t *args, uint32_t count, uint32_t result_kind);
#endif
JbvStatus jbv_typed_call(JbvVM *vm, JbvMethod *m, const int32_t *args, uint16_t count, uint64_t *out) {
#if defined(_M_IX86)
    JbvNativeFrame frame;
    frame.previous = vm->native_frame; frame.user = m->native_user; frame.status = JBV_OK;
    vm->native_frame = &frame;
    *out = jbv_native_x86((JbvNativeFunction)m->native_slots, vm, args, count, m->result_kind);
    vm->native_frame = frame.previous;
    if (frame.status == JBV_OK && vm->exception) frame.status = vm->exception_status;
    return frame.status;
#else
    (void)vm; (void)m; (void)args; (void)count; (void)out;
    return JBV_UNSUPPORTED_FEATURE;
#endif
}

JBV_API void *JBV_CALL jbv_native_context(JbvVM *vm) {
    return vm && vm->native_frame ? vm->native_frame->user : 0;
}
JBV_API JbvStatus JBV_CALL jbv_native_fail(JbvVM *vm, JbvStatus status) {
    if (!vm || !vm->native_frame || status == JBV_OK) return JBV_BAD_ARGUMENT;
    vm->native_frame->status = status;
    return status;
}

void jbv_begin_call(JbvVM *vm) {
    if (!vm->depth) {
        vm->remaining = vm->config.max_instructions;
        vm->exception = 0; vm->exception_status = JBV_OK;
    }
}

JBV_API JbvStatus JBV_CALL jbv_resolve_method(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvMethodId *out) {
    JbvClass *c;
    JbvMethod *m;
    JbvStatus status;
    JbvText n, d;
    if (!vm || !class_name || !name || !descriptor || !out) return JBV_BAD_ARGUMENT;
    n = jbv_text(name); d = jbv_text(descriptor);
    if (jbv_text_is(n, "<clinit>")) return JBV_UNSUPPORTED_FEATURE;
    status = jbv_resolve_class(vm, jbv_text(class_name), &c);
    if (status != JBV_OK) return status;
    m = jbv_text_is(n, "<init>") ? jbv_find_method(c, n, d) : jbv_lookup_method(&c, n, d);
    if (!m) return c ? JBV_NOT_FOUND : JBV_LINKAGE_ERROR;
    out->owner = c; out->method = m;
    return JBV_OK;
}

JBV_API JbvStatus JBV_CALL jbv_invoke(JbvVM *vm, const JbvMethodId *id,
    const int32_t *args, uint16_t count, uint64_t *result) {
    JbvClass *owner, *target_owner;
    JbvMethod *m, *target;
    JbvStatus status;
    uint64_t value = 0;
    if (!vm || !id || !id->owner || !id->method || !result || (count && !args)) return JBV_BAD_ARGUMENT;
    jbv_begin_call(vm);
    owner = target_owner = (JbvClass *)id->owner;
    m = target = (JbvMethod *)id->method;
    if (count != m->argument_slots) return JBV_BAD_ARGUMENT;
    status = jbv_arguments(vm, owner, m, args, count, 0, 1);
    if (status != JBV_OK) return status;
    if (m->flags & JBV_STATIC) status = jbv_initialize(vm, owner);
    else if (!(m->flags & 0x0002) && !jbv_text_is(m->name, "<init>")) {
        JbvObject *receiver;
        status = jbv_object(vm, args[0], &receiver);
        if (status == JBV_OK) {
            target_owner = receiver->type;
            target = jbv_lookup_method(&target_owner, m->name, m->descriptor);
            if (!target || (target->flags & (JBV_STATIC | JBV_ABSTRACT))) status = JBV_LINKAGE_ERROR;
        }
    }
    if (status == JBV_OK) status = jbv_execute(vm, target_owner, target, args, 0, count, &value);
    if (status == JBV_OK && m->result_kind == JBV_REF + 1) status = jbv_retain(vm, jbv_i32((uint32_t)value));
    (void)jbv_arguments(vm, owner, m, args, count, 0, -1);
    if (status == JBV_OK) *result = value;
    return status;
}

/* This bounded slot buffer needs no CRT /GS cookie machinery. Keep /GS enabled
 * for the rest of the build; the explicit width guard bounds every write. */
#ifdef _MSC_VER
__declspec(safebuffers)
#endif
JBV_API JbvStatus JBV_CALL jbv_invoke_args(JbvVM *vm, const JbvMethodId *id, JbvValue *out, ...) {
    JbvMethod *m;
    int32_t slots[255];
    uint32_t pos = 1, count = 0, width;
    uint64_t result = 0;
    JbvStatus status = JBV_OK;
    va_list ap;
    if (!vm || !id || !id->owner || !id->method || !out) return JBV_BAD_ARGUMENT;
    m = (JbvMethod *)id->method;
    if (!(m->flags & JBV_STATIC)) return JBV_UNSUPPORTED_FEATURE;
    va_start(ap, out);
    while (m->descriptor.data[pos] != ')') {
        uint8_t kind = jbv_kind(m->descriptor.data[pos]);
        JbvValue value;
        value.bits = 0;
        if (!jbv_descriptor_type(m->descriptor, &pos, &width)) { status = JBV_BAD_CLASS; break; }
        if (width > 255 - count) { status = JBV_BAD_ARGUMENT; break; }
        if (kind == JBV_LONG) value.j = va_arg(ap, int64_t);
        else if (kind == JBV_DOUBLE) value.d = va_arg(ap, double);
        else if (kind == JBV_FLOAT) value.f = (float)va_arg(ap, double);
        else value.i = va_arg(ap, int32_t);
        jbv_put_bits(slots + count, value.bits, kind);
        count += width;
    }
    va_end(ap);
    if (status == JBV_OK) status = jbv_invoke(vm, id, slots, (uint16_t)count, &result);
    if (status == JBV_OK) out->bits = result;
    return status;
}

JBV_API JbvStatus JBV_CALL jbv_alloc_object(JbvVM *vm, const char *class_name, JbvRef *out) {
    JbvClass *c;
    JbvStatus status;
    int32_t ref = 0;
    if (!vm || !class_name || !out) return JBV_BAD_ARGUMENT;
    jbv_begin_call(vm);
    status = jbv_resolve_class(vm, jbv_text(class_name), &c);
    if (status != JBV_OK) return status;
    if (c->array_kind) return JBV_BAD_ARGUMENT;
    status = jbv_initialize(vm, c);
    if (status == JBV_OK) status = jbv_new(vm, c, 0, &ref);
    if (status == JBV_OK) status = jbv_retain(vm, ref);
    if (status == JBV_OK) *out = ref;
    return status;
}

JBV_API JbvStatus JBV_CALL jbv_new_array(JbvVM *vm, const char *descriptor, int32_t length, JbvRef *out) {
    JbvClass *c;
    JbvStatus status;
    int32_t ref = 0;
    if (!vm || !descriptor || descriptor[0] != '[' || !out) return JBV_BAD_ARGUMENT;
    status = jbv_resolve_class(vm, jbv_text(descriptor), &c);
    if (status == JBV_OK) status = jbv_new(vm, c, length, &ref);
    if (status == JBV_OK) status = jbv_retain(vm, ref);
    if (status == JBV_OK) *out = ref;
    return status;
}

JBV_API JbvStatus JBV_CALL jbv_resolve_field(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvFieldId *out) {
    JbvClass *c;
    JbvField *f;
    JbvStatus status;
    if (!vm || !class_name || !name || !descriptor || !out) return JBV_BAD_ARGUMENT;
    status = jbv_resolve_class(vm, jbv_text(class_name), &c);
    if (status != JBV_OK) return status;
    f = jbv_lookup_field(&c, jbv_text(name), jbv_text(descriptor));
    if (!f) return JBV_NOT_FOUND;
    out->owner = c; out->field = f;
    return JBV_OK;
}

static JbvStatus field_location(JbvVM *vm, const JbvFieldId *id, int32_t ref, int32_t **out) {
    JbvClass *c = (JbvClass *)id->owner;
    JbvField *f = (JbvField *)id->field;
    JbvStatus status;
    if (f->flags & JBV_STATIC) {
        if (ref) return JBV_BAD_ARGUMENT;
        if (c->init_state != 2) jbv_begin_call(vm);
        status = jbv_initialize(vm, c);
        if (status == JBV_OK) *out = &f->value;
    } else {
        JbvObject *object;
        status = jbv_object(vm, ref, &object);
        if (status == JBV_OK) {
            if (!jbv_assignable(object->type, c)) return JBV_CLASS_CAST;
            *out = jbv_data(object) + f->slot;
        }
    }
    return status;
}

JBV_API JbvStatus JBV_CALL jbv_get_field(JbvVM *vm, const JbvFieldId *id, JbvRef receiver, uint64_t *out) {
    JbvField *f;
    JbvStatus status;
    int32_t *location;
    uint64_t value;
    uint8_t kind;
    if (!vm || !id || !id->owner || !id->field || !out) return JBV_BAD_ARGUMENT;
    f = (JbvField *)id->field; kind = jbv_kind(f->descriptor.data[0]);
    status = field_location(vm, id, receiver, &location);
    if (status != JBV_OK) return status;
    value = jbv_slot_bits(location, kind);
    if (kind == JBV_REF) status = jbv_retain(vm, jbv_i32((uint32_t)value));
    if (status == JBV_OK) *out = value;
    return status;
}

JBV_API JbvStatus JBV_CALL jbv_set_field(JbvVM *vm, const JbvFieldId *id, JbvRef receiver, uint64_t value) {
    JbvField *f;
    JbvStatus status;
    int32_t *location, ref = jbv_i32((uint32_t)value);
    uint8_t kind;
    if (!vm || !id || !id->owner || !id->field) return JBV_BAD_ARGUMENT;
    f = (JbvField *)id->field; kind = jbv_kind(f->descriptor.data[0]);
    if (kind == JBV_REF) {
        status = jbv_check_reference(vm, ref, f->descriptor);
        if (status == JBV_OK) status = jbv_retain(vm, ref);
        if (status != JBV_OK) return status;
    }
    /* A static initializer can run Java/native code and collect the value. */
    status = field_location(vm, id, receiver, &location);
    if (status == JBV_OK) {
        if (kind == JBV_INT) value = (uint32_t)jbv_narrow(ref, f->descriptor.data[0]);
        jbv_put_bits(location, value, kind);
        if (kind == JBV_REF && receiver) { JbvObject *owner; if (jbv_object(vm, receiver, &owner) == JBV_OK) jbv_barrier_checked(vm, owner, ref); }
    }
    if (kind == JBV_REF) (void)jbv_release(vm, ref);
    return status;
}

static JbvStatus array_range(JbvVM *vm, int32_t ref, uint32_t start, uint32_t count, JbvObject **out) {
    JbvStatus status;
    if (!vm) return JBV_BAD_ARGUMENT;
    status = jbv_object(vm, ref, out);
    if (status != JBV_OK) return status;
    if (!(*out)->type->array_kind) return JBV_BAD_ARGUMENT;
    if (start > jbv_length(*out) || count > jbv_length(*out) - start) return JBV_ARRAY_BOUNDS;
    return JBV_OK;
}

JBV_API JbvStatus JBV_CALL jbv_array_info(JbvVM *vm, JbvRef ref, uint32_t *length, char *kind) {
    JbvObject *array;
    JbvStatus status;
    if (!length) return JBV_BAD_ARGUMENT;
    status = array_range(vm, ref, 0, 0, &array);
    if (status != JBV_OK) return status;
    *length = jbv_length(array);
    if (kind) *kind = (char)array->type->array_kind;
    return JBV_OK;
}

JBV_API JbvStatus JBV_CALL jbv_array_read(JbvVM *vm, JbvRef ref, uint32_t start, uint32_t count, uint64_t *out) {
    JbvObject *array;
    JbvStatus status;
    uint8_t kind;
    uint32_t i, width;
    int32_t *data;
    if (count && !out) return JBV_BAD_ARGUMENT;
    status = array_range(vm, ref, start, count, &array);
    if (status != JBV_OK) return status;
    if (array->type->array_kind != 'L') {
        for (i = 0; i < count; ++i) out[i] = jbv_array_get(array, start + i, array->type->array_kind);
        return JBV_OK;
    }
    kind = jbv_kind(array->type->array_kind); width = jbv_width(kind);
    data = jbv_data(array) + start * width;
    if (kind == JBV_REF) {
        for (i = 0; i < count; ++i) {
            status = jbv_retain(vm, data[i]);
            if (status != JBV_OK) {
                while (i) (void)jbv_release(vm, data[--i]);
                return status;
            }
        }
    }
    for (i = 0; i < count; ++i) out[i] = jbv_slot_bits(data + i * width, kind);
    return JBV_OK;
}

JBV_API JbvStatus JBV_CALL jbv_array_write(JbvVM *vm, JbvRef ref, uint32_t start, uint32_t count, const uint64_t *values) {
    JbvObject *array;
    JbvStatus status;
    uint8_t kind, type;
    uint32_t i, width;
    int32_t *data;
    if (count && !values) return JBV_BAD_ARGUMENT;
    status = array_range(vm, ref, start, count, &array);
    if (status != JBV_OK) return status;
    if (array->type->array_kind != 'L') {
        for (i = 0; i < count; ++i) {
            uint64_t value = values[i];
            if (jbv_kind(array->type->array_kind) == JBV_INT) value = (uint32_t)jbv_narrow(jbv_i32((uint32_t)value), array->type->array_kind);
            jbv_array_set(array, start + i, array->type->array_kind, value);
        }
        return JBV_OK;
    }
    type = array->type->array_kind; kind = jbv_kind(type); width = jbv_width(kind);
    data = jbv_data(array) + start * width;
    if (kind == JBV_REF) {
        for (i = 0; i < count; ++i) {
            int32_t element = jbv_i32((uint32_t)values[i]);
            JbvObject *object;
            if (!element) continue;
            status = jbv_object(vm, element, &object);
            if (status != JBV_OK) return status;
            if (!jbv_assignable(object->type, array->type->component)) return JBV_ARRAY_STORE;
        }
    }
    for (i = 0; i < count; ++i) { data[i] = jbv_i32((uint32_t)values[i]); jbv_barrier_checked(vm, array, data[i]); }
    (void)type; (void)width;
    return JBV_OK;
}

JBV_API JbvStatus JBV_CALL jbv_throw(JbvVM *vm, JbvRef ref) {
    JbvStatus status;
    if (!vm) return JBV_BAD_ARGUMENT;
    if (!ref) return JBV_NULL_REFERENCE;
    status = jbv_check_reference(vm, ref, jbv_text("Ljava/lang/Throwable;"));
    if (status != JBV_OK) return status;
    vm->exception = ref; vm->exception_status = JBV_EXCEPTION;
    return JBV_EXCEPTION;
}

JBV_API JbvStatus JBV_CALL jbv_clear_exception(JbvVM *vm) {
    if (!vm) return JBV_BAD_ARGUMENT;
    vm->exception = 0; vm->exception_status = JBV_OK;
    return JBV_OK;
}

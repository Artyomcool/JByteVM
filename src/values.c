#include "classpath.h"
static const char codes[] = "ZBCSIJFDV";
static const char *const wrappers[] = {"java/lang/Boolean","java/lang/Byte","java/lang/Character","java/lang/Short",
    "java/lang/Integer","java/lang/Long","java/lang/Float","java/lang/Double","java/lang/Void"};

JbvClass *jbv_mirror_type(JbvVM *vm, int32_t ref) {
    JbvObject *o;
    return jbv_object(vm, ref, &o) == JBV_OK && o->type->builtin == B_CLASS ?
        (JbvClass *)(uintptr_t)jbv_slot_bits(jbv_data(o), JBV_LONG) : 0;
}
JbvStatus jbv_text_bytes(JbvVM *vm, int32_t ref, JbvText *out) {
    JbvTextView view;
    uint32_t i, n = 0;
    uint8_t *data;
    JbvStatus status = jbv_string_view(vm, ref, &view);
    if (status != JBV_OK) return status;
    for (i = 0; i < view.length; ++i) {
        n += view.data[i] && view.data[i] < 128 ? 1 : view.data[i] < 2048 ? 2 : 3;
        if (n > UINT16_MAX) return JBV_BAD_ARGUMENT;
    }
    if (n > UINT16_MAX) return JBV_BAD_ARGUMENT;
    data = (uint8_t *)jbv_alloc(vm, n);
    if (!data) return JBV_OUT_OF_MEMORY;
    for (i = n = 0; i < view.length; ++i) {
        uint32_t ch = view.data[i];
        if (ch && ch < 128) data[n++] = (uint8_t)ch;
        else {
            if (ch >= 2048) { data[n++] = (uint8_t)(224 | (ch>>12)); data[n++] = (uint8_t)(128 | ((ch>>6)&63)); }
            else data[n++] = (uint8_t)(192 | (ch>>6));
            data[n++] = (uint8_t)(128 | (ch&63));
        }
    }
    out->data = data; out->size = (uint16_t)n; return JBV_OK;
}
JbvStatus jbv_type_class(JbvVM *vm, JbvText descriptor, JbvClass **out) {
    if (descriptor.size == 1) {
        int32_t ref;
        JbvStatus status = jbv_primitive_mirror(vm, descriptor.data[0], &ref);
        if (status == JBV_OK) *out = jbv_mirror_type(vm, ref);
        return status;
    }
    if (descriptor.size && descriptor.data[0] == 'L') { ++descriptor.data; descriptor.size -= 2; }
    return jbv_resolve_class(vm, descriptor, out);
}
JbvStatus jbv_box(JbvVM *vm, uint8_t code, uint64_t bits, int32_t *out) {
    JbvClass *type;
    JbvMethod *method;
    JbvStatus status;
    uint32_t i;
    int32_t args[2];
    uint64_t result = 0;
    for (i = 0; codes[i] && codes[i] != code; ++i) {}
    if (!codes[i] || code == 'V') return JBV_BAD_ARGUMENT;
    status = jbv_resolve_class(vm, jbv_text(wrappers[i]), &type);
    if (status != JBV_OK) return status;
    for (i = 0; i < type->method_count; ++i) {
        method = &type->methods[i];
        if (jbv_text_is(method->name, "valueOf") && method->descriptor.data[1] == code && method->descriptor.data[2] == ')') {
            jbv_put_bits(args, bits, jbv_kind(code));
            status = jbv_initialize(vm, type);
            if (status == JBV_OK) status = jbv_execute(vm, type, method, args, 0, (uint16_t)jbv_width(jbv_kind(code)), &result);
            if (status == JBV_OK) *out = (int32_t)result;
            return status;
        }
    }
    return JBV_NOT_FOUND;
}
JbvStatus jbv_unbox(JbvVM *vm, int32_t ref, uint8_t target, int explicit_cast, uint64_t *out) {
    JbvObject *o;
    uint8_t source, from, to, op;
    uint32_t i;
    uint64_t bits;
    JbvStatus status;
    if (!ref && explicit_cast) { *out = 0; return JBV_OK; }
    status = jbv_object(vm, ref, &o);
    if (status != JBV_OK) return status;
    for (i = 0; i < 8 && !jbv_text_is(o->type->name, wrappers[i]); ++i) {}
    if (i == 8) return JBV_CLASS_CAST;
    source = (uint8_t)codes[i];
    if (!explicit_cast && source != target && (source == 'Z' || target == 'Z' || target == 'B' || target == 'C' ||
        (target == 'S' && source != 'B') || (target == 'I' && (source == 'J' || source == 'F' || source == 'D')) ||
        (target == 'J' && (source == 'F' || source == 'D')) || (target == 'F' && source == 'D'))) return JBV_CLASS_CAST;
    from = jbv_kind(source); to = jbv_kind(target);
    bits = jbv_slot_bits(jbv_data(o), from);
    if (from != to) {
        /* JVM conversion opcodes form the I/J/F/D conversion matrix. */
        uint8_t row = from == JBV_INT ? 0 : from == JBV_LONG ? 1 : from == JBV_FLOAT ? 2 : 3;
        uint8_t col = to == JBV_INT ? 0 : to == JBV_LONG ? 1 : to == JBV_FLOAT ? 2 : 3;
        op = (uint8_t)(133 + row*3 + col - (col > row));
        status = jbv_numeric(op, bits, 0, &bits);
        if (status != JBV_OK) return status;
    }
    if (to == JBV_INT) bits = (uint32_t)jbv_narrow((int32_t)bits, target);
    *out = bits; return JBV_OK;
}
JbvStatus jbv_from_object(JbvVM *vm, int32_t ref, JbvText type, uint64_t *out) {
    if (jbv_reference_type(type)) {
        JbvStatus status = jbv_check_reference(vm, ref, type);
        if (status == JBV_OK) *out = (uint32_t)ref;
        return status;
    }
    return jbv_unbox(vm, ref, type.data[0], 0, out);
}

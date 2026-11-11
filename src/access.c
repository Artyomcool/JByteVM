#include "internal.h"

int jbv_same_package(JbvClass *a, JbvClass *b) {
    uint32_t i, na = 0, nb = 0;
    for (i = 0; i < a->name.size; ++i) if (a->name.data[i] == '/') na = i+1;
    for (i = 0; i < b->name.size; ++i) if (b->name.data[i] == '/') nb = i+1;
    if (na != nb) return 0;
    for (i = 0; i < na; ++i) if (a->name.data[i] != b->name.data[i]) return 0;
    return 1;
}
JbvStatus jbv_class_access(JbvVM *vm, JbvClass *caller, JbvClass *target) {
    while (target->array_kind == 'L') target = target->component;
    return (target->flags & 1) || jbv_same_package(caller, target) ? JBV_OK :
        jbv_throw_named(vm, "java/lang/IllegalAccessError", 0, JBV_LINKAGE_ERROR);
}
static JbvStatus nest_host(JbvVM *vm, JbvClass *member, JbvClass **out) {
    JbvClass *host;
    uint16_t i;
    JbvStatus status;
    *out = member;
    if (!member->nest_host) return JBV_OK;
    status = jbv_class_constant(vm, member, member->nest_host, &host);
    if (status != JBV_OK) return status;
    if (jbv_same_package(member, host)) for (i = 0; i < host->nest_count; ++i) {
        uint16_t index = jbv_u16(host->nest_members + 2*i);
        if (jbv_text_eq(host->pool[host->pool[index].a].text, member->name)) { *out = host; return JBV_OK; }
    }
    return jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR);
}
JbvStatus jbv_member_access(JbvVM *vm, JbvClass *caller, JbvClass *owner, uint16_t flags, JbvClass *receiver) {
    if (flags & 1 || caller == owner) return JBV_OK;
    if (flags & 2) {
        JbvClass *a, *b;
        JbvStatus status = nest_host(vm, caller, &a);
        if (status != JBV_OK) return status;
        status = nest_host(vm, owner, &b);
        if (status != JBV_OK) return status;
        if (a == b) return JBV_OK;
    } else if (jbv_same_package(caller, owner)) return JBV_OK;
    else if ((flags & 4) && jbv_assignable(caller, owner) &&
        (!receiver || (flags & JBV_STATIC) || jbv_assignable(receiver, caller))) return JBV_OK;
    return jbv_throw_named(vm, "java/lang/IllegalAccessError", 0, JBV_LINKAGE_ERROR);
}
static int overrides(JbvClass *child, JbvMethod *method, JbvClass *base, JbvMethod *original) {
    JbvClass *c;
    if (method->flags & (2 | JBV_STATIC)) return 0;
    if (original->flags & 2) return 0;
    if (original->flags & (1 | 4) || jbv_same_package(child, base)) return 1;
    for (c = child->super; c && c != base; c = c->super) {
        JbvMethod *middle = jbv_find_method(c, original->name, original->descriptor);
        if (middle && overrides(child, method, c, middle) && overrides(c, middle, base, original)) return 1;
    }
    return 0;
}
JbvMethod *jbv_virtual_method(JbvClass **owner, JbvClass *resolved, JbvMethod *method) {
    JbvClass *c;
    for (c = *owner; c; c = c->super) {
        JbvMethod *candidate = jbv_find_method(c, method->name, method->descriptor);
        if (candidate && (c == resolved || overrides(c, candidate, resolved, method))) { *owner = c; return candidate; }
    }
    return jbv_lookup_method(owner, method->name, method->descriptor);
}

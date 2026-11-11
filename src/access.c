#include "internal.h"

int jbv_same_package(JbvClass *a, JbvClass *b) {
    uint32_t i, na = 0, nb = 0;
    for (i = 0; i < a->name.size; ++i) if (a->name.data[i] == '/') na = i+1;
    for (i = 0; i < b->name.size; ++i) if (b->name.data[i] == '/') nb = i+1;
    if (na != nb) return 0;
    for (i = 0; i < na; ++i) if (a->name.data[i] != b->name.data[i]) return 0;
    return 1;
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

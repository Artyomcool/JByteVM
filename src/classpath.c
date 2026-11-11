#include "classpath.h"
#include "jar.h"

enum { H_PRIMITIVE,H_COPY,H_ARRAY,H_HASH,H_CLOCK,H_WRITE,H_COLLECT,H_FBITS,H_FVALUE,H_DBITS,H_DVALUE,H_PARSE,H_SQRT,H_ROUND };
static const char *const hooks[] = {"primitive","arraycopy","newArrayLike","identityHash","clock","write","collect",
    "floatBits","bitsFloat","doubleBits","bitsDouble","parseFP","sqrt","roundIntegral",
    "callerClass","methodTypeClass","findHandle","invokeHandle","staticFinal","wrapperClass","explicitCast","enumValue","captureStackTrace"};

static JbvStatus arraycopy(JbvVM *vm, const int32_t *a) {
    JbvObject *from, *to;
    uint32_t i, width;
    int32_t *src, *dst;
    JbvStatus status;
    if (!a[0] || !a[2]) return JBV_NULL_REFERENCE;
    status = jbv_object(vm, a[0], &from); if (status != JBV_OK) return status;
    status = jbv_object(vm, a[2], &to); if (status != JBV_OK) return status;
    if (!from->type->array_kind || from->type->array_kind != to->type->array_kind) return JBV_ARRAY_STORE;
    if (a[1] < 0 || a[3] < 0 || a[4] < 0 || (uint32_t)a[1] > from->length || (uint32_t)a[3] > to->length ||
        (uint32_t)a[4] > from->length - (uint32_t)a[1] || (uint32_t)a[4] > to->length - (uint32_t)a[3]) return JBV_ARRAY_BOUNDS;
    if (from->type->array_kind == 'C') {
        uint16_t *s = jbv_chars(from) + a[1], *d = jbv_chars(to) + a[3];
        if (from == to && a[3] > a[1]) { i = (uint32_t)a[4]; while (i--) d[i] = s[i]; }
        else for (i = 0; i < (uint32_t)a[4]; ++i) d[i] = s[i];
        return JBV_OK;
    }
    width = jbv_width(jbv_kind(from->type->array_kind));
    src = jbv_data(from) + (uint32_t)a[1] * width; dst = jbv_data(to) + (uint32_t)a[3] * width;
    if (from->type->array_kind == 'L' && !jbv_assignable(from->type->component, to->type->component)) {
        for (i = 0; i < (uint32_t)a[4]; ++i) {
            if (src[i]) {
                JbvObject *element;
                status = jbv_object(vm, src[i], &element); if (status != JBV_OK) return status;
                if (!jbv_assignable(element->type, to->type->component)) return JBV_ARRAY_STORE;
            }
            dst[i] = src[i];
        }
    } else if (from == to && a[3] > a[1]) {
        i = (uint32_t)a[4] * width; while (i--) dst[i] = src[i];
    } else for (i = 0; i < (uint32_t)a[4] * width; ++i) dst[i] = src[i];
    return JBV_OK;
}
static uint64_t integral_round(uint64_t bits, int mode) {
    uint64_t magnitude = bits & UINT64_C(0x7fffffffffffffff), sign = bits & UINT64_C(0x8000000000000000);
    int e = (int)(magnitude >> 52) - 1023;
    uint64_t mask, half, fraction, unit;
    if (e >= 52 || !magnitude) return bits;
    if (e < 0) {
        if (mode == 0) return sign ? UINT64_C(0xbff0000000000000) : 0;
        if (mode == 1) return sign ? sign : UINT64_C(0x3ff0000000000000);
        return sign | (magnitude > UINT64_C(0x3fe0000000000000) ? UINT64_C(0x3ff0000000000000) : 0);
    }
    unit = UINT64_C(1) << (52 - e); mask = unit - 1; half = unit >> 1;
    fraction = magnitude & mask; magnitude &= ~mask;
    if ((mode == 0 && sign && fraction) || (mode == 1 && !sign && fraction) ||
        (mode == 2 && (fraction > half || (fraction == half && (magnitude & unit))))) magnitude += unit;
    return sign | magnitude;
}
static JbvStatus JBV_CALL hook(JbvVM *vm, void *user, const int32_t *a, uint16_t count, uint64_t *out) {
    uint32_t op = (uint32_t)(uintptr_t)user;
    int32_t ref;
    JbvStatus status;
    (void)count; *out = 0;
    switch (op) {
    case H_PRIMITIVE:
        status = jbv_primitive_mirror(vm, (uint8_t)a[0], &ref);
        if (status == JBV_OK) *out = (uint32_t)ref;
        return status;
    case H_COPY: return arraycopy(vm, a);
    case H_ARRAY: {
        JbvObject *array;
        status = jbv_object(vm, a[0], &array);
        if (status != JBV_OK) return status;
        if (array->type->array_kind != 'L') return JBV_CLASS_CAST;
        status = jbv_new(vm, array->type, a[1], &ref);
        if (status == JBV_OK) *out = (uint32_t)ref;
        return status;
    }
    case H_HASH: *out = (uint32_t)a[0]; return JBV_OK;
    case H_CLOCK:
        if (!vm->services.clock) return JBV_NATIVE_ERROR;
        *out = (uint64_t)vm->services.clock(vm->services.user, a[0] != 0); return JBV_OK;
    case H_WRITE:
        if (!vm->services.write) return JBV_NATIVE_ERROR;
        return vm->services.write(vm, vm->services.user, a[0], a[1] != 0);
    case H_COLLECT: return jbv_collect(vm);
    case H_FBITS: case H_FVALUE: *out = (uint32_t)a[0]; return JBV_OK;
    case H_DBITS: case H_DVALUE: *out = jbv_slot_bits(a, JBV_LONG); return JBV_OK;
    case H_PARSE: return jbv_parse_fp(vm, a[0], a[1] != 0, out);
    case H_SQRT: {
        union { uint64_t bits; double value; } n;
        n.bits = jbv_slot_bits(a, JBV_DOUBLE);
#if defined(_M_IX86)
        __asm fld n.value
        __asm fsqrt
        __asm fstp n.value
#else
        return JBV_UNSUPPORTED_FEATURE;
#endif
        *out = n.bits; return JBV_OK;
    }
    case H_ROUND: *out = integral_round(jbv_slot_bits(a, JBV_DOUBLE), a[2]); return JBV_OK;
    default: return jbv_dynamic_native(vm, op-H_ROUND-1, a, out);
    }
}
static uint32_t le32(const uint8_t *p) { return p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
/* jbv/library.bin: u32 count, count x {u32 offset, u32 size, u8 length, name}, class images.
 * It is inflated once per VM on first use; parsed classes reference it in place. */
JbvStatus jbv_classpath_find(JbvVM *vm, JbvText name, const uint8_t **data, uint32_t *size) {
    const uint8_t *p;
    size_t at = 4, total;
    uint32_t count, length, k;
    if (!vm->library) {
        uint8_t *image;
        JbvStatus status = jbv_jar_read(vm, jbv_library_jar, jbv_library_jar_size, jbv_text("jbv/library"), ".bin", &image, &total);
        if (status != JBV_OK) return status == JBV_NOT_FOUND ? JBV_BAD_CLASS : status;
        vm->library = image; vm->library_size = total;
    }
    p = vm->library; total = vm->library_size;
    if (total < 4) return JBV_BAD_CLASS;
    for (count = le32(p); count--; at += 9 + length) {
        if (total - at < 9 || total - at - 9 < (length = p[at + 8])) return JBV_BAD_CLASS;
        if (length != name.size) continue;
        for (k = 0; k < length && p[at + 9 + k] == name.data[k]; ++k) {}
        if (k < length) continue;
        k = le32(p + at);
        if (k > total || le32(p + at + 4) > total - k) return JBV_BAD_CLASS;
        if (data) { *data = p + k; *size = le32(p + at + 4); }
        return JBV_OK;
    }
    return JBV_NOT_FOUND;
}
JbvStatus jbv_classpath_load(JbvVM *vm, JbvText name, JbvClass **out) {
    JbvClass *c;
    JbvStatus status;
    const uint8_t *image;
    uint32_t size, i, j;
    status = jbv_classpath_find(vm, name, &image, &size);
    if (status != JBV_OK) return status;
    c = jbv_find_class(vm, name);
    if (c) { *out = c; return jbv_link(vm, c, 0); }
    status = jbv_parse_owned(vm, (uint8_t *)image, size, &c);
    if (status != JBV_OK) return status;
    c->next = vm->classes; vm->classes = c;
    if (jbv_text_is(name, "jbv/runtime/Support"))
        for (i = 0; i < c->method_count; ++i) if (c->methods[i].flags & JBV_NATIVE) {
            for (j = 0; j < sizeof(hooks)/sizeof(hooks[0]); ++j) if (jbv_text_is(c->methods[i].name, hooks[j])) break;
            if (j == sizeof(hooks)/sizeof(hooks[0])) return JBV_LINKAGE_ERROR;
            c->methods[i].native_slots = hook; c->methods[i].native_user = (void *)(uintptr_t)j; c->methods[i].intrinsic = 4;
        }
    if (jbv_text_is(name, "jbv/runtime/Reflection"))
        for (i = 0; i < c->method_count; ++i) if (c->methods[i].flags & JBV_NATIVE) {
            static const char *const names[] = {"info","flags","invoke","field","access","array","convert","annotations"};
            for (j = 0; j < sizeof(names)/sizeof(names[0]); ++j) if (jbv_text_is(c->methods[i].name, names[j])) break;
            if (j == sizeof(names)/sizeof(names[0])) return JBV_LINKAGE_ERROR;
            c->methods[i].native_slots = jbv_reflect_native; c->methods[i].native_user = (void *)(uintptr_t)j; c->methods[i].intrinsic = 4;
        }
    *out = c; return jbv_link(vm, c, 0);
}

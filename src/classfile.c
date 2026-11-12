#include "internal.h"

/* Bounded container reader only. Code, member declarations and CP relationships
 * are supplied by a trusted producer; no bytecode verification is performed. */

#if !defined(_M_IX86)   /* classfile_x86.asm parses; this is the reference */
typedef struct Reader {
    const uint8_t *data;
    size_t size, pos;
    int bad;
} Reader;
static const uint8_t *take(Reader *r, size_t n) {
    const uint8_t *p;
    if (r->bad || n > r->size - r->pos) { r->bad = 1; return 0; }
    p = r->data + r->pos;
    r->pos += n;
    return p;
}
static uint8_t u1(Reader *r) { const uint8_t *p = take(r, 1); return p ? *p : 0; }
static uint16_t u2(Reader *r) { const uint8_t *p = take(r, 2); return p ? jbv_u16(p) : 0; }
static uint32_t u4(Reader *r) { const uint8_t *p = take(r, 4); return p ? jbv_u32(p) : 0; }
static JbvText utf(Reader *r, JbvClass *c, uint16_t index) {
    JbvConstant *p = jbv_cp(c, index, 1);
    JbvText empty = {0, 0};
    if (!p) { r->bad = 1; return empty; }
    return p->text;
}
static JbvText class_name(Reader *r, JbvClass *c, uint16_t index) {
    JbvConstant *p = jbv_cp(c, index, 7);
    JbvText empty = {0, 0};
    if (!p) { r->bad = 1; return empty; }
    return utf(r, c, p->a);
}
static Reader attribute(Reader *r, JbvClass *c, JbvText *name) {
    Reader sub;
    uint16_t index = u2(r);
    uint32_t size = u4(r);
    *name = utf(r, c, index);
    sub.data = take(r, size);
    sub.size = sub.data ? size : 0;
    sub.pos = 0;
    sub.bad = r->bad;
    return sub;
}
#else
#include "layout_check.h"
#endif
JbvStatus jbv_parse(JbvVM *vm, const void *bytes, size_t size, JbvClass **out) {
    uint8_t *image;
    size_t k;
    if (size < 10 || size > 64 * 1024 * 1024) return JBV_BAD_CLASS;
    image = (uint8_t *)jbv_alloc(vm, size);
    if (!image) return JBV_OUT_OF_MEMORY;
    for (k = 0; k < size; ++k) ((volatile uint8_t *)image)[k] = ((const uint8_t *)bytes)[k];
    return jbv_parse_owned(vm, image, size, out);
}
#if !defined(_M_IX86)
/* Takes ownership of image (allocated with jbv_alloc), also on failure. */
/* Length of the instruction at code[i] (trusted bytecode). */
static uint32_t op_length(const uint8_t *code, uint32_t i) {
    uint8_t op = code[i];
    uint32_t p = (i + 4) & ~3u;
    if (op == 170) return p + 12 + 4 * (uint32_t)((int32_t)jbv_u32(code + p + 8) - (int32_t)jbv_u32(code + p + 4) + 1) - i;
    if (op == 171) return p + 8 + 8 * jbv_u32(code + p + 4) - i;
    if (op == 196) return code[i + 1] == 132 ? 6 : 4;
    if (op == 16 || op == 18 || (op >= 21 && op <= 25) || (op >= 54 && op <= 58) || op == 169 || op == 188) return 2;
    if (op == 17 || op == 19 || op == 20 || op == 132 || (op >= 153 && op <= 168) || (op >= 178 && op <= 184) || op == 187 ||
        op == 189 || op == 192 || op == 193 || op == 198 || op == 199) return 3;
    return op == 197 ? 4 : op == 185 || op == 186 || op == 200 || op == 201 ? 5 : 1;
}
/* Accessor methods (run inline at the call site by the x86 core) and superinstructions:
 * the first byte of `aload_0 getfield` becomes 203, of `iinc goto` 204. Only that byte
 * changes: the C loop runs the original opcode, branches into the pair still work. */
static void prepare_code(JbvMethod *m, uint8_t *code, uint32_t size) {
    uint32_t i;
    if (!(m->flags & (JBV_STATIC | JBV_SYNCHRONIZED))) {
        if (size == 5 && code[0] == 0x2a && code[1] == 0xb4 && (code[4] == 0xac || code[4] == 0xb0)) m->accessor = 1;
        else if (size == 6 && code[0] == 0x2a && code[1] == 0x1b && code[2] == 0xb5 && code[5] == 0xb1) m->accessor = 2;
    }
    for (i = 0; i < size; ) {   /* the length first: a marker has none of its own */
        uint32_t length = op_length(code, i);
        if (code[i] == 0x2a && i + 1 < size && code[i + 1] == 0xb4) code[i] = 203;
        else if (code[i] == 0x84 && i + 3 < size && code[i + 3] == 0xa7) code[i] = 204;
        i += length;
    }
}
JbvStatus JBV_CALL jbv_parse_owned(JbvVM *vm, uint8_t *image, size_t size, JbvClass **out) {
    Reader r;
    JbvClass *c;
    JbvStatus status = JBV_BAD_CLASS;
    uint16_t minor, major, i, n;
    r.data = image; r.size = size; r.pos = 0; r.bad = 0;
    if (size < 10 || size > 64 * 1024 * 1024 || u4(&r) != 0xcafebabe) { jbv_free_image(vm, image); return JBV_BAD_CLASS; }
    minor = u2(&r); major = u2(&r);
    if (major != 69 || minor != 0) { jbv_free_image(vm, image); return JBV_UNSUPPORTED_VERSION; }
    c = (JbvClass *)jbv_alloc(vm, sizeof(*c));
    if (!c) { jbv_free_image(vm, image); return JBV_OUT_OF_MEMORY; }
    c->image = image;
    c->pool_size = u2(&r);
    if (!c->pool_size) goto fail;
    c->pool = (JbvConstant *)jbv_alloc(vm, (size_t)c->pool_size * sizeof(*c->pool));
    if (!c->pool) { status = JBV_OUT_OF_MEMORY; goto fail; }
    for (i = 1; i < c->pool_size && !r.bad; ++i) {
        JbvConstant *p = &c->pool[i];
        p->tag = u1(&r);
        switch (p->tag) {
        case 1: p->text.size = u2(&r); p->text.data = take(&r, p->text.size); break;
        case 3: case 4: p->bits = u4(&r); break;
        case 5: case 6:
            p->bits_hi = u4(&r); p->bits = u4(&r);
            if (++i >= c->pool_size) goto fail;
            break;
        case 7: case 8: case 16: case 19: case 20: p->a = u2(&r); break;
        case 9: case 10: case 11: case 12: p->a = u2(&r); p->b = u2(&r); break;
        case 15: p->a = u1(&r); p->b = u2(&r); break;
        case 17: status = JBV_UNSUPPORTED_FEATURE; goto fail; /* prepare --lower-condy */
        case 18: status = JBV_INDY_DISABLED; goto fail;
        default: goto fail;
        }
    }
    if (r.bad) goto fail;
    c->flags = u2(&r);
    if (c->flags & 0x8000) { status = JBV_UNSUPPORTED_FEATURE; goto fail; } /* module-info */
    n = u2(&r); c->name = class_name(&r, c, n);
    n = u2(&r);
    if (n) c->super_name = class_name(&r, c, n);
    if (r.bad || !c->name.size) goto fail;
    c->interface_count = u2(&r);
    c->interface_indices = take(&r, (size_t)c->interface_count * 2);
    if (r.bad) goto fail;
    c->field_count = u2(&r);
    c->fields = (JbvField *)jbv_alloc(vm, (size_t)c->field_count * sizeof(*c->fields));
    if (!c->fields) { status = JBV_OUT_OF_MEMORY; goto fail; }
    for (i = 0; i < c->field_count && !r.bad; ++i) {
        JbvField *f = &c->fields[i];
        uint16_t j, count, index;
        f->flags = u2(&r);
        index = u2(&r); f->name = utf(&r, c, index);
        index = u2(&r); f->descriptor = utf(&r, c, index);
#if JBV_PROFILE_FULL
        f->attributes = r.data + r.pos;
#endif
        count = u2(&r);
        for (j = 0; j < count && !r.bad; ++j) {
            JbvText name;
            Reader attr = attribute(&r, c, &name);
            if (jbv_text_is(name, "ConstantValue")) {
                JbvConstant *value;
                index = u2(&attr);
                if (attr.bad) goto fail;
                f->constant = index;
                if (!index || index >= c->pool_size) goto fail;
                value = &c->pool[index];
                if ((f->flags & JBV_STATIC) && value->tag != 8) {
                    f->value = jbv_i32(value->bits); f->value_hi = jbv_i32(value->bits_hi);
                }
            }
        }
    }
    c->method_count = u2(&r);
    c->methods = (JbvMethod *)jbv_alloc(vm, (size_t)c->method_count * sizeof(*c->methods));
    if (!c->methods) { status = JBV_OUT_OF_MEMORY; goto fail; }
    for (i = 0; i < c->method_count && !r.bad; ++i) {
        JbvMethod *m = &c->methods[i];
        uint16_t j, count, index;
        m->flags = u2(&r);
        index = u2(&r); m->name = utf(&r, c, index);
        index = u2(&r); m->descriptor = utf(&r, c, index);
#if JBV_PROFILE_FULL
        m->attributes = r.data + r.pos;
#endif
        count = u2(&r);
        for (j = 0; j < count && !r.bad; ++j) {
            JbvText name;
            Reader attr = attribute(&r, c, &name);
            if (jbv_text_is(name, "Code")) {
                uint32_t code_size;
                m->max_stack = u2(&attr);
                m->max_locals = u2(&attr);
                code_size = u4(&attr);
                m->code = take(&attr, code_size);
                if (!attr.bad) prepare_code(m, (uint8_t *)m->code, code_size);
                m->handlers = u2(&attr);
                m->exception_table = take(&attr, (size_t)m->handlers * 8);
                {
                    uint16_t meta_index, attrs = u2(&attr);
                    for (meta_index = 0; meta_index < attrs && !attr.bad; ++meta_index) {
                        JbvText nested;
                        Reader meta = attribute(&attr, c, &nested);
                        if (jbv_text_is(nested, "LineNumberTable")) {
                            m->line_count = u2(&meta);
                            m->lines = take(&meta, (size_t)m->line_count * 4);
                            if (meta.bad) goto fail;
                        }
                    }
                }
                if (attr.bad) goto fail;
            }
        }
    }
#if JBV_PROFILE_FULL
    c->attributes = r.data + r.pos;
#endif
    n = u2(&r);
    for (i = 0; i < n && !r.bad; ++i) {
        JbvText name;
        Reader attr = attribute(&r, c, &name);
        if (jbv_text_is(name, "SourceFile")) c->source_file = utf(&attr, c, u2(&attr));
        if (attr.bad) goto fail;
    }
    if (r.bad || r.pos != r.size) goto fail;
    for (i = 0; i < c->method_count; ++i) jbv_prepare_method(&c->methods[i]);
    *out = c;
    return JBV_OK;
fail:
    jbv_free_class(vm, c);
    return status;
}
#endif

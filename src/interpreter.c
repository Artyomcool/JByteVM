#include "internal.h"

#if !defined(_M_IX86)   /* link_x86.asm; this is the reference */
static int integral(uint8_t c) {
    return c == 'I' || c == 'B' || c == 'C' || c == 'S' || c == 'Z';
}
int jbv_descriptor_type(JbvText d, uint32_t *pos, uint32_t *width) {
    uint32_t i = *pos, arrays = 0;
    uint8_t type;
    while (i < d.size && d.data[i] == '[') { ++i; ++arrays; }
    if (i >= d.size || arrays > 255) return 0;
    type = d.data[i++];
    *width = 1;
    if (type == 'L') {
        uint32_t start = i;
        while (i < d.size && d.data[i] != ';') {
            if (d.data[i] == '[' || d.data[i] == '.' || d.data[i] == 0) return 0;
            ++i;
        }
        if (i == start || i >= d.size) return 0;
        ++i;
    } else if (type == 'J' || type == 'D' || type == 'F') {
        *width = type == 'F' || arrays ? 1u : 2u;
    } else if (!integral(type)) return 0;
    *pos = i;
    return 1;
}
JbvStatus jbv_signature(JbvText d, uint16_t *args, int *returns) {
    uint32_t i = 1, slots = 0, width;
    uint16_t count = 0;
    if (d.size < 3 || d.data[0] != '(') return JBV_BAD_CLASS;
    while (i < d.size && d.data[i] != ')') {
        if (!jbv_descriptor_type(d, &i, &width)) return JBV_BAD_CLASS;
        slots += width;
        if (slots > 255) return JBV_BAD_CLASS;
        count = (uint16_t)slots;
    }
    if (i + 1 >= d.size) return JBV_BAD_CLASS;
    ++i;
    if (d.data[i] == 'V') { *returns = 0; ++i; }
    else {
        *returns = jbv_kind(d.data[i]) + 1;
        if (!jbv_descriptor_type(d, &i, &width)) return JBV_BAD_CLASS;
    }
    if (i != d.size) return JBV_BAD_CLASS;
    *args = count;
    return JBV_OK;
}
JbvText jbv_return_type(JbvText d) {
    uint32_t i = 1, width;
    JbvText result = {0, 0};
    while (i < d.size && d.data[i] != ')')
        if (!jbv_descriptor_type(d, &i, &width)) return result;
    if (++i >= d.size) return result;
    result.data = d.data + i; result.size = (uint16_t)(d.size - i);
    return result;
}
void jbv_prepare_method(JbvMethod *m) {
    uint16_t slots = 0;
    int result = 0;
    /* User classes and VM-built metadata have trusted method descriptors. */
    (void)jbv_signature(m->descriptor, &slots, &result);
    m->argument_slots = (uint16_t)(slots + !(m->flags & JBV_STATIC));
    m->result_kind = (uint8_t)result;
    m->return_char = m->descriptor.size ? m->descriptor.data[m->descriptor.size - 1] : 'V';
}
JbvStatus jbv_arguments(JbvVM *vm, JbvClass *owner, JbvMethod *method,
    const int32_t *args, uint16_t count, uint8_t *refs, int pin) {
    uint32_t pos = 1, width, i;
    JbvStatus status = JBV_OK;
    for (i = 0; i < count;) {
        JbvText type = {0, 0};
        int receiver = i == 0 && !(method->flags & JBV_STATIC), reference;
        width = 1;
        if (!receiver) {
            uint32_t begin = pos;
            if (!jbv_descriptor_type(method->descriptor, &pos, &width)) { status = JBV_BAD_CLASS; goto fail; }
            type.data = method->descriptor.data + begin; type.size = (uint16_t)(pos - begin);
        }
        reference = receiver || jbv_reference_type(type);
        if (width > count - i) { status = JBV_BAD_CLASS; goto fail; }
        if (refs) { refs[i] = (uint8_t)reference; if (width == 2) refs[i + 1] = 0; i += width; continue; }
        if (!reference) { i += width; continue; }
        if (pin < 0) { (void)jbv_release(vm, args[i]); ++i; continue; }
        if (receiver) {
            JbvObject *object;
            status = jbv_object(vm, args[i], &object);
            if (status == JBV_OK && !jbv_assignable(object->type, owner)) status = JBV_CLASS_CAST;
        } else status = jbv_check_reference(vm, args[i], type);
        if (status != JBV_OK) goto fail;
        if (pin > 0) {
            status = jbv_retain(vm, args[i]);
            if (status != JBV_OK) goto fail;
        }
        ++i;
    }
    return JBV_OK;
fail:
    if (pin > 0) (void)jbv_arguments(vm, owner, method, args, (uint16_t)i, 0, -1);
    return status;
}
JBV_GC static JbvStatus initialize_defaults(JbvVM *vm, JbvClass *c) {
    uint16_t i;
    JbvStatus status;
    for (i = 0; i < c->interface_count; ++i) {
        status = initialize_defaults(vm, c->interfaces[i]);
        if (status != JBV_OK) return status;
    }
    for (i = 0; i < c->method_count; ++i)
        if (!(c->methods[i].flags & (JBV_STATIC | JBV_ABSTRACT | 0x0002))) return jbv_initialize(vm, c);
    return JBV_OK;
}
JbvStatus jbv_initialize(JbvVM *vm, JbvClass *c) {
    JbvMethod *clinit;
    JbvStatus status = JBV_OK;
    uint64_t ignored;
    uint16_t i;
    if (c->init_state == 1 || c->init_state == 2) return JBV_OK;
    if (c->init_state == 3) return jbv_throw_named(vm, "java/lang/NoClassDefFoundError", 0, JBV_LINKAGE_ERROR);
    status = jbv_link(vm, c, 0);
    if (status != JBV_OK) return status;
    if (vm->depth >= vm->config.max_depth) return jbv_throw_named(vm, "java/lang/StackOverflowError", 0, JBV_LIMIT_EXCEEDED);
    ++vm->depth;
    c->init_state = 1;
    status = jbv_library_initialize(vm, c);
    for (i = 0; status == JBV_OK && i < c->field_count; ++i)
        if ((c->fields[i].flags & JBV_STATIC) && c->fields[i].constant &&
            jbv_reference_type(c->fields[i].descriptor))
            status = jbv_literal(vm, c, c->fields[i].constant, &c->fields[i].value);
    if (status == JBV_OK && !(c->flags & JBV_INTERFACE) && c->super) status = jbv_initialize(vm, c->super);
    if (!(c->flags & JBV_INTERFACE))
        for (i = 0; status == JBV_OK && i < c->interface_count; ++i) status = initialize_defaults(vm, c->interfaces[i]);
    clinit = jbv_find_method(c, jbv_text("<clinit>"), jbv_text("()V"));
    if (status == JBV_OK && clinit) status = jbv_execute(vm, c, clinit, 0, 0, 0, &ignored);
    if (status != JBV_OK && vm->exception) {
        JbvObject *exception;
        JbvClass *error;
        if (jbv_object(vm, vm->exception, &exception) == JBV_OK &&
            jbv_exception_class(vm, jbv_text("java/lang/Error"), &error) == JBV_OK && !jbv_assignable(exception->type, error))
            (void)jbv_throw_named(vm, "java/lang/ExceptionInInitializerError", vm->exception, status);
    }
    c->init_state = status == JBV_OK ? 2 : 3;
    c->init_error = status;
    --vm->depth;
    return status;
}
JBV_GC static JbvStatus resolve(JbvVM *vm, JbvClass *c, uint16_t index,
    JbvClass **owner, JbvText *name, JbvText *descriptor) {
    JbvConstant *ref = &c->pool[index], *pair = &c->pool[ref->b];
    *name = c->pool[pair->a].text;
    *descriptor = c->pool[pair->b].text;
    return jbv_class_constant(vm, c, ref->a, owner);
}
/* Resolves a member reference once; the pool entry keeps the JbvLink. */
JBV_GC static JbvStatus link_member(JbvVM *vm, JbvClass *c, uint16_t index, JbvLink **out) {
    JbvConstant *entry = &c->pool[index];
    JbvClass *owner, *symbolic;
    JbvText name, descriptor;
    JbvLink *link;
    void *member = 0;
    JbvStatus status;
    if (entry->text.data) { *out = (JbvLink *)entry->text.data; return JBV_OK; }
    status = resolve(vm, c, index, &owner, &name, &descriptor);
    if (status != JBV_OK) return status;
    symbolic = owner;
    if (entry->tag == 9) {
        member = jbv_lookup_field(&owner, name, descriptor);
        if (!member) return jbv_throw_detail(vm, "java/lang/NoSuchFieldError", owner ? owner->name : name, owner ? name : descriptor, descriptor, 1, JBV_NOT_FOUND);
    }
#if JBV_PROFILE_FULL
    else if (entry->tag == 10 && jbv_text_is(symbolic->name, "java/lang/invoke/MethodHandle") &&
        (jbv_text_is(name, "invokeExact") || jbv_text_is(name, "invoke"))) member = 0;   /* signature polymorphic */
#endif
    else {
        if (!!(symbolic->flags & JBV_INTERFACE) != (entry->tag == 11))
            return jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR);
        member = jbv_lookup_method(&owner, name, descriptor);
        if (!member) return owner ? jbv_throw_detail(vm, "java/lang/NoSuchMethodError", owner->name, name, descriptor, 1, JBV_NOT_FOUND)
                                  : jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR);
    }
    link = (JbvLink *)jbv_alloc(vm, sizeof(*link));
    if (!link) return JBV_OUT_OF_MEMORY;
    link->owner = owner; link->symbolic = symbolic; link->member = member;
    if (entry->tag != 9 && member) { link->argc = ((JbvMethod *)member)->argument_slots; link->result = ((JbvMethod *)member)->result_kind; }
    if (entry->tag == 9) {
        JbvField *field = (JbvField *)member;
        link->type = field->descriptor.data[0]; link->kind = jbv_kind(link->type);
        link->fast = link->kind > JBV_REF ? 0 : field->flags & JBV_STATIC ? 2 : 1;
        link->slot = field->slot;
        link->address = &field->value;
    }
    entry->text.data = (const uint8_t *)link;
    *out = link;
    return JBV_OK;
}
int32_t jbv_narrow(int32_t value, uint8_t type) {
    uint32_t n = (uint32_t)value;
    switch (type) {
    case 'Z': return (int32_t)(n & 1);
    case 'C': return (int32_t)(n & 65535);
    case 'B': n &= 255; return n < 128 ? (int32_t)n : (int32_t)n - 256;
    case 'S': n &= 65535; return n < 32768 ? (int32_t)n : (int32_t)n - 65536;
    default: return value;
    }
}
#else
JbvStatus jbv_link_member(JbvVM *vm, JbvClass *c, uint16_t index, JbvLink **out);
#define link_member jbv_link_member
#endif
/* What the x86 core keeps per method: where it runs, plus copies of vm->handles and the
 * young region, reloaded from the VM after anything that may collect. The rest it reads
 * through vm. */
typedef struct JbvCoreState {
    const uint8_t *code;
    int32_t *locals;
    uint8_t *refs;
    uint32_t pc, sp;          /* in/out; sp counts from locals */
    uintptr_t *handles;
    const JbvConstant *pool;
    JbvVM *vm;
    JbvStatus status;         /* out: a call made by the core failed (frame synced) */
    uint8_t *nursery;         /* the young region, for the write barrier */
    size_t nursery_size;
    uint32_t reserved;
    uint64_t result;          /* out with JBV_CORE_RETURN: the returned value */
} JbvCoreState;
#define JBV_CORE_RETURN ((JbvStatus)0x52455400)   /* core.status: the method returned */
/* One running method: the core state first (the x86 core's state pointer is the
 * activation), then its frame. Class and method are the frame's; the operand stack and
 * its reference bits follow the locals. jbv_execute keeps one on the C stack; the x86
 * core builds them on its own for calls. */
typedef struct JbvActivation {
    JbvCoreState core;
    JbvFrame frame;
    /* activations the x86 core made for a call (asm_frame): */
    struct JbvActivation *caller;
    uint32_t saved;           /* vm->used_slots to restore */
    uint32_t argbase;         /* the caller's sp after the call */
    uint8_t resume;           /* operand bytes of the invoke */
    uint8_t asm_frame;        /* no C activation runs it (jbv_core_finish takes over) */
    void *ret;                /* the core's return address into its caller: a real call/ret pair, predicted */
} JbvActivation;
#if defined(_M_IX86)
/* The x86 core (src/interp_x86.asm, generated by tools/gen_interp_x86.py) runs the hot
 * bytecodes with threaded dispatch and returns at the first opcode it leaves to C.
 * Its layout constants are checked here. */
#define JBV_X86_CORE 1

#define JBV_CORE_RETURN ((JbvStatus)0x52455400)   /* core.status: the method returned */
void JBV_CALL jbv_interpret_x86(JbvCoreState *state);
#define JBV_LAYOUT(name, ok) typedef char jbv_layout_##name[(ok) ? 1 : -1]
JBV_LAYOUT(constant, sizeof(JbvConstant) == 24 && offsetof(JbvConstant, bits) == 8 && offsetof(JbvConstant, text) == 16 && offsetof(JbvText, data) == 0);
JBV_LAYOUT(link, offsetof(JbvLink, slot) == 32 && offsetof(JbvLink, kind) == 36 && offsetof(JbvLink, type) == 37 && offsetof(JbvLink, fast) == 38 &&
    offsetof(JbvLink, ready) == 39 && offsetof(JbvLink, argc) == 40 && offsetof(JbvLink, result) == 42 && offsetof(JbvLink, owner) == 0 &&
    offsetof(JbvLink, member) == 8 && offsetof(JbvLink, seen) == 12 && offsetof(JbvLink, target_owner) == 16 && offsetof(JbvLink, target) == 20);
JBV_LAYOUT(links, offsetof(JbvLink, special_owner) == 24 && offsetof(JbvLink, special) == 28 && offsetof(JbvLink, trivial) == 43 &&
    offsetof(JbvLink, address) == 44 && offsetof(JbvLink, pic_seen) == 48 && offsetof(JbvLink, pic_owner) == 60 && offsetof(JbvLink, pic_target) == 72);
JBV_LAYOUT(core2, offsetof(JbvCoreState, nursery) == 36 && offsetof(JbvCoreState, nursery_size) == 40 && offsetof(JbvVM, last_remembered) == 2012 &&
    offsetof(JbvVM, object_class) == 360 && offsetof(JbvMethod, return_char) == (JBV_PROFILE_FULL ? 50 : 46));
JBV_LAYOUT(activation, sizeof(JbvCoreState) == 56 && offsetof(JbvActivation, frame) == 56 && offsetof(JbvActivation, caller) == 88 &&
    offsetof(JbvActivation, saved) == 92 && offsetof(JbvActivation, argbase) == 96 && offsetof(JbvActivation, resume) == 100 &&
    offsetof(JbvActivation, asm_frame) == 101 && offsetof(JbvActivation, ret) == 104 && sizeof(JbvActivation) == 112 && offsetof(JbvMethod, max_locals) == 4 &&
    JBV_NATIVE == 0x100 && JBV_SYNCHRONIZED == 0x20);
JBV_LAYOUT(vm, offsetof(JbvVM, config.max_slots) == 12 && offsetof(JbvVM, config.max_depth) == 16 && offsetof(JbvVM, slots) == 336 &&
    offsetof(JbvVM, used_slots) == 340 && offsetof(JbvVM, depth) == 344 && offsetof(JbvVM, remaining) == 352 &&
    offsetof(JbvVM, slot_refs) == 364 && offsetof(JbvVM, frames) == 368);
JBV_LAYOUT(vm_alloc, offsetof(JbvVM, nursery) == 1984 && offsetof(JbvVM, nursery_top) == 1988 && offsetof(JbvVM, nursery_size) == 1992 &&
    offsetof(JbvVM, heap_bytes) == 2036 && offsetof(JbvVM, heap_limit) == 2040 && offsetof(JbvVM, handle_cursor) == 396 &&
    offsetof(JbvVM, generations) == 380 && offsetof(JbvVM, object_count) == 400 && offsetof(JbvVM, handles) == 376 &&
    offsetof(JbvVM, handle_capacity) == 392 && offsetof(JbvVM, used) == 2108 && offsetof(JbvVM, young) == 2112);
JBV_LAYOUT(method, offsetof(JbvMethod, max_stack) == 2 && offsetof(JbvMethod, descriptor) == 16 && offsetof(JbvText, size) == 4 &&
    offsetof(JbvMethod, code) == (JBV_PROFILE_FULL ? 28 : 24) && offsetof(JbvMethod, argument_slots) == (JBV_PROFILE_FULL ? 36 : 32) &&
    offsetof(JbvMethod, result_kind) == (JBV_PROFILE_FULL ? 38 : 34) && offsetof(JbvClass, pool) == 8 && offsetof(JbvFrame, base) == 20 &&
    offsetof(JbvFrame, previous) == 0 && offsetof(JbvFrame, owner) == 4 && offsetof(JbvFrame, method) == 8 && offsetof(JbvFrame, has_monitors) == 28 &&
    sizeof(JbvFrame) == 32);
JBV_LAYOUT(klass, offsetof(JbvClass, component) == (JBV_PROFILE_FULL ? 72 : 68) && offsetof(JbvClass, flags) == (JBV_PROFILE_FULL ? 56 : 52) &&
    offsetof(JbvClass, init_state) == (JBV_PROFILE_FULL ? 82 : 78) && offsetof(JbvClass, array_kind) == (JBV_PROFILE_FULL ? 81 : 77) && JBV_INTERFACE == 0x200 && JBV_ABSTRACT == 0x400);
JBV_LAYOUT(frame, offsetof(JbvFrame, pc) == 12 && offsetof(JbvFrame, sp) == 16 && offsetof(JbvFrame, locals) == 24);
JBV_LAYOUT(core, offsetof(JbvCoreState, vm) == 28 && offsetof(JbvCoreState, status) == 32 &&
    offsetof(JbvCoreState, result) == 48 && JBV_INT + 1 == 1 && JBV_REF + 1 == 2 && JBV_LONG + 1 == 3 && JBV_DOUBLE + 1 == 6);
JBV_LAYOUT(state, offsetof(JbvCoreState, sp) == 16 && offsetof(JbvCoreState, handles) == 20 && offsetof(JbvCoreState, pool) == 24);
JBV_LAYOUT(object, sizeof(JbvObject) == 4 && JBV_HANDLE_MASK == 0xffffffu && JBV_INT == 0 && JBV_REF == 1);
#endif
/* Big-endian immediates, inline: these run at every branch and wide operand. */
#define U16(p) ((uint32_t)(p)[0] << 8 | (p)[1])
#define S16(p) ((int32_t)(int16_t)U16(p))
#define U32(p) ((uint32_t)(p)[0] << 24 | (uint32_t)(p)[1] << 16 | (uint32_t)(p)[2] << 8 | (p)[3])
typedef struct JbvOp { uint32_t pc, sp; } JbvOp;
JBV_INLINE void push_value(int32_t *stack, uint8_t *refs, uint32_t *sp, uint64_t value, uint8_t kind) {
    if (jbv_width(kind) == 2) {
        stack[*sp] = jbv_i32((uint32_t)value); refs[(*sp)++] = 0;
        stack[*sp] = jbv_i32((uint32_t)(value >> 32)); refs[(*sp)++] = 0;
    } else { stack[*sp] = jbv_i32((uint32_t)value); refs[(*sp)++] = kind == JBV_REF; }
}
#if !defined(_M_IX86)   /* slow_x86.asm; this is the reference */
/* Bytecodes off the hot path: everything that may resolve, allocate, call or
 * throw, wide and two-slot locals, long/float/double arithmetic and switches.
 * Kept out of jbv_execute so that its loop keeps pc and sp in registers. The
 * frame is synced (pc = instruction start, sp) on entry. */
JBV_GC static __declspec(noinline) JbvStatus slow_op(JbvVM *vm, JbvClass *c, JbvFrame *frame, uint8_t op, JbvOp *state,
    int32_t *stack, uint8_t *stack_refs, int32_t *locals, uint8_t *local_refs) {
    const uint8_t *code = frame->method->code;
    uint32_t pc = state->pc, sp = state->sp, start = frame->pc, index, i;
    int32_t a, b;
    JbvStatus status = JBV_OK;
#define FAIL(s) do { status = (s); goto done; } while (0)
#define PUSH_VALUE(v, k) do { push_value(stack, stack_refs, &sp, (v), (uint8_t)(k)); goto done; } while (0)
#define PUSHR(v) do { stack[sp] = (v); stack_refs[sp++] = 1; } while (0)
    switch (op) {
    case 9: case 10: PUSH_VALUE(op - 9u, JBV_LONG);
    case 11: case 12: case 13: PUSH_VALUE(op == 11 ? 0 : op == 12 ? 0x3f800000 : 0x40000000, JBV_FLOAT);
    case 14: case 15: PUSH_VALUE(op == 14 ? 0 : UINT64_C(0x3ff0000000000000), JBV_DOUBLE);
    case 18: case 19: case 20: {
        JbvConstant *p;
        int32_t literal;
        if (op == 18) index = code[pc++];
        else { index = U16(code + pc); pc += 2; }
        p = &c->pool[index];
        if (p->tag == 15 || p->tag == 16) {
            uint64_t constant;
            uint8_t kind;
            status = jbv_constant(vm, c, (uint16_t)index, &constant, &kind);
            if (status != JBV_OK) goto done;
            PUSH_VALUE(constant, kind);
        }
        if (op == 20) PUSH_VALUE(((uint64_t)p->bits_hi << 32) | p->bits, p->tag == 5 ? JBV_LONG : JBV_DOUBLE);
        if (p->tag == 3 || p->tag == 4) PUSH_VALUE((uint32_t)p->bits, p->tag == 4 ? JBV_FLOAT : JBV_INT);
        status = jbv_literal(vm, c, (uint16_t)index, &literal);
        if (status != JBV_OK) goto done;
        PUSHR(literal);
        break;
    }
    case 22: case 23: case 24:
    case 30: case 31: case 32: case 33:
    case 34: case 35: case 36: case 37: case 38: case 39: case 40: case 41:
    case 55: case 56: case 57:
    case 63: case 64: case 65: case 66:
    case 67: case 68: case 69: case 70: case 71: case 72: case 73: case 74:
    case 196: {
        uint8_t sub = op, kind;
        uint32_t width, type;
        int store;
        if (op == 196) { sub = code[pc++]; index = U16(code + pc); pc += 2; }
        else if (op >= 26 && op <= 45) { index = (op - 26u) % 4; sub = (uint8_t)(21 + (op - 26) / 4); }
        else if (op >= 59) { index = (op - 59u) % 4; sub = (uint8_t)(54 + (op - 59) / 4); }
        else index = code[pc++];
        if (sub == 132) {
            a = S16(code + pc); pc += 2;
            locals[index] = jbv_i32((uint32_t)locals[index] + (uint32_t)a);
            break;
        }
        store = sub >= 54 && sub <= 58;
        type = sub - (store ? 54u : 21u);
        kind = type == 0 ? JBV_INT : type == 1 ? JBV_LONG : type == 2 ? JBV_FLOAT : type == 3 ? JBV_DOUBLE : JBV_REF;
        width = jbv_width(kind);
        if (!store) PUSH_VALUE(jbv_slot_bits(locals + index, kind), kind);
        sp -= width;
        for (i = 0; i < width; ++i) { locals[index + i] = stack[sp + i]; local_refs[index + i] = stack_refs[sp + i]; }
        break;
    }
    case 90: case 91: case 92: case 93: case 94: {
        uint32_t copies = op >= 92 ? 2u : 1u;
        uint32_t shift = op >= 92 ? op - 92u : op - 89u;
        uint8_t ar, br = 0;
        a = stack[sp - copies]; ar = stack_refs[sp - copies];
        b = 0;
        if (copies == 2) { b = stack[sp - 1]; br = stack_refs[sp - 1]; }
        for (i = 0; i < shift; ++i) {
            stack[sp - 1 - i] = stack[sp - 1 - copies - i];
            stack_refs[sp - 1 - i] = stack_refs[sp - 1 - copies - i];
        }
        stack[sp - copies - shift] = a; stack_refs[sp - copies - shift] = ar;
        if (copies == 2) { stack[sp - 1 - shift] = b; stack_refs[sp - 1 - shift] = br; }
        stack[sp] = a; stack_refs[sp++] = ar;
        if (copies == 2) { stack[sp] = b; stack_refs[sp++] = br; }
        break;
    }
    case 97: case 98: case 99: case 101: case 102: case 103:
    case 105: case 106: case 107: case 109: case 110: case 111:
    case 113: case 114: case 115: case 117: case 118: case 119:
    case 121: case 123: case 125: case 127: case 129: case 131:
    case 133: case 134: case 135: case 136: case 137: case 138:
    case 139: case 140: case 141: case 142: case 143: case 144:
    case 148: case 149: case 150: case 151: case 152: {
        uint32_t types = jbv_numeric_types(op), wa, wb;
        uint8_t ka = (uint8_t)types, kb = (uint8_t)(types >> 8), kr = (uint8_t)(types >> 16);
        uint64_t left, right = 0, output = 0;
        wa = jbv_width(ka); wb = kb == JBV_TOP ? 0 : jbv_width(kb);
        left = jbv_slot_bits(stack + sp - wa - wb, ka);
        if (wb) { right = jbv_slot_bits(stack + sp - wb, kb); }
        status = jbv_numeric(op, left, right, &output);
        if (status != JBV_OK) goto done;
        sp -= wa + wb;
        PUSH_VALUE(output, kr);
    }
    case 170: case 171: {
        uint32_t at = (start + 4) & ~3u;
        int32_t off = jbv_i32(U32(code + at));
        a = stack[--sp];
        if (op == 170) {
            int32_t low = jbv_i32(U32(code + at + 4));
            int32_t high = jbv_i32(U32(code + at + 8));
            if (a >= low && a <= high)
                off = jbv_i32(U32(code + at + 12 + ((uint32_t)a - (uint32_t)low) * 4));
        } else {
            uint32_t lo = 0, hi = U32(code + at + 4);
            while (lo < hi) {
                uint32_t mid = lo + (hi - lo) / 2;
                b = jbv_i32(U32(code + at + 8 + mid * 8));
                if (a < b) hi = mid;
                else if (a > b) lo = mid + 1;
                else { off = jbv_i32(U32(code + at + 12 + mid * 8)); break; }
            }
        }
        if (off <= 0) { if (!vm->remaining) FAIL(JBV_LIMIT_EXCEEDED); --vm->remaining; }
        pc = start + (uint32_t)off;
        break;
    }
    case 178: case 179: case 180: case 181: {
        JbvObject *object = 0;
        JbvLink *link;
        JbvField *field;
        int32_t *location;
        int store = op == 179 || op == 181, is_static = op <= 179;
        uint32_t width;
        index = U16(code + pc); pc += 2;
        status = link_member(vm, c, (uint16_t)index, &link);
        if (status != JBV_OK) goto done;
        field = (JbvField *)link->member;
        if (!!(field->flags & JBV_STATIC) != is_static) FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
        width = jbv_width(link->kind);
        if (is_static) {
            status = jbv_initialize(vm, link->owner);
            if (status != JBV_OK) goto done;
            if (link->owner->init_state == 2) link->ready = 1;
            location = &field->value;
        } else {
            status = jbv_object(vm, stack[sp - (store ? 1u + width : 1u)], &object);
            if (status != JBV_OK) goto done;
            location = jbv_data(object) + field->slot;
        }
        if (store) {
            sp -= width;
            for (i = 0; i < width; ++i) location[i] = link->kind == JBV_INT ? jbv_narrow(stack[sp + i], link->type) : stack[sp + i];
            if (!is_static && link->kind == JBV_REF) jbv_barrier(vm, object, stack[sp]);
            if (!is_static) --sp;
            break;
        }
        if (!is_static) --sp;
        PUSH_VALUE(jbv_slot_bits(location, link->kind), link->kind);
    }
    case 182: case 183: case 184: case 185: {
        JbvClass *owner;
        JbvLink *link;
        JbvMethod *callee;
        uint16_t argc;
        int has_result;
        uint64_t returned = 0;
        uint32_t argbase;
        index = U16(code + pc); pc += 2;
        status = link_member(vm, c, (uint16_t)index, &link);
        if (status != JBV_OK) goto done;
#if JBV_PROFILE_FULL
        if (!link->member) {   /* MethodHandle.invokeExact/invoke */
            JbvConstant *pair = &c->pool[c->pool[index].b];
            JbvText name = c->pool[pair->a].text, descriptor = c->pool[pair->b].text;
            status = jbv_signature(descriptor, &argc, &has_result);
            if (status != JBV_OK) goto done;
            argbase = sp - argc - 1;
            status = jbv_polymorphic(vm, stack[argbase], descriptor, stack+argbase+1, jbv_text_is(name,"invokeExact"), &returned);
            if (status != JBV_OK) goto done;
            sp = argbase;
            if (has_result) PUSH_VALUE(returned, has_result-1);
            break;
        }
#endif
        callee = (JbvMethod *)link->member; owner = link->owner;
        if (!!(callee->flags & JBV_STATIC) != (op == 184)) FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
        argc = callee->argument_slots;
        has_result = callee->result_kind;
        if (op == 185) pc += 2;
        argbase = sp - argc;
        if (op != 184) {
            JbvObject *receiver;
            status = jbv_object(vm, stack[argbase], &receiver);
            if (status != JBV_OK) goto done;
            if (op != 183 && !link->special && (callee->flags & 0x0012 || owner->flags & 0x0010) && !(callee->flags & (JBV_STATIC | JBV_ABSTRACT))) {
                link->special = callee; link->special_owner = owner;   /* private or final: the core calls it directly */
            }
            if (op != 183 && !(callee->flags & 0x0012) && !(owner->flags & 0x0010)) {
                JbvClass *type = receiver->type;
                for (i = 0; i < 3 && link->pic_seen[i] != type; ++i) {}
                if (link->seen != type && i < 3) { owner = link->pic_owner[i]; callee = link->pic_target[i]; }
                else if (link->seen != type) {   /* inline cache miss: select and check once per class */
                    JbvClass *selected = type;
                    JbvMethod *target;
                    if (op == 185 && !jbv_assignable(type, link->symbolic))
                        FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
                    target = jbv_virtual_method(&selected, link->owner, callee);
                    if (!target) FAIL(jbv_throw_named(vm, selected ? "java/lang/AbstractMethodError" : "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
                    if (target->flags & (JBV_STATIC | JBV_ABSTRACT)) FAIL(jbv_throw_named(vm, target->flags & JBV_STATIC ? "java/lang/IncompatibleClassChangeError" : "java/lang/AbstractMethodError", 0, JBV_LINKAGE_ERROR));
                    if (!link->seen) { link->seen = type; link->target = target; link->target_owner = selected; }
                    else {   /* polymorphic: three more entries, replaced in turn */
                        i = link->pic_next++ % 3u;
                        link->pic_seen[i] = type; link->pic_owner[i] = selected; link->pic_target[i] = target;
                    }
                    owner = selected; callee = target;
                } else { owner = link->target_owner; callee = link->target; }
            } else {
                if (op == 183) {
                    if (!link->special) {   /* invokespecial: ACC_SUPER call of a superclass method, resolved once */
                        JbvClass *symbolic = link->symbolic, *selected = owner;
                        JbvMethod *target = callee;
                        if (!jbv_text_is(callee->name, "<init>") && (c->flags & 0x0020) && c != symbolic &&
                            !(symbolic->flags & JBV_INTERFACE) && jbv_assignable(c, symbolic) && c->super) {
                            selected = c->super;
                            target = jbv_lookup_method(&selected, callee->name, callee->descriptor);
                            if (!target) FAIL(jbv_throw_named(vm, selected ? "java/lang/AbstractMethodError" : "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
                        }
                        link->special = target; link->special_owner = selected; link->trivial = target->intrinsic == 1;
                    }
                    owner = link->special_owner; callee = link->special;
                }
                if (callee->flags & (JBV_STATIC | JBV_ABSTRACT)) FAIL(jbv_throw_named(vm, callee->flags & JBV_STATIC ? "java/lang/IncompatibleClassChangeError" : "java/lang/AbstractMethodError", 0, JBV_LINKAGE_ERROR));
            }
        } else {
            status = jbv_initialize(vm, owner);
            if (status == JBV_OK && owner->init_state == 2) link->ready = 1;
        }
        if (status == JBV_OK) status = jbv_execute(vm, owner, callee, stack + argbase, stack_refs + argbase, argc, &returned);
        if (status != JBV_OK) goto done;
        sp = argbase;
        if (has_result) PUSH_VALUE(returned, has_result - 1);
        break;
    }
    case 186: FAIL(JBV_INDY_DISABLED);
    case 187: case 188: case 189: {
        JbvClass *type;
        int32_t ref = 0;
        if (op == 188) {
            uint8_t kind = code[pc++];
            kind = (uint8_t)"ZCFDBSIJ"[kind - 4];
            status = jbv_array_class(vm, 0, kind, &type);
        } else {
            index = U16(code + pc); pc += 2;
            status = jbv_class_constant(vm, c, (uint16_t)index, &type);
            if (status == JBV_OK && op == 189) status = jbv_array_class(vm, type, 'L', &type);
        }
        if (status != JBV_OK) goto done;
        if (op == 187) {
            if (type->flags & (JBV_INTERFACE | JBV_ABSTRACT)) FAIL(jbv_throw_named(vm, "java/lang/InstantiationError", 0, JBV_LINKAGE_ERROR));
            status = jbv_initialize(vm, type);
            if (status == JBV_OK) status = jbv_new(vm, type, 0, &ref);
            if (status != JBV_OK) goto done;
            PUSHR(ref);
        } else {
            status = jbv_new(vm, type, stack[sp - 1], &ref);
            if (status != JBV_OK) goto done;
            stack[sp - 1] = ref; stack_refs[sp - 1] = 1;
        }
        break;
    }
    case 197: {
        JbvClass *type;
        uint8_t dimensions;
        int32_t ref = 0;
        index = U16(code + pc); pc += 2;
        dimensions = code[pc++];
        status = jbv_class_constant(vm, c, (uint16_t)index, &type);
        if (status != JBV_OK) goto done;
        for (i = 0; i < dimensions; ++i) {
            if (stack[sp - dimensions + i] < 0) FAIL(JBV_NEGATIVE_ARRAY_SIZE);
        }
        status = jbv_multi_array(vm, type, stack + sp - dimensions, dimensions, &ref);
        if (status != JBV_OK) goto done;
        sp -= dimensions;
        PUSHR(ref);
        break;
    }
    case 191:
        a = stack[sp - 1];
        if (!a) FAIL(JBV_NULL_REFERENCE);
        vm->exception = a; vm->exception_status = JBV_EXCEPTION;
        FAIL(JBV_EXCEPTION);
    case 192: case 193: {
        JbvClass *type;
        JbvObject *object;
        int matches = 0;
        index = U16(code + pc); pc += 2;
        status = jbv_class_constant(vm, c, (uint16_t)index, &type);
        if (status != JBV_OK) goto done;
        if (stack[sp - 1]) {
            status = jbv_object(vm, stack[sp - 1], &object);
            if (status != JBV_OK) goto done;
            matches = jbv_assignable(object->type, type);
        }
        if (op == 192) { if (stack[sp - 1] && !matches) FAIL(JBV_CLASS_CAST); }
        else { stack[sp - 1] = matches; stack_refs[sp - 1] = 0; }
        break;
    }
    case 194: case 195:
        status = jbv_monitor(vm, 0, stack[sp-1], op == 194 ? 1 : -1);
        if (status != JBV_OK) goto done;
        --sp; break;
    default: FAIL(JBV_UNSUPPORTED_FEATURE);
    }
done:
    state->pc = pc; state->sp = sp;
    if (status != JBV_OK) frame->sp = sp;
    return status;
#undef FAIL
#undef PUSH_VALUE
#undef PUSHR
}
#else
JbvStatus jbv_slow_op(JbvVM *vm, JbvClass *c, JbvFrame *frame, uint8_t op, JbvOp *state,
    int32_t *stack, uint8_t *stack_refs, int32_t *locals, uint8_t *local_refs);
#define slow_op jbv_slow_op
#endif
#if JBV_X86_CORE
JBV_GC static JbvStatus jbv_run(JbvVM *vm, JbvActivation *act, JbvStatus status, uint64_t *out);
static void core_state(JbvVM *vm, JbvActivation *act) {   /* core.locals and core.refs are set */
    act->core.code = act->frame.method->code;
    act->core.pc = 0; act->core.sp = act->frame.locals;
    act->core.pool = act->frame.owner->pool;
    act->core.vm = vm; act->core.status = JBV_OK;
    act->core.handles = vm->handles; act->core.nursery = vm->nursery; act->core.nursery_size = vm->nursery_size;
}
/* Unlinks an activation the core made. */
void jbv_core_leave(JbvActivation *act) {
    JbvVM *vm = act->core.vm;
    if (act->frame.has_monitors) jbv_release_monitors(vm, &act->frame);
    vm->frames = act->frame.previous; vm->used_slots = act->saved; --vm->depth;
}
/* An activation the core made needs C (an opcode it leaves to C, or a pending failure
 * in core.status): runs it to its end in C, unlinks it; the result is in core.result. */
JBV_GC JbvStatus jbv_core_finish(JbvActivation *act) {
    JbvStatus status = act->core.status;
    act->core.status = JBV_OK; act->asm_frame = 0;
    status = jbv_run(act->core.vm, act, status, &act->core.result);
    jbv_core_leave(act);
    /* the caller in the core takes the table and young region from here */
    act->core.handles = act->core.vm->handles; act->core.nursery = act->core.vm->nursery; act->core.nursery_size = act->core.vm->nursery_size;
    return status;
}
#endif
/* FP state is a fixed-size instruction-written blob; operands live on the VM heap.
 *
 * As in HotSpot's interpreter, pc and sp stay in registers. The frame gets a copy
 * (SYNC) only before what may collect, throw or run Java, the only readers of it
 * (GC roots, stack traces, handler lookup). Arguments already on the caller's
 * operand stack become the callee's first locals in place. The instruction budget
 * is charged per method entry and per backward branch, which bounds every loop
 * and recursion without a counter update at each bytecode. */
/* Runs act's method from act->core.pc until it returns (*out) or fails; a pending
 * status first unwinds to a handler in this method. The frame stays linked. */
__declspec(safebuffers)
JBV_GC static JbvStatus jbv_run(JbvVM *vm, JbvActivation *act, JbvStatus status, uint64_t *out) {
    JbvClass *c = act->frame.owner;
    JbvMethod *m = act->frame.method;
    const uint8_t *code = m->code;
    int32_t *locals = act->core.locals, *stack = locals + act->frame.locals;
    uint8_t *local_refs = act->core.refs, *stack_refs = local_refs + act->frame.locals;
    uint64_t value = 0;
    uint32_t i;
    /* pc and sp live in the core state: register copies of them would be spilled
     * around every core call by the C handlers, which are the cold path. */
#define PC act->core.pc
#define SP act->core.sp

/* SP counts from locals (the operand stack follows them); at every sync point
 * PC is just past the opcode. */
#define SYNC() (act->frame.pc = PC - 1, act->frame.sp = SP - act->frame.locals)
#define FAIL(s) do { SYNC(); status = (s); goto finish; } while (0)
/* (no &SP here: MSVC would then keep copies of SP in memory across the loop) */
#define PUSH_BITS(v, k) do { uint64_t v_ = (v); uint8_t k_ = (k);         if (jbv_width(k_) == 2) { locals[SP] = jbv_i32((uint32_t)v_); local_refs[SP++] = 0; locals[SP] = jbv_i32((uint32_t)(v_ >> 32)); local_refs[SP++] = 0; }         else { locals[SP] = jbv_i32((uint32_t)v_); local_refs[SP++] = k_ == JBV_REF; } } while (0)
#define PUSHI(v) do { locals[SP] = (v); local_refs[SP++] = 0; } while (0)
#define PUSHR(v) do { locals[SP] = (v); local_refs[SP++] = 1; } while (0)
#define JUMP(off) do { int32_t off_ = (off); \
        if (off_ <= 0) { if (!vm->remaining) FAIL(JBV_LIMIT_EXCEEDED); --vm->remaining; } \
        PC = PC - 1 + (uint32_t)off_; } while (0)
#define IF(cond) do { if (cond) JUMP(S16(code + PC)); else PC += 2; } while (0)
#define INT2(expr) do { b = locals[SP - 1]; a = locals[SP - 2]; locals[SP - 2] = (expr); --SP; } while (0)
#define ILOAD(n) do { locals[SP] = locals[n]; local_refs[SP++] = 0; } while (0)
#define ALOAD(n) do { locals[SP] = locals[n]; local_refs[SP++] = 1; } while (0)
#define ISTORE(n) do { locals[n] = locals[--SP]; local_refs[n] = 0; } while (0)
#define ASTORE(n) do { locals[n] = locals[--SP]; local_refs[n] = 1; } while (0)
/* Operand stack references come from the VM itself: a handle load, no validation. */
#define DEREF(ref) ((JbvObject *)vm->handles[(uint32_t)(ref) & JBV_HANDLE_MASK])
#define XALOAD(T, ref) do { JbvObject *array_; b = locals[SP - 2]; a = locals[SP - 1]; \
        if (!b) FAIL(JBV_NULL_REFERENCE); \
        array_ = DEREF(b); if ((uint32_t)a >= jbv_length(array_)) FAIL(JBV_ARRAY_BOUNDS); \
        --SP; locals[SP - 1] = ((const T *)(array_ + 1))[a]; local_refs[SP - 1] = (ref); } while (0)
#define XASTORE(T, value) do { JbvObject *array_; b = locals[SP - 3]; a = locals[SP - 2]; \
        if (!b) FAIL(JBV_NULL_REFERENCE); \
        array_ = DEREF(b); if ((uint32_t)a >= jbv_length(array_)) FAIL(JBV_ARRAY_BOUNDS); \
        ((T *)(array_ + 1))[a] = (T)(value); SP -= 3; } while (0)
    if (status != JBV_OK) goto finish;
resume:
    for (;;) {
#if !JBV_X86_CORE
        uint32_t index;
#endif
        uint8_t op;
        int32_t a, b;
#if JBV_X86_CORE
        /* hot bytecodes in the x86 core; it stops at the next one for this loop */
        act->core.handles = vm->handles; act->core.nursery = vm->nursery; act->core.nursery_size = vm->nursery_size;
        jbv_interpret_x86(&act->core);
        if (act->core.status != JBV_OK) {
            if (act->core.status == JBV_CORE_RETURN) { act->core.status = JBV_OK; value = act->core.result; goto finish; }
            status = act->core.status; act->core.status = JBV_OK; goto finish;
        }
#endif
        op = code[PC++];
        switch (op) {
        /* superinstruction markers (classfile.c): run the original first opcode */
        case 203: ALOAD(0); break;
        case 204: { uint32_t at = code[PC]; locals[at] = jbv_i32((uint32_t)locals[at] + (uint32_t)(int32_t)(int8_t)code[PC + 1]); PC += 2; break; }
        case 0: break; /* nop */
#if !JBV_X86_CORE   /* the x86 core runs these completely: never handed to C */
        case 1: PUSHR(0); break;
        case 2: PUSHI(-1); break;
        case 3: PUSHI(0); break;
        case 4: PUSHI(1); break;
        case 5: PUSHI(2); break;
        case 6: PUSHI(3); break;
        case 7: PUSHI(4); break;
        case 8: PUSHI(5); break;
        case 16: a = (int32_t)(int8_t)code[PC++]; PUSHI(a); break;
        case 17: a = S16(code + PC); PC += 2; PUSHI(a); break;
        case 21: index = code[PC++]; ILOAD(index); break;
        case 25: index = code[PC++]; ALOAD(index); break;
        case 26: ILOAD(0); break;
        case 27: ILOAD(1); break;
        case 28: ILOAD(2); break;
        case 29: ILOAD(3); break;
        case 42: ALOAD(0); break;
        case 43: ALOAD(1); break;
        case 44: ALOAD(2); break;
        case 45: ALOAD(3); break;
        case 54: index = code[PC++]; ISTORE(index); break;
        case 58: index = code[PC++]; ASTORE(index); break;
        case 59: ISTORE(0); break;
        case 60: ISTORE(1); break;
        case 61: ISTORE(2); break;
        case 62: ISTORE(3); break;
        case 75: ASTORE(0); break;
        case 76: ASTORE(1); break;
        case 77: ASTORE(2); break;
        case 78: ASTORE(3); break;
        case 87: --SP; break;
        case 88: SP -= 2; break;
        case 89: locals[SP] = locals[SP - 1]; local_refs[SP] = local_refs[SP - 1]; ++SP; break;
        case 95: {
            uint8_t tag;
            a = locals[SP - 1]; locals[SP - 1] = locals[SP - 2]; locals[SP - 2] = a;
            tag = local_refs[SP - 1]; local_refs[SP - 1] = local_refs[SP - 2]; local_refs[SP - 2] = tag;
            break;
        }
        /* int arithmetic: the result slot already holds an int, its reference bit stays 0 */
        case 96: INT2(jbv_i32((uint32_t)a + (uint32_t)b)); break;
        case 100: INT2(jbv_i32((uint32_t)a - (uint32_t)b)); break;
        case 104: INT2(jbv_i32((uint32_t)a * (uint32_t)b)); break;
#endif
        case 108: case 112:
            b = locals[SP - 1]; a = locals[SP - 2];
            if (!b) FAIL(JBV_DIVIDE_BY_ZERO);
            if (a == INT32_MIN && b == -1) a = op == 108 ? INT32_MIN : 0;
            else a = op == 108 ? a / b : a % b;
            locals[SP - 2] = a; --SP; break;
#if !JBV_X86_CORE   /* the x86 core runs these completely: never handed to C */
        case 120: INT2(jbv_i32((uint32_t)a << ((uint32_t)b & 31))); break;
        case 122: {
            uint32_t shift, bits;
            b = locals[SP - 1]; a = locals[SP - 2];
            shift = (uint32_t)b & 31; bits = (uint32_t)a >> shift;
            if (a < 0 && shift) bits |= UINT32_MAX << (32 - shift);
            locals[SP - 2] = jbv_i32(bits); --SP; break;
        }
        case 124: INT2(jbv_i32((uint32_t)a >> ((uint32_t)b & 31))); break;
        case 126: INT2(jbv_i32((uint32_t)a & (uint32_t)b)); break;
        case 128: INT2(jbv_i32((uint32_t)a | (uint32_t)b)); break;
        case 130: INT2(jbv_i32((uint32_t)a ^ (uint32_t)b)); break;
        case 116: locals[SP - 1] = jbv_i32(0u - (uint32_t)locals[SP - 1]); break;
        case 132:
            index = code[PC++]; a = (int32_t)(int8_t)code[PC++];
            locals[index] = jbv_i32((uint32_t)locals[index] + (uint32_t)a); break;
        case 145: case 146: case 147:
            locals[SP - 1] = jbv_narrow(locals[SP - 1], op == 145 ? 'B' : op == 146 ? 'C' : 'S'); break;
#endif
        case 153: a = locals[--SP]; IF(a == 0); break;
        case 154: a = locals[--SP]; IF(a != 0); break;
        case 155: a = locals[--SP]; IF(a < 0); break;
        case 156: a = locals[--SP]; IF(a >= 0); break;
        case 157: a = locals[--SP]; IF(a > 0); break;
        case 158: a = locals[--SP]; IF(a <= 0); break;
        case 159: case 165: b = locals[--SP]; a = locals[--SP]; IF(a == b); break;
        case 160: case 166: b = locals[--SP]; a = locals[--SP]; IF(a != b); break;
        case 161: b = locals[--SP]; a = locals[--SP]; IF(a < b); break;
        case 162: b = locals[--SP]; a = locals[--SP]; IF(a >= b); break;
        case 163: b = locals[--SP]; a = locals[--SP]; IF(a > b); break;
        case 164: b = locals[--SP]; a = locals[--SP]; IF(a <= b); break;
        case 198: a = locals[--SP]; IF(a == 0); break;
        case 199: a = locals[--SP]; IF(a != 0); break;
        case 167: JUMP(S16(code + PC)); break;
        case 200: JUMP(jbv_i32(U32(code + PC))); break;
        case 172: {
            uint8_t type = m->descriptor.data[m->descriptor.size - 1];
            value = (uint32_t)(type == 'I' ? locals[SP - 1] : jbv_narrow(locals[SP - 1], type)); goto finish;
        }
        case 173: case 174: case 175: {
            uint8_t kind = op == 173 ? JBV_LONG : op == 174 ? JBV_FLOAT : JBV_DOUBLE;
            uint32_t width = jbv_width(kind);
            value = jbv_slot_bits(locals + SP - width, kind); goto finish;
        }
        case 176:
            value = locals[SP - 1]; goto finish;
        case 177:
            value = 0; goto finish;
#if !JBV_X86_CORE   /* fast paths the x86 core takes; here they are the slow path's */
        case 18: case 19: {   /* ldc of an int/float constant */
            const JbvConstant *p = &c->pool[op == 18 ? code[PC] : U16(code + PC)];
            if (p->tag != 3 && p->tag != 4) goto slow;
            PUSHI(jbv_i32(p->bits)); PC += op == 18 ? 1u : 2u; break;
        }
        case 178: case 179: {   /* getstatic/putstatic, resolved one-slot field of an initialized class */
            const JbvLink *link = (const JbvLink *)c->pool[U16(code + PC)].text.data;
            JbvField *field;
            if (!link || link->fast != 2 || link->owner->init_state != 2) goto slow;
            field = (JbvField *)link->member;
            if (op == 178) { locals[SP] = field->value; local_refs[SP++] = link->kind; }
            else { a = locals[--SP]; field->value = link->type == 'I' || link->kind == JBV_REF ? a : jbv_narrow(a, link->type); }
            PC += 2; break;
        }
        case 184: {   /* invokestatic, resolved, class initialized */
            const JbvLink *link = (const JbvLink *)c->pool[U16(code + PC)].text.data;
            JbvMethod *callee;
            uint64_t returned;
            uint32_t argbase;
            if (!link || !link->ready) goto slow;
            callee = (JbvMethod *)link->member;
            argbase = SP - callee->argument_slots;
            SYNC();
            status = jbv_execute(vm, link->owner, callee, locals + argbase, local_refs + argbase, callee->argument_slots, &returned);
            if (status != JBV_OK) goto finish;
            SP = argbase; PC += 2;
            if (callee->result_kind) PUSH_BITS(returned, (uint8_t)(callee->result_kind - 1));
            break;
        }
        case 182: case 185: {   /* invokevirtual/invokeinterface: monomorphic cache hit */
            const JbvLink *link = (const JbvLink *)c->pool[U16(code + PC)].text.data;
            JbvMethod *callee;
            JbvObject *receiver;
            uint64_t returned;
            uint32_t argbase;
            if (!link || !link->member || !link->seen) goto slow;
            callee = (JbvMethod *)link->member;
            if (callee->flags & (0x0002 | JBV_STATIC)) goto slow;
            argbase = SP - callee->argument_slots;
            if (!locals[argbase]) goto slow;
            receiver = DEREF(locals[argbase]);
            if (receiver->type != link->seen) goto slow;
            callee = link->target;
            SYNC();
            status = jbv_execute(vm, link->target_owner, callee, locals + argbase, local_refs + argbase, callee->argument_slots, &returned);
            if (status != JBV_OK) goto finish;
            SP = argbase; PC += op == 182 ? 2u : 4u;
            if (callee->result_kind) PUSH_BITS(returned, (uint8_t)(callee->result_kind - 1));
            break;
        }
        case 180: {   /* getfield, resolved one-slot field */
            const JbvLink *link = (const JbvLink *)c->pool[U16(code + PC)].text.data;
            JbvObject *object;
            if (!link || link->fast != 1 || !locals[SP - 1]) goto slow;
            object = DEREF(locals[SP - 1]);
            locals[SP - 1] = jbv_data(object)[((const JbvField *)link->member)->slot];
            local_refs[SP - 1] = link->kind;
            PC += 2; break;
        }
        case 181: {   /* putfield, resolved one-slot field */
            const JbvLink *link = (const JbvLink *)c->pool[U16(code + PC)].text.data;
            JbvObject *object;
            if (!link || link->fast != 1 || !locals[SP - 2]) goto slow;
            object = DEREF(locals[SP - 2]);
            a = locals[SP - 1];
            if (link->kind == JBV_REF) { jbv_data(object)[((const JbvField *)link->member)->slot] = a; jbv_barrier(vm, object, a); }
            else jbv_data(object)[((const JbvField *)link->member)->slot] = link->type == 'I' ? a : jbv_narrow(a, link->type);
            SP -= 2; PC += 2; break;
        }
#endif
#if JBV_X86_CORE   /* the core runs the common array accesses: here the generic case serves all */
        case 46: case 50: case 51: case 52: case 53: case 79: case 84: case 85: case 86:
#else
        case 46: XALOAD(int32_t, 0); break;
        case 50: XALOAD(int32_t, 1); break;
        case 51: XALOAD(int8_t, 0); break;    /* boolean elements are stored as 0/1 */
        case 52: XALOAD(uint16_t, 0); break;
        case 53: XALOAD(int16_t, 0); break;
        case 79: XASTORE(int32_t, locals[SP - 1]); break;
        case 84:
            b = locals[SP - 3];
            if (b && DEREF(b)->type->array_kind == 'Z') { XASTORE(uint8_t, locals[SP - 1] & 1); }
            else { XASTORE(uint8_t, locals[SP - 1]); }
            break;
        case 85: case 86: XASTORE(uint16_t, locals[SP - 1]); break;
#endif
        case 47: case 48: case 49: case 83:
        case 80: case 81: case 82: {
            JbvObject *array;
            int store = op >= 79;
            uint8_t load = (uint8_t)(store ? op - 33 : op), kind, tag;
            uint32_t width = load == 47 || load == 49 ? 2u : 1u;
            uint32_t offset = store ? 2u + width : 2u;
            status = jbv_object(vm, locals[SP - offset], &array);
            if (status != JBV_OK) FAIL(status);
            kind = array->type->array_kind;
            a = locals[SP - offset + 1];
            if (a < 0 || (uint32_t)a >= jbv_length(array)) FAIL(JBV_ARRAY_BOUNDS);
            tag = jbv_kind(kind);
            if (store) {
                if (kind == 'L') {
                    JbvObject *element;
                    b = locals[SP - 1];
                    if (b) {
                        status = jbv_object(vm, b, &element);
                        if (status != JBV_OK) FAIL(status);
                        if (!jbv_assignable(element->type, array->type->component)) FAIL(JBV_ARRAY_STORE);
                    }
                }
                jbv_array_set(array, (uint32_t)a, kind, jbv_slot_bits(locals + SP - width, tag));
                if (kind == 'L') jbv_barrier(vm, array, locals[SP - 1]);
                SP -= offset;
            } else {
                uint64_t bits = jbv_array_get(array, (uint32_t)a, kind);
                SP -= 2;
                PUSH_BITS(bits, tag);
            }
            break;
        }
        case 190: {
            JbvObject *array;
            if (!locals[SP - 1]) FAIL(JBV_NULL_REFERENCE);
            array = DEREF(locals[SP - 1]);
            locals[SP - 1] = (int32_t)jbv_length(array); local_refs[SP - 1] = 0;
            break;
        }
        case 9: case 10: case 11: case 12: case 13: case 14: case 15: case 20: case 22: case 23: case 24: case 30: case 31: case 32: case 33: case 34: case 35: case 36: case 37: case 38: case 39: case 40: case 41: case 55: case 56: case 57: case 63: case 64: case 65: case 66: case 67: case 68: case 69: case 70: case 71: case 72: case 73: case 74: case 90: case 91: case 92: case 93: case 94: case 97: case 98: case 99: case 101: case 102: case 103: case 105: case 106: case 107: case 109: case 110: case 111: case 113: case 114: case 115: case 117: case 118: case 119: case 121: case 123: case 125: case 127: case 129: case 131: case 133: case 134: case 135: case 136: case 137: case 138: case 139: case 140: case 141: case 142: case 143: case 144: case 148: case 149: case 150: case 151: case 152: case 168: case 169: case 170: case 171: case 183: case 186: case 187: case 188: case 189: case 191: case 192: case 193: case 194: case 195: case 196: case 197: case 201: case 202: case 205: case 206: case 207: case 208: case 209: case 210: case 211: case 212: case 213: case 214: case 215: case 216: case 217: case 218: case 219: case 220: case 221: case 222: case 223: case 224: case 225: case 226: case 227: case 228: case 229: case 230: case 231: case 232: case 233: case 234: case 235: case 236: case 237: case 238: case 239: case 240: case 241: case 242: case 243: case 244: case 245: case 246: case 247: case 248: case 249: case 250: case 251: case 252: case 253: case 254: case 255:
#if JBV_X86_CORE
        case 18: case 19: case 178: case 179: case 180: case 181: case 182: case 184: case 185:
        case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8: case 16: case 17: case 21: case 25: case 26: case 27: case 28: case 29: case 42: case 43: case 44: case 45: case 54: case 58: case 59: case 60: case 61: case 62: case 75: case 76: case 77: case 78: case 87: case 88: case 89: case 95: case 96: case 100: case 104: case 120: case 122: case 124: case 126: case 128: case 130: case 116: case 132: case 145: case 146: case 147:   /* unreachable here: slow_op reports them */
#else
        slow:
#endif
        {
            JbvOp state;
            SYNC();
            state.pc = PC; state.sp = SP - act->frame.locals;
            status = slow_op(vm, c, &act->frame, op, &state, stack, stack_refs, locals, local_refs);
            PC = state.pc; SP = state.sp + act->frame.locals;
            if (status != JBV_OK) goto finish;
            break;
        }
        default: __assume(0);
        }
    }
finish:
    if (status != JBV_OK) {
        (void)jbv_raise(vm, status);
        if (vm->exception) {
            JbvObject *exception = 0;
            if (jbv_object(vm, vm->exception, &exception) == JBV_OK) {
                for (i = 0; i < m->handlers; ++i) {
                    const uint8_t *entry = m->exception_table + i * 8;
                    uint16_t catch_type = (uint16_t)U16(entry + 6);
                    JbvClass *type = 0;
                    if (act->frame.pc < U16(entry) || act->frame.pc >= U16(entry + 2)) continue;
                    if (catch_type) {
                        JbvStatus resolved = jbv_class_constant(vm, c, catch_type, &type);
                        if (resolved != JBV_OK) { status = resolved; break; }
                        if (!jbv_assignable(exception->type, type)) continue;
                    }
                    stack[0] = vm->exception; stack_refs[0] = 1; SP = act->frame.locals + 1;
                    vm->exception = 0; vm->exception_status = JBV_OK;
                    PC = U16(entry + 4); status = JBV_OK;
                    goto resume;
                }
            }
        }
    }
    if (status == JBV_OK) { vm->exception = 0; vm->exception_status = JBV_OK; *out = value; }
    return status;
#undef SYNC
#undef FAIL
#undef PC
#undef SP
#undef PUSHI
#undef PUSHR
#undef JUMP
#undef IF
#undef INT2
#undef ILOAD
#undef ALOAD
#undef ISTORE
#undef ASTORE
#undef PUSH_BITS
#undef DEREF
#undef XALOAD
#undef XASTORE
}
__declspec(safebuffers)
JbvStatus jbv_execute(JbvVM *vm, JbvClass *c, JbvMethod *m,
    const int32_t *args, const uint8_t *refs, uint16_t count, uint64_t *result) {
    uint32_t saved = vm->used_slots, base = saved, needed, i;
    int returns = m->result_kind;
    uint64_t value = 0;
    int32_t *locals = 0, *stack = 0;
    uint8_t *local_refs = 0, *stack_refs = 0;
    JbvActivation act;
    JbvFPEnv fp_state;
    int own_fp = !vm->fp_ready;
    int frame_active = 0;
    JbvStatus status = JBV_OK;
    act.frame.previous = vm->frames;
    act.frame.has_monitors = 0;
    act.frame.owner = c; act.frame.method = m; act.frame.pc = 0; act.frame.sp = 0;
    /* Bytecode calling bytecode: arguments in place on the caller's stack, VM FP state,
     * no monitor, native or intrinsic; the general entry below handles the rest. */
    if (!own_fp && args >= vm->slots && args < vm->slots + saved && refs == vm->slot_refs + (args - vm->slots) &&
        !(m->flags & (JBV_NATIVE | JBV_SYNCHRONIZED | JBV_ABSTRACT)) && !m->intrinsic) {
        base = (uint32_t)(args - vm->slots);
        needed = (uint32_t)m->max_locals + m->max_stack;
        if (vm->depth < vm->config.max_depth && needed <= vm->config.max_slots - base && vm->remaining) {
            ++vm->depth; --vm->remaining;
            act.frame.locals = m->max_locals;
            locals = vm->slots + base; stack = locals + act.frame.locals;
            local_refs = vm->slot_refs + base; stack_refs = local_refs + act.frame.locals;
            vm->used_slots = base + needed;
            for (i = count; i < act.frame.locals; ++i) ((volatile uint8_t *)local_refs)[i] = 0;
            act.frame.base = base;
            vm->frames = &act.frame; frame_active = 1;
            goto run;
        }
        base = saved;
    }
    if (m->flags & JBV_ABSTRACT)
        return JBV_UNSUPPORTED_FEATURE;
    if (vm->depth >= vm->config.max_depth) return jbv_throw_named(vm, "java/lang/StackOverflowError", 0, JBV_LIMIT_EXCEEDED);
    if (own_fp) { jbv_fp_enter(&fp_state); vm->fp_ready = 1; }
    ++vm->depth;
    act.frame.locals = (m->flags & JBV_NATIVE) ? count : m->max_locals;
    needed = act.frame.locals + ((m->flags & JBV_NATIVE) ? 0u : m->max_stack);
    if (refs && args >= vm->slots && args < vm->slots + saved && refs == vm->slot_refs + (args - vm->slots))
        base = (uint32_t)(args - vm->slots);   /* called from bytecode: arguments stay where they are */
    if (needed > vm->config.max_slots - base) { status = jbv_throw_named(vm, "java/lang/StackOverflowError", 0, JBV_LIMIT_EXCEEDED); goto done; }
    locals = vm->slots + base;
    stack = locals + act.frame.locals;
    local_refs = vm->slot_refs + base;
    stack_refs = local_refs + act.frame.locals;
    vm->used_slots = base + needed;
    if (base == saved) {
        for (i = 0; i < count; ++i) locals[i] = args[i];
        if (refs) {
            for (i = 0; i < count; ++i) local_refs[i] = refs[i];
        } else {
            status = jbv_arguments(vm, c, m, locals, count, local_refs, 0);
            if (status != JBV_OK) goto done;
        }
    }
    /* Only live stack entries are scanned; each push supplies its reference bit.
     * Uninitialized locals cannot be read by trusted bytecode. */
    for (i = count; i < act.frame.locals; ++i) ((volatile uint8_t *)local_refs)[i] = 0;
    act.frame.base = base; act.frame.previous = vm->frames;
    act.frame.has_monitors = 0;
    vm->frames = &act.frame; frame_active = 1;
    if (!vm->remaining) { status = JBV_LIMIT_EXCEEDED; goto done; }
    --vm->remaining;
    if (m->flags & JBV_SYNCHRONIZED) {
        status = jbv_monitor(vm, m->flags & JBV_STATIC ? c : 0, m->flags & JBV_STATIC ? 0 : locals[0], 1);
        if (status != JBV_OK) goto done;
    }
    if (m->intrinsic == 1) goto done; /* Object.<init>: caller checked null. */
    if (m->flags & JBV_NATIVE) {
        status = jbv_native_call(vm, m, locals, count, &value);
        if (status == JBV_OK && returns <= 1) value = returns ? (uint32_t)jbv_narrow(jbv_i32((uint32_t)value), m->descriptor.data[m->descriptor.size - 1]) : 0;
        goto done;
    }
run:
    act.core.locals = locals; act.core.refs = local_refs;
#if JBV_X86_CORE
    act.asm_frame = 0;
    core_state(vm, &act);
#else
    act.core.pc = 0; act.core.sp = act.frame.locals;
#endif
    status = jbv_run(vm, &act, JBV_OK, &value);
    goto leave;
done:
    if (status != JBV_OK) (void)jbv_raise(vm, status);
leave:
    if (status == JBV_OK) { vm->exception = 0; vm->exception_status = JBV_OK; }
    /* Host natives only: built-in ones return the declared type. */
    if (status == JBV_OK && (m->flags & JBV_NATIVE) && !m->intrinsic && returns == 2) status = jbv_check_reference(vm, jbv_i32((uint32_t)value), jbv_return_type(m->descriptor));
    if (frame_active) {
        if (act.frame.has_monitors) jbv_release_monitors(vm, &act.frame);
        vm->frames = act.frame.previous;
    }
    vm->used_slots = saved;
    --vm->depth;
    if (own_fp) { jbv_fp_restore(&fp_state); vm->fp_ready = 0; }
    if (status == JBV_OK) *result = returns && jbv_width((uint8_t)(returns - 1)) == 2 ? value : (uint32_t)value;
    return status;
}


#include "internal.h"

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
static JbvStatus initialize_defaults(JbvVM *vm, JbvClass *c) {
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
static JbvStatus resolve(JbvVM *vm, JbvClass *c, uint16_t index,
    JbvClass **owner, JbvText *name, JbvText *descriptor) {
    JbvConstant *ref = &c->pool[index], *pair = &c->pool[ref->b];
    *name = c->pool[pair->a].text;
    *descriptor = c->pool[pair->b].text;
    return jbv_class_constant(vm, c, ref->a, owner);
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
/* FP state is a fixed-size instruction-written blob; operands live on the VM heap. */
__declspec(safebuffers)
JbvStatus jbv_execute(JbvVM *vm, JbvClass *c, JbvMethod *m,
    const int32_t *args, const uint8_t *refs, uint16_t count, uint64_t *result) {
    uint32_t saved = vm->used_slots, pc = 0, sp = 0, needed, i, fault_pc = 0;
    int returns = m->result_kind;
    uint64_t value = 0;
    int32_t *locals = 0, *stack = 0;
    uint8_t *local_refs = 0, *stack_refs = 0;
    JbvFrame frame;
    JbvFPEnv fp_state;
    int own_fp = !vm->fp_ready;
    int frame_active = 0;
    const uint8_t *code = m->code;
    JbvStatus status = JBV_OK;
    frame.previous = vm->frames;
    frame.has_monitors = 0;
    frame.owner = c; frame.method = m; frame.pc = &fault_pc;
    if (m->flags & JBV_ABSTRACT)
        return JBV_UNSUPPORTED_FEATURE;
    if (vm->depth >= vm->config.max_depth) return jbv_throw_named(vm, "java/lang/StackOverflowError", 0, JBV_LIMIT_EXCEEDED);
    if (own_fp) { jbv_fp_enter(&fp_state); vm->fp_ready = 1; }
    ++vm->depth;
    frame.locals = (m->flags & JBV_NATIVE) ? count : m->max_locals;
    needed = frame.locals + ((m->flags & JBV_NATIVE) ? 0u : m->max_stack);
    if (needed > vm->config.max_slots - saved) { status = jbv_throw_named(vm, "java/lang/StackOverflowError", 0, JBV_LIMIT_EXCEEDED); goto finish; }
    locals = vm->slots + saved;
    stack = locals + frame.locals;
    local_refs = vm->slot_refs + saved;
    stack_refs = local_refs + frame.locals;
    vm->used_slots += needed;
    for (i = 0; i < count; ++i) locals[i] = args[i];
    if (refs) {
        for (i = 0; i < count; ++i) local_refs[i] = refs[i];
    } else {
        status = jbv_arguments(vm, c, m, locals, count, local_refs, 0);
        if (status != JBV_OK) goto finish;
    }
    /* Only live stack entries are scanned; each push supplies its reference bit.
     * Uninitialized locals cannot be read by trusted bytecode. */
    for (i = count; i < frame.locals; ++i) ((volatile uint8_t *)local_refs)[i] = 0;
    frame.base = saved; frame.sp = &sp; frame.previous = vm->frames;
    frame.has_monitors = 0;
    vm->frames = &frame; frame_active = 1;
    if (m->flags & JBV_SYNCHRONIZED) {
        status = jbv_monitor(vm, m->flags & JBV_STATIC ? c : 0, m->flags & JBV_STATIC ? 0 : locals[0], 1);
        if (status != JBV_OK) goto finish;
    }
    if (m->intrinsic == 1) goto finish; /* Object.<init>: caller checked null. */
    if (m->flags & JBV_NATIVE) {
        if (!vm->remaining) { status = JBV_LIMIT_EXCEEDED; goto finish; }
        --vm->remaining;
        status = jbv_native_call(vm, m, locals, count, &value);
        if (status == JBV_OK && returns <= 1) value = returns ? (uint32_t)jbv_narrow(jbv_i32((uint32_t)value), m->descriptor.data[m->descriptor.size - 1]) : 0;
        goto finish;
    }

#define FAIL(s) do { status = (s); goto finish; } while (0)
/* PUSH_KIND and PUSH_VALUE finish the current opcode through a shared tail.
 * Multi-write handlers such as dup update the reference bits explicitly. */
#define PUSH_KIND(v, r) do { a = (v); pushed_kind = (uint8_t)(r); goto push_scalar; } while (0)
#define PUSH(v) PUSH_KIND(v, 0)
/* Value-producing handlers end here; share the category-1/category-2 write
 * instead of expanding it at every field, array, numeric and call opcode. */
#define PUSH_VALUE(v, k) do { pushed = (v); pushed_kind = (uint8_t)(k); goto push_value; } while (0)
resume:
    for (;;) {
        uint32_t start = pc, index;
        uint8_t op;
        uint8_t pushed_kind;
        uint64_t pushed;
        int32_t a, b;
        fault_pc = pc;
        if (!vm->remaining) FAIL(JBV_LIMIT_EXCEEDED);
        --vm->remaining;
        op = code[pc++];
        switch (op) {
        case 0: break; /* nop */
        case 1: PUSH_KIND(0, 1); break;
        case 2: case 3: case 4: case 5: case 6: case 7: case 8: PUSH((int32_t)op - 3); break;
        case 9: case 10: PUSH_VALUE(op - 9u, JBV_LONG); break;
        case 11: case 12: case 13: PUSH_KIND(op == 11 ? 0 : op == 12 ? 0x3f800000 : 0x40000000, JBV_FLOAT); break;
        case 14: case 15: PUSH_VALUE(op == 14 ? 0 : UINT64_C(0x3ff0000000000000), JBV_DOUBLE); break;
        case 16: a = code[pc++]; PUSH(a < 128 ? a : a - 256); break;
        case 17: a = jbv_u16(code + pc); pc += 2; PUSH(a < 32768 ? a : a - 65536); break;
        case 18: case 19: case 20: {
            JbvConstant *p;
            /* Keep address-taking off the shared operand temporary a. */
            int32_t literal;
            if (op == 18) index = code[pc++];
            else { index = jbv_u16(code + pc); pc += 2; }
            p = &c->pool[index];
            if (p->tag == 15 || p->tag == 16) {
                uint64_t constant;
                uint8_t kind;
                status = jbv_constant(vm, c, (uint16_t)index, &constant, &kind);
                if (status != JBV_OK) goto finish;
                PUSH_VALUE(constant, kind);
            }
            if (op == 20) {
                PUSH_VALUE(((uint64_t)p->bits_hi << 32) | p->bits, p->tag == 5 ? JBV_LONG : JBV_DOUBLE);
                break;
            }
            if (p->tag == 3 || p->tag == 4) {
                PUSH_KIND(jbv_i32(p->bits), p->tag == 4 ? JBV_FLOAT : JBV_INT);
            }
            status = jbv_literal(vm, c, (uint16_t)index, &literal);
            if (status != JBV_OK) goto finish;
            PUSH_KIND(literal, JBV_REF);
            break;
        }
        case 21: case 25:
        case 26: case 27: case 28: case 29: case 42: case 43: case 44: case 45:
            index = op == 21 || op == 25 ? code[pc++] : op >= 42 ? op - 42 : op - 26;
            PUSH_KIND(locals[index], local_refs[index]); break;
        case 54: case 58:
        case 59: case 60: case 61: case 62: case 75: case 76: case 77: case 78:
            index = op == 54 || op == 58 ? code[pc++] : op >= 75 ? op - 75 : op - 59;
            --sp; locals[index] = stack[sp]; local_refs[index] = stack_refs[sp]; break;
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
            if (op == 196) { sub = code[pc++]; index = jbv_u16(code + pc); pc += 2; }
            else if (op >= 26 && op <= 45) { index = (op - 26u) % 4; sub = (uint8_t)(21 + (op - 26) / 4); }
            else if (op >= 59) { index = (op - 59u) % 4; sub = (uint8_t)(54 + (op - 59) / 4); }
            else index = code[pc++];
            if (sub == 132) {
                a = jbv_u16(code + pc); pc += 2; if (a >= 32768) a -= 65536;
                locals[index] = jbv_i32((uint32_t)locals[index] + (uint32_t)a);
                break;
            }
            store = sub >= 54 && sub <= 58;
            type = sub - (store ? 54u : 21u);
            kind = type == 0 ? JBV_INT : type == 1 ? JBV_LONG : type == 2 ? JBV_FLOAT : type == 3 ? JBV_DOUBLE : JBV_REF;
            width = jbv_width(kind);
            if (!store) {
                if (width == 1) { PUSH_KIND(locals[index], kind); }
                else { PUSH_VALUE(jbv_slot_bits(locals + index, kind), kind); }
            } else {
                sp -= width;
                for (i = 0; i < width; ++i) { locals[index + i] = stack[sp + i]; local_refs[index + i] = stack_refs[sp + i]; }
            }
            break;
        }
        case 87: --sp; break;
        case 88: sp -= 2; break;
        case 89: case 90: case 91: case 92: case 93: case 94: {
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
        case 95: {
            uint8_t tag;
            a = stack[sp - 1]; stack[sp - 1] = stack[sp - 2]; stack[sp - 2] = a;
            tag = stack_refs[sp - 1]; stack_refs[sp - 1] = stack_refs[sp - 2]; stack_refs[sp - 2] = tag;
            break;
        }
        case 96: case 100: case 104: case 108: case 112:
        case 120: case 122: case 124: case 126: case 128: case 130:
            b = stack[--sp]; a = stack[sp - 1];
            switch (op) {
            case 96: a = jbv_i32((uint32_t)a + (uint32_t)b); break;
            case 100: a = jbv_i32((uint32_t)a - (uint32_t)b); break;
            case 104: a = jbv_i32((uint32_t)a * (uint32_t)b); break;
            case 108: case 112:
                if (!b) FAIL(JBV_DIVIDE_BY_ZERO);
                if (a == INT32_MIN && b == -1) a = op == 108 ? INT32_MIN : 0;
                else a = op == 108 ? a / b : a % b;
                break;
            case 120: a = jbv_i32((uint32_t)a << ((uint32_t)b & 31)); break;
            case 122: {
                uint32_t shift = (uint32_t)b & 31;
                uint32_t bits = (uint32_t)a >> shift;
                if (a < 0 && shift) bits |= UINT32_MAX << (32 - shift);
                a = jbv_i32(bits); break;
            }
            case 124: a = jbv_i32((uint32_t)a >> ((uint32_t)b & 31)); break;
            case 126: a = jbv_i32((uint32_t)a & (uint32_t)b); break;
            case 128: a = jbv_i32((uint32_t)a | (uint32_t)b); break;
            case 130: a = jbv_i32((uint32_t)a ^ (uint32_t)b); break;
            }
            stack[sp - 1] = a; break;
        case 116: stack[sp - 1] = jbv_i32(0u - (uint32_t)stack[sp - 1]); break;
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
            if (status != JBV_OK) goto finish;
            sp -= wa + wb;
            PUSH_VALUE(output, kr);
            break;
        }
        case 132:
            index = code[pc++]; a = code[pc++]; if (a >= 128) a -= 256;
            locals[index] = jbv_i32((uint32_t)locals[index] + (uint32_t)a); break;
        case 145: case 146: case 147:
            stack[sp - 1] = jbv_narrow(stack[sp - 1], op == 145 ? 'B' : op == 146 ? 'C' : 'S'); break;
        case 153: case 154: case 155: case 156: case 157: case 158:
        case 159: case 160: case 161: case 162: case 163: case 164: {
            int condition;
            int32_t off = jbv_u16(code + pc); pc += 2; if (off >= 32768) off -= 65536;
            if (op >= 159) { b = stack[--sp]; a = stack[--sp]; }
            else { a = stack[--sp]; b = 0; }
            switch ((op - 153) % 6) {
            case 0: condition = a == b; break;
            case 1: condition = a != b; break;
            case 2: condition = a < b; break;
            case 3: condition = a >= b; break;
            case 4: condition = a > b; break;
            default: condition = a <= b; break;
            }
            if (condition) pc = (uint32_t)((int64_t)start + off);
            break;
        }
        case 165: case 166: case 198: case 199: {
            int condition;
            int32_t off = jbv_u16(code + pc); pc += 2; if (off >= 32768) off -= 65536;
            if (op <= 166) { b = stack[--sp]; a = stack[--sp]; condition = op == 165 ? a == b : a != b; }
            else { a = stack[--sp]; condition = op == 198 ? a == 0 : a != 0; }
            if (condition) pc = (uint32_t)((int64_t)start + off);
            break;
        }
        case 167:
            a = jbv_u16(code + pc); if (a >= 32768) a -= 65536;
            pc = (uint32_t)((int64_t)start + a); break;
        case 200: pc = (uint32_t)((int64_t)start + jbv_i32(jbv_u32(code + pc))); break;
        case 170: case 171: {
            uint32_t base = (start + 4) & ~3u;
            int32_t off = jbv_i32(jbv_u32(code + base));
            a = stack[--sp];
            if (op == 170) {
                int32_t low = jbv_i32(jbv_u32(code + base + 4));
                int32_t high = jbv_i32(jbv_u32(code + base + 8));
                if (a >= low && a <= high)
                    off = jbv_i32(jbv_u32(code + base + 12 + ((uint32_t)a - (uint32_t)low) * 4));
            } else {
                uint32_t lo = 0, hi = jbv_u32(code + base + 4);
                while (lo < hi) {
                    uint32_t mid = lo + (hi - lo) / 2;
                    b = jbv_i32(jbv_u32(code + base + 8 + mid * 8));
                    if (a < b) hi = mid;
                    else if (a > b) lo = mid + 1;
                    else { off = jbv_i32(jbv_u32(code + base + 12 + mid * 8)); break; }
                }
            }
            pc = (uint32_t)((int64_t)start + off); break;
        }
        case 172:
            value = jbv_narrow(stack[sp - 1], m->descriptor.data[m->descriptor.size - 1]); goto finish;
        case 173: case 174: case 175: {
            uint8_t kind = op == 173 ? JBV_LONG : op == 174 ? JBV_FLOAT : JBV_DOUBLE;
            uint32_t width = jbv_width(kind);
            value = jbv_slot_bits(stack + sp - width, kind); goto finish;
        }
        case 176:
            value = stack[sp - 1]; goto finish;
        case 177:
            value = 0; goto finish;
        case 178: case 179: case 180: case 181: {
            JbvObject *object = 0;
            JbvClass *owner;
            JbvText name, descriptor;
            JbvField *field;
            int32_t *location;
            int store = op == 179 || op == 181, is_static = op <= 179;
            uint8_t kind;
            uint32_t width;
            index = jbv_u16(code + pc); pc += 2;
            status = resolve(vm, c, (uint16_t)index, &owner, &name, &descriptor);
            if (status != JBV_OK) goto finish;
            field = jbv_lookup_field(&owner, name, descriptor);
            if (!field) FAIL(jbv_throw_detail(vm, "java/lang/NoSuchFieldError", owner ? owner->name : name, owner ? name : descriptor, descriptor, 1, JBV_NOT_FOUND));
            status = jbv_member_access(vm, c, owner, field->flags, 0);
            if (status != JBV_OK) goto finish;
            if (!!(field->flags & JBV_STATIC) != is_static) FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
            if (store && (field->flags & JBV_FINAL) && (owner != c || !jbv_text_is(m->name, is_static ? "<clinit>" : "<init>")))
                FAIL(jbv_throw_named(vm, "java/lang/IllegalAccessError", 0, JBV_LINKAGE_ERROR));
            kind = jbv_kind(descriptor.data[0]); width = jbv_width(kind);
            if (is_static) {
                status = jbv_initialize(vm, owner);
                if (status != JBV_OK) goto finish;
                location = &field->value;
            } else {
                uint32_t offset = store ? 1u + width : 1u;
                status = jbv_object(vm, stack[sp - offset], &object);
                if (status != JBV_OK) goto finish;
                status = jbv_member_access(vm, c, owner, field->flags, object->type);
                if (status != JBV_OK) goto finish;
                location = jbv_data(object) + field->slot;
            }
            if (store) {
                sp -= width;
                for (i = 0; i < width; ++i) location[i] = kind == JBV_INT ? jbv_narrow(stack[sp + i], descriptor.data[0]) : stack[sp + i];
                if (!is_static && kind == JBV_REF) jbv_barrier(vm, object, stack[sp]);
                if (!is_static) --sp;
            } else {
                uint64_t bits = jbv_slot_bits(location, kind);
                if (!is_static) --sp;
                PUSH_VALUE(bits, kind);
            }
            break;
        }
        case 182: case 183: case 184: case 185: {
            JbvClass *owner, *symbolic, *resolved;
            JbvText name, descriptor;
            JbvMethod *callee;
            uint16_t argc;
            int has_result;
            uint64_t returned = 0;
            uint32_t argbase;
            index = jbv_u16(code + pc); pc += 2;
            status = resolve(vm, c, (uint16_t)index, &owner, &name, &descriptor);
            if (status != JBV_OK) goto finish;
            symbolic = owner;
#if JBV_PROFILE_FULL
            if (op == 182 && jbv_text_is(symbolic->name, "java/lang/invoke/MethodHandle") &&
                (jbv_text_is(name, "invokeExact") || jbv_text_is(name, "invoke"))) {
                status = jbv_signature(descriptor, &argc, &has_result);
                if (status != JBV_OK) goto finish;
                argbase = sp - argc - 1;
                status = jbv_polymorphic(vm, stack[argbase], descriptor, stack+argbase+1, jbv_text_is(name,"invokeExact"), &returned);
                if (status != JBV_OK) goto finish;
                sp = argbase;
                if (has_result) { PUSH_VALUE(returned, has_result-1); }
                break;
            }
#endif
            if (!!(symbolic->flags & JBV_INTERFACE) != (c->pool[index].tag == 11))
                FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
            callee = jbv_lookup_method(&owner, name, descriptor);
            if (!callee) FAIL(owner ? jbv_throw_detail(vm, "java/lang/NoSuchMethodError", owner->name, name, descriptor, 1, JBV_NOT_FOUND)
                                    : jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
            resolved = owner;
            status = jbv_member_access(vm, c, owner, symbolic->array_kind && jbv_text_is(name, "clone") ? 1 : callee->flags, 0);
            if (status != JBV_OK) goto finish;
            if (!!(callee->flags & JBV_STATIC) != (op == 184)) FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
            argc = callee->argument_slots;
            has_result = callee->result_kind;
            if (op == 185) {
                pc += 2;
            }
            argbase = sp - argc;
            if (op != 184) {
                JbvObject *receiver;
                status = jbv_object(vm, stack[argbase], &receiver);
                if (status != JBV_OK) goto finish;
                if (op == 185 && !jbv_assignable(receiver->type, symbolic))
                    FAIL(jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
                status = jbv_member_access(vm, c, owner, symbolic->array_kind && jbv_text_is(name, "clone") ? 1 : callee->flags, receiver->type);
                if (status != JBV_OK) goto finish;
                if ((op == 182 || op == 185) && !(callee->flags & 0x0002)) {
                    owner = receiver->type;
                    callee = jbv_virtual_method(&owner, resolved, callee);
                } else if (op == 183 && !jbv_text_is(name, "<init>") && (c->flags & 0x0020) && c != symbolic &&
                    !(symbolic->flags & JBV_INTERFACE) && jbv_assignable(c, symbolic) && c->super) {
                    owner = c->super;
                    callee = jbv_lookup_method(&owner, name, descriptor);
                }
                if (!callee) FAIL(jbv_throw_named(vm, owner ? "java/lang/AbstractMethodError" : "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR));
                if (callee->flags & (JBV_STATIC | JBV_ABSTRACT)) FAIL(jbv_throw_named(vm, callee->flags & JBV_STATIC ? "java/lang/IncompatibleClassChangeError" : "java/lang/AbstractMethodError", 0, JBV_LINKAGE_ERROR));
                if (op == 185 && !(callee->flags & (1 | 0x0002))) FAIL(jbv_throw_named(vm, "java/lang/IllegalAccessError", 0, JBV_LINKAGE_ERROR));
            } else status = jbv_initialize(vm, owner);
            if (status == JBV_OK) status = jbv_execute(vm, owner, callee, stack + sp - argc, stack_refs + sp - argc, argc, &returned);
            if (status != JBV_OK) goto finish;
            sp -= argc;
            if (has_result) { PUSH_VALUE(returned, has_result - 1); }
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
                index = jbv_u16(code + pc); pc += 2;
                status = jbv_class_constant(vm, c, (uint16_t)index, &type);
                if (status == JBV_OK && op == 189) status = jbv_array_class(vm, type, 'L', &type);
            }
            if (status != JBV_OK) goto finish;
            if (op == 187) {
                if (type->flags & (JBV_INTERFACE | JBV_ABSTRACT)) FAIL(jbv_throw_named(vm, "java/lang/InstantiationError", 0, JBV_LINKAGE_ERROR));
                status = jbv_initialize(vm, type);
                if (status == JBV_OK) status = jbv_new(vm, type, 0, &ref);
                if (status != JBV_OK) goto finish;
                PUSH_KIND(ref, 1);
            } else {
                status = jbv_new(vm, type, stack[sp - 1], &ref);
                if (status != JBV_OK) goto finish;
                stack[sp - 1] = ref; stack_refs[sp - 1] = 1;
            }
            break;
        }
        case 197: {
            JbvClass *type;
            uint8_t dimensions;
            int32_t ref = 0;
            index = jbv_u16(code + pc); pc += 2;
            dimensions = code[pc++];
            status = jbv_class_constant(vm, c, (uint16_t)index, &type);
            if (status != JBV_OK) goto finish;
            for (i = 0; i < dimensions; ++i) {
                if (stack[sp - dimensions + i] < 0) FAIL(JBV_NEGATIVE_ARRAY_SIZE);
            }
            status = jbv_multi_array(vm, type, stack + sp - dimensions, dimensions, &ref);
            if (status != JBV_OK) goto finish;
            sp -= dimensions;
            PUSH_KIND(ref, 1);
            break;
        }
        case 46: case 47: case 48: case 49: case 50: case 51: case 52: case 53:
        case 79: case 80: case 81: case 82: case 83: case 84: case 85: case 86: {
            JbvObject *array;
            int store = op >= 79;
            uint8_t load = (uint8_t)(store ? op - 33 : op), kind, tag;
            uint32_t width = load == 47 || load == 49 ? 2u : 1u;
            uint32_t offset = store ? 2u + width : 2u;
            status = jbv_object(vm, stack[sp - offset], &array);
            if (status != JBV_OK) goto finish;
            kind = array->type->array_kind;
            a = stack[sp - offset + 1];
            if (a < 0 || (uint32_t)a >= jbv_length(array)) FAIL(JBV_ARRAY_BOUNDS);
            tag = jbv_kind(kind);
            if (store) {
                if (kind == 'L') {
                    JbvObject *element;
                    b = stack[sp - 1];
                    if (b) {
                        status = jbv_object(vm, b, &element);
                        if (status != JBV_OK) goto finish;
                        if (!jbv_assignable(element->type, array->type->component)) FAIL(JBV_ARRAY_STORE);
                    }
                }
                jbv_array_set(array, (uint32_t)a, kind, jbv_slot_bits(stack + sp - width, tag));
                if (kind == 'L') jbv_barrier(vm, array, stack[sp - 1]);
                sp -= offset;
            } else {
                uint64_t bits = jbv_array_get(array, (uint32_t)a, kind);
                sp -= 2;
                PUSH_VALUE(bits, tag);
            }
            break;
        }
        case 190: {
            JbvObject *array;
            status = jbv_object(vm, stack[sp - 1], &array);
            if (status != JBV_OK) goto finish;
            stack[sp - 1] = (int32_t)jbv_length(array); stack_refs[sp - 1] = 0;
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
            index = jbv_u16(code + pc); pc += 2;
            status = jbv_class_constant(vm, c, (uint16_t)index, &type);
            if (status != JBV_OK) goto finish;
            if (stack[sp - 1]) {
                status = jbv_object(vm, stack[sp - 1], &object);
                if (status != JBV_OK) goto finish;
                matches = jbv_assignable(object->type, type);
            }
            if (op == 192) { if (stack[sp - 1] && !matches) FAIL(JBV_CLASS_CAST); }
            else { stack[sp - 1] = matches; stack_refs[sp - 1] = 0; }
            break;
        }
        case 194: case 195:
            status = jbv_monitor(vm, 0, stack[sp-1], op == 194 ? 1 : -1);
            if (status != JBV_OK) goto finish;
            --sp; break;
        default: FAIL(JBV_UNSUPPORTED_FEATURE);
        }
        continue;
push_value:
        a = jbv_i32((uint32_t)pushed);
        if (jbv_width(pushed_kind) == 2) {
            stack[sp] = a; stack_refs[sp++] = 0; ++pushed_kind;
            a = jbv_i32((uint32_t)(pushed >> 32));
        }
push_scalar:
        stack[sp] = a; stack_refs[sp++] = pushed_kind == JBV_REF;
    }
finish:
    if (status != JBV_OK) {
        (void)jbv_raise(vm, status);
        if (vm->exception && frame_active && !(m->flags & JBV_NATIVE)) {
            JbvObject *exception = 0;
            if (jbv_object(vm, vm->exception, &exception) == JBV_OK) {
                for (i = 0; i < m->handlers; ++i) {
                    const uint8_t *entry = m->exception_table + i * 8;
                    uint16_t catch_type = jbv_u16(entry + 6);
                    JbvClass *type = 0;
                    if (fault_pc < jbv_u16(entry) || fault_pc >= jbv_u16(entry + 2)) continue;
                    if (catch_type) {
                        JbvStatus resolved = jbv_class_constant(vm, c, catch_type, &type);
                        if (resolved != JBV_OK) { status = resolved; break; }
                        if (!jbv_assignable(exception->type, type)) continue;
                    }
                    stack[0] = vm->exception; stack_refs[0] = 1; sp = 1;
                    vm->exception = 0; vm->exception_status = JBV_OK;
                    pc = jbv_u16(entry + 4); status = JBV_OK;
                    goto resume;
                }
            }
        }
    }
    if (status == JBV_OK) { vm->exception = 0; vm->exception_status = JBV_OK; }
    if (status == JBV_OK && (m->flags & JBV_NATIVE) && returns == 2) status = jbv_check_reference(vm, jbv_i32((uint32_t)value), jbv_return_type(m->descriptor));
    if (frame_active) {
        if (frame.has_monitors) jbv_release_monitors(vm, &frame);
        vm->frames = frame.previous;
    }
    vm->used_slots = saved;
    --vm->depth;
    if (own_fp) { jbv_fp_restore(&fp_state); vm->fp_ready = 0; }
    if (status == JBV_OK) *result = returns && jbv_width((uint8_t)(returns - 1)) == 2 ? value : (uint32_t)value;
    return status;
#undef FAIL
#undef PUSH
#undef PUSH_KIND
#undef PUSH_VALUE
}

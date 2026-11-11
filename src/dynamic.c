#include "library.h"
#include "classpath.h"

/* Direct Java handles. Value conversions are shared with reflection;
 * CONSTANT_Dynamic is lowered during class preparation. */
#define MH "java/lang/invoke/MethodHandle"
#define MT "java/lang/invoke/MethodType"
#define LOOKUP "java/lang/invoke/MethodHandles$Lookup"
static const char codes[] = "ZBCSIJFDV";
static const char *const wrappers[] = {"java/lang/Boolean","java/lang/Byte","java/lang/Character","java/lang/Short",
    "java/lang/Integer","java/lang/Long","java/lang/Float","java/lang/Double","java/lang/Void"};

static JbvStatus new_object(JbvVM *vm, const char *name, int32_t *ref, JbvObject **out) {
    JbvClass *type;
    JbvStatus status = jbv_resolve_class(vm, jbv_text(name), &type);
    if (status == JBV_OK) status = jbv_new(vm, type, 0, ref);
    if (status == JBV_OK) (void)jbv_object(vm, *ref, out);
    return status;
}
static JbvStatus method_type(JbvVM *vm, JbvText descriptor, int32_t *out) {
    int32_t string;
    JbvObject *o;
    JbvStatus status = jbv_string_mutf(vm, descriptor, &string);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm, string);
    status = new_object(vm, MT, out, &o);
    if (status == JBV_OK) { jbv_data(o)[0] = string; jbv_barrier_checked(vm, o, string); }
    (void)jbv_release(vm, string); return status;
}
static uint32_t class_descriptor(JbvClass *type, uint8_t *buffer) {
    uint32_t i, n = 0;
    if (type->primitive) { buffer[0] = type->primitive; return 1; }
    if (!type->array_kind) buffer[n++] = 'L';
    for (i = 0; i < type->name.size; ++i) buffer[n++] = type->name.data[i];
    if (!type->array_kind) buffer[n++] = ';';
    return n;
}
static JbvStatus make_handle(JbvVM *vm, JbvClass *caller, JbvClass *symbolic, JbvText name, JbvText descriptor, uint8_t kind, int32_t *out) {
    JbvClass *owner = symbolic;
    JbvMethod *method = 0;
    JbvField *field = 0;
    JbvObject *handle = 0;
    JbvStatus status;
    uint16_t flags;
    uint8_t *buffer;
    uint32_t n = 0, i, capacity = (uint32_t)descriptor.size + symbolic->name.size*2u + 12u;
    int32_t type_ref = 0, caller_ref = 0;
    JbvText invocation;
    if (caller) status = jbv_class_access(vm, caller, symbolic);
    else status = symbolic->flags & 1 ? JBV_OK : JBV_LINKAGE_ERROR;
    if (status != JBV_OK) return status;
    if (kind <= 4) {
        field = jbv_lookup_field(&owner, name, descriptor);
        if (!field) return jbv_throw_named(vm, "java/lang/NoSuchFieldError", 0, JBV_NOT_FOUND);
        flags = field->flags;
        if (!!(flags & JBV_STATIC) != (kind == 2 || kind == 4)) return jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR);
        if ((kind == 3 || kind == 4) && (flags & JBV_FINAL)) return jbv_throw_named(vm, "java/lang/IllegalAccessError", 0, JBV_LINKAGE_ERROR);
    } else {
        method = jbv_lookup_method(&owner, name, descriptor);
        if (!method) return jbv_throw_named(vm, "java/lang/NoSuchMethodError", 0, JBV_NOT_FOUND);
        flags = method->flags;
        if (!!(flags & JBV_STATIC) != (kind == 6)) return jbv_throw_named(vm, "java/lang/IncompatibleClassChangeError", 0, JBV_LINKAGE_ERROR);
    }
    status = caller ? jbv_member_access(vm, caller, owner, flags, 0) : flags & 1 ? JBV_OK : JBV_LINKAGE_ERROR;
    if (status != JBV_OK) return status;
    if (capacity > UINT16_MAX) return JBV_BAD_ARGUMENT;
    buffer = (uint8_t *)jbv_alloc(vm, capacity);
    if (!buffer) return JBV_OUT_OF_MEMORY;
    buffer[n++] = '(';
    if (kind == 1 || kind == 3 || kind == 5 || kind == 7 || kind == 9)
        n += class_descriptor(caller && (flags & 4) && !jbv_same_package(caller, owner) ? caller : symbolic, buffer+n);
    if (kind >= 5) {
        for (i = 1; i < descriptor.size && descriptor.data[i] != ')'; ++i) buffer[n++] = descriptor.data[i];
        buffer[n++] = ')';
        if (kind == 8) n += class_descriptor(symbolic, buffer+n);
        else while (++i < descriptor.size) buffer[n++] = descriptor.data[i];
    } else {
        if (kind == 3 || kind == 4) for (i = 0; i < descriptor.size; ++i) buffer[n++] = descriptor.data[i];
        buffer[n++] = ')';
        if (kind == 3 || kind == 4) buffer[n++] = 'V';
        else for (i = 0; i < descriptor.size; ++i) buffer[n++] = descriptor.data[i];
    }
    invocation.data = buffer; invocation.size = (uint16_t)n;
    status = method_type(vm, invocation, &type_ref);
    jbv_free(vm, buffer);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm, type_ref);
    if (caller) status = jbv_mirror(vm, caller, &caller_ref);
    if (status == JBV_OK) status = new_object(vm, MH, out, &handle);
    if (status == JBV_OK) {
        int32_t *data = jbv_data(handle);
        jbv_put_bits(data, (uint64_t)(uintptr_t)(field ? (void *)field : (void *)method), JBV_LONG);
        jbv_put_bits(data+2, (uint64_t)(uintptr_t)owner, JBV_LONG);
        data[4] = kind | (method && (flags & 0x80) ? 0x80 : 0); data[5] = type_ref; data[6] = caller_ref;
    }
    (void)jbv_release(vm, type_ref); return status;
}
static JbvStatus object_array(JbvVM *vm, JbvClass *component, uint32_t length, int32_t *ref) {
    JbvClass *type;
    JbvStatus status = jbv_array_class(vm, component, 'L', &type);
    return status == JBV_OK ? jbv_new(vm, type, (int32_t)length, ref) : status;
}
static JbvStatus handle_descriptor(JbvVM *vm, JbvObject *handle, JbvText *out) {
    JbvObject *type;
    JbvStatus status = jbv_object(vm, jbv_data(handle)[5], &type);
    return status == JBV_OK ? jbv_text_bytes(vm, jbv_data(type)[0], out) : status;
}
static JbvStatus invoke_handle(JbvVM *vm, int32_t ref, int32_t array_ref, int32_t *out, int collect) {
    JbvObject *handle, *array, *receiver = 0;
    JbvClass *owner, *caller;
    JbvMethod *method = 0;
    JbvField *field = 0;
    JbvText d = {0,0}, result_type;
    JbvStatus status;
    int32_t *slots = 0, varargs_ref = 0, receiver_ref = 0;
    uint8_t *refs = 0;
    uint32_t pos = 1, argc = 0, used = 0, width, parameters = 0, begin, i, length;
    uint8_t kind;
    uint64_t bits = 0;
    status = jbv_object(vm, ref, &handle); if (status != JBV_OK) return status;
    status = jbv_object(vm, array_ref, &array); if (status != JBV_OK) return status;
    if (!jbv_text_is(handle->type->name, MH) || array->type->array_kind != 'L') return JBV_CLASS_CAST;
    length = jbv_length(array);   /* handle and array may move once anything allocates */
    kind = (uint8_t)jbv_data(handle)[4];
    owner = (JbvClass *)(uintptr_t)jbv_slot_bits(jbv_data(handle)+2, JBV_LONG);
    caller = jbv_mirror_type(vm, jbv_data(handle)[6]);
    if ((kind&127) <= 4) field = (JbvField *)(uintptr_t)jbv_slot_bits(jbv_data(handle), JBV_LONG);
    else method = (JbvMethod *)(uintptr_t)jbv_slot_bits(jbv_data(handle), JBV_LONG);
    status = handle_descriptor(vm, handle, &d); if (status != JBV_OK) return status;
    while (d.data[pos] != ')') { if (!jbv_descriptor_type(d, &pos, &width)) { status = JBV_BAD_ARGUMENT; goto done; } ++parameters; used += width; }
    slots = (int32_t *)jbv_alloc(vm, (used+2)*sizeof(*slots)); refs = (uint8_t *)jbv_alloc(vm, used+2);
    if (!slots || !refs) { status = JBV_OUT_OF_MEMORY; goto done; }
    used = 0; pos = 1;
    if ((kind&127) == 8) {
        status = jbv_initialize(vm, owner);
        if (status == JBV_OK) status = jbv_new(vm, owner, 0, &receiver_ref);
        if (status != JBV_OK) goto done;
        (void)jbv_retain(vm, receiver_ref); slots[used] = receiver_ref; refs[used++] = 1;
    }
    for (i = 0; i < parameters; ++i) {
        JbvText type;
        int32_t argument;
        begin = pos; (void)jbv_descriptor_type(d, &pos, &width);
        type.data = d.data+begin; type.size = (uint16_t)(pos-begin);
        if (collect && (kind&128) && i+1 == parameters) {
            JbvClass *array_type;
            JbvObject *tail = 0;
            uint32_t j, remaining = length-argc;
            JbvText component = {type.data+1,(uint16_t)(type.size-1)};
            status = jbv_type_class(vm, type, &array_type);
            if (status == JBV_OK) status = jbv_new(vm, array_type, (int32_t)remaining, &varargs_ref);
            if (status != JBV_OK) goto done;
            (void)jbv_retain(vm, varargs_ref);
            for (j = 0; j < remaining; ++j) {
                (void)jbv_object(vm, array_ref, &array);
                status = jbv_from_object(vm, jbv_data(array)[argc++], component, &bits);
                if (status != JBV_OK) goto done;
                (void)jbv_object(vm, varargs_ref, &tail);
                jbv_array_set(tail, j, array_type->array_kind, bits);
                if (array_type->array_kind == 'L') jbv_barrier_checked(vm, tail, (int32_t)(uint32_t)bits);
            }
            argument = varargs_ref;
        } else {
            if (argc >= length) { status = JBV_BAD_ARGUMENT; goto wrong_type; }
            (void)jbv_object(vm, array_ref, &array); argument = jbv_data(array)[argc++];
        }
        status = jbv_from_object(vm, argument, type, &bits);
        if (status != JBV_OK) goto done;
        refs[used] = (uint8_t)jbv_reference_type(type); jbv_put_bits(slots+used, bits, jbv_kind(type.data[0])); used += width;
    }
    if (argc != length) { status = JBV_BAD_ARGUMENT; goto wrong_type; }
    kind &= 127;
    if (kind == 1 || kind == 3 || kind == 5 || kind == 7 || kind == 9) {
        JbvClass *actual;
        status = jbv_object(vm, slots[0], &receiver); if (status != JBV_OK) goto done;
        actual = receiver->type;   /* jbv_member_access may move the receiver */
        if (caller) { status = jbv_member_access(vm, caller, owner, field ? field->flags : method->flags, actual); if (status != JBV_OK) goto done; }
        if (kind == 5 || kind == 9) { method = jbv_virtual_method(&actual, owner, method); owner = actual; }
    }
    if (field) {
        int32_t *location;
        if (field->flags & JBV_STATIC) { status = jbv_initialize(vm, owner); location = &field->value; }
        else { (void)jbv_object(vm, slots[0], &receiver); location = jbv_data(receiver)+field->slot; }
        if (status != JBV_OK) goto done;
        if (kind == 1 || kind == 2) bits = jbv_slot_bits(location, jbv_kind(field->descriptor.data[0]));
        else { jbv_put_bits(location, jbv_slot_bits(slots+(kind == 3), jbv_kind(field->descriptor.data[0])), jbv_kind(field->descriptor.data[0]));
            if (receiver) jbv_barrier_checked(vm, receiver, location[0]); }
    } else {
        if (!method || (method->flags & JBV_ABSTRACT)) { status = jbv_throw_named(vm, "java/lang/AbstractMethodError", 0, JBV_LINKAGE_ERROR); goto done; }
        if (method->flags & JBV_STATIC) status = jbv_initialize(vm, owner);
        if (status == JBV_OK) status = jbv_execute(vm, owner, method, slots, refs, (uint16_t)used, &bits);
        if (status != JBV_OK) goto done;
        if (kind == 8) bits = (uint32_t)receiver_ref;
    }
    result_type = jbv_return_type(d);
    if (result_type.data[0] == 'V') *out = 0;
    else if (jbv_reference_type(result_type)) *out = (int32_t)bits;
    else status = jbv_box(vm, result_type.data[0], bits, out);
    goto done;
wrong_type:
    status = jbv_throw_named(vm, "java/lang/invoke/WrongMethodTypeException", 0, JBV_EXCEPTION);
done:
    (void)jbv_release(vm, varargs_ref); (void)jbv_release(vm, receiver_ref);
    jbv_free(vm, (void *)d.data); jbv_free(vm, slots); jbv_free(vm, refs); return status;
}

JbvStatus jbv_polymorphic(JbvVM *vm, int32_t ref, JbvText d, const int32_t *args, int exact, uint64_t *out) {
    JbvObject *handle, *array;
    JbvClass *object = jbv_find_class(vm, jbv_text("java/lang/Object"));
    JbvText target = {0,0}, result;
    uint32_t pos = 1, count = 0, width, used = 0, index = 0;
    int32_t array_ref = 0, value;
    JbvStatus status = jbv_object(vm, ref, &handle);
    if (status != JBV_OK) return status;
    if (exact) {
        status = handle_descriptor(vm, handle, &target);
        if (status != JBV_OK) return status;
        if (!jbv_text_eq(d, target)) status = jbv_throw_named(vm, "java/lang/invoke/WrongMethodTypeException", 0, JBV_EXCEPTION);
        jbv_free(vm, (void *)target.data);
        if (status != JBV_OK) return status;
    }
    while (d.data[pos] != ')') { (void)jbv_descriptor_type(d, &pos, &width); ++count; }
    status = object_array(vm, object, count, &array_ref);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm, array_ref); pos = 1;
    while (index < count) {
        uint8_t code = d.data[pos];
        (void)jbv_descriptor_type(d, &pos, &width);
        if (code == 'L' || code == '[') value = args[used];
        else { status = jbv_box(vm, code, jbv_slot_bits(args+used, jbv_kind(code)), &value); if (status != JBV_OK) goto done; }
        (void)jbv_object(vm, array_ref, &array);   /* boxing may have moved it */
        jbv_data(array)[index++] = value; jbv_barrier_checked(vm, array, value); used += width;
    }
    status = invoke_handle(vm, ref, array_ref, &value, !exact);
    if (status != JBV_OK) goto done;
    result = jbv_return_type(d);
    if (result.data[0] == 'V') *out = 0;
    /* The result is held only here; the conversion may resolve classes (and collect). */
    else { (void)jbv_retain(vm, value); status = jbv_from_object(vm, value, result, out); (void)jbv_release(vm, value); }
done:
    (void)jbv_release(vm, array_ref); return status;
}

JbvStatus jbv_constant(JbvVM *vm, JbvClass *owner, uint16_t index, uint64_t *out, uint8_t *kind) {
    JbvConstant *p = &owner->pool[index];
    JbvStatus status;
    int32_t ref = 0;
    *kind = JBV_REF;
    if (p->tag >= 3 && p->tag <= 6) {
        *out = (uint64_t)p->bits_hi<<32 | p->bits;
        *kind = p->tag == 3 ? JBV_INT : p->tag == 4 ? JBV_FLOAT : p->tag == 5 ? JBV_LONG : JBV_DOUBLE; return JBV_OK;
    }
    if (p->tag == 7 || p->tag == 8) {
        status = jbv_literal(vm, owner, index, &ref); if (status == JBV_OK) *out = (uint32_t)ref; return status;
    }
    if (p->bits) { *out = p->bits; return JBV_OK; }
    if (p->tag == 16) status = method_type(vm, owner->pool[p->a].text, &ref);
    else if (p->tag == 15) {
        JbvConstant *member = &owner->pool[p->b], *pair = &owner->pool[member->b];
        JbvClass *target;
        status = jbv_class_constant(vm, owner, member->a, &target);
        if (status == JBV_OK) status = make_handle(vm, owner, target, owner->pool[pair->a].text, owner->pool[pair->b].text, (uint8_t)p->a, &ref);
    } else return JBV_UNSUPPORTED_FEATURE;
    if (status == JBV_OK) { p->bits = (uint32_t)ref; *out = (uint32_t)ref; }
    return status;
}

JbvStatus jbv_dynamic_native(JbvVM *vm, uint32_t op, const int32_t *a, uint64_t *out) {
    JbvText name = {0,0}, descriptor = {0,0};
    JbvClass *type, *caller;
    JbvStatus status = JBV_OK;
    int32_t ref = 0;
    uint32_t pos, width, i;
    if (op == 0) {
        JbvFrame *frame = vm->frames->previous;
        int32_t skip = a[0];
        while (frame && skip-- > 0) frame = frame->previous;
        if (!frame) return JBV_BAD_ARGUMENT;
        status = jbv_mirror(vm, frame->owner, &ref);
    } else if (op == 1) {
        uint16_t args; int result;
        status = jbv_text_bytes(vm, a[0], &descriptor); if (status != JBV_OK) return status;
        if (jbv_signature(descriptor, &args, &result) != JBV_OK) { status = JBV_BAD_ARGUMENT; goto done; }
        if (a[1] == -2) {
            pos = 1;
            while (descriptor.data[pos] != ')') {
                uint32_t begin = pos; JbvText part;
                (void)jbv_descriptor_type(descriptor, &pos, &width); part.data=descriptor.data+begin; part.size=(uint16_t)(pos-begin);
                status = jbv_type_class(vm, part, &type); if (status != JBV_OK) goto done;
            }
            name = jbv_return_type(descriptor); status = jbv_type_class(vm, name, &type); name.data = 0;
        } else {
            if (a[1] == -1) name = jbv_return_type(descriptor);
            else {
                pos = 1;
                for (i = 0; i < (uint32_t)a[1] && descriptor.data[pos] != ')'; ++i) (void)jbv_descriptor_type(descriptor, &pos, &width);
                if (a[1] < 0 || descriptor.data[pos] == ')') { status = JBV_ARRAY_BOUNDS; goto done; }
                i = pos; (void)jbv_descriptor_type(descriptor, &pos, &width); name.data=descriptor.data+i; name.size=(uint16_t)(pos-i);
            }
            status = jbv_type_class(vm, name, &type); name.data=0;
            if (status == JBV_OK) status = jbv_mirror(vm, type, &ref);
        }
    } else if (op == 2) {
        caller = jbv_mirror_type(vm, a[0]); type = jbv_mirror_type(vm, a[1]); if (!type) return JBV_NULL_REFERENCE;
        status = jbv_text_bytes(vm, a[2], &name); if (status == JBV_OK) status = jbv_text_bytes(vm, a[3], &descriptor);
        if (status == JBV_OK) status = make_handle(vm, caller, type, name, descriptor, (uint8_t)a[4], &ref);
        if (status == JBV_NOT_FOUND) status = jbv_throw_named(vm, a[4] <= 4 ? "java/lang/NoSuchFieldException" : "java/lang/NoSuchMethodException", 0, JBV_EXCEPTION);
        else if (status == JBV_LINKAGE_ERROR) status = jbv_throw_named(vm, "java/lang/IllegalAccessException", 0, JBV_EXCEPTION);
    } else if (op == 3) status = invoke_handle(vm, a[0], a[1], &ref, 1);
    else if (op == 4 || op == 7) {
        JbvField *field;
        JbvClass *declaring;
        caller = op == 4 ? jbv_mirror_type(vm, a[0]) : 0;
        type = jbv_mirror_type(vm, a[op == 4 ? 1 : 0]); if (!type) return JBV_NULL_REFERENCE;
        status = jbv_text_bytes(vm, a[op == 4 ? 2 : 1], &name); if (status != JBV_OK) goto done;
        field = 0; declaring = type;
        for (; declaring; declaring = declaring->super) {
            for (i = 0; i < declaring->field_count; ++i) if (jbv_text_eq(declaring->fields[i].name, name)) { field = &declaring->fields[i]; break; }
            if (field) break;
        }
        if (!field || (field->flags & (JBV_STATIC|JBV_FINAL)) != (JBV_STATIC|JBV_FINAL)) { status = jbv_throw_named(vm, op == 7 ? "java/lang/IllegalArgumentException" : "java/lang/NoSuchFieldError", 0, JBV_EXCEPTION); goto done; }
        if (op == 7 && !(field->flags & 0x4000)) { status = JBV_BAD_ARGUMENT; goto done; }
        if (caller) { status = jbv_member_access(vm, caller, declaring, field->flags, 0); if (status != JBV_OK) goto done; }
        if (op == 4) {
            JbvClass *expected = jbv_mirror_type(vm,a[3]), *actual;
            status = jbv_type_class(vm, field->descriptor, &actual); if (status != JBV_OK) goto done;
            if (actual != expected) { status = jbv_throw_named(vm,"java/lang/NoSuchFieldError",0,JBV_EXCEPTION); goto done; }
        }
        status = jbv_initialize(vm, declaring); if (status != JBV_OK) goto done;
        if (jbv_reference_type(field->descriptor)) ref = field->value;
        else status = jbv_box(vm, field->descriptor.data[0], jbv_slot_bits(&field->value,jbv_kind(field->descriptor.data[0])), &ref);
    } else if (op == 5) {
        type = jbv_mirror_type(vm, a[0]); if (!type) return JBV_NULL_REFERENCE;
        for (i = 0; codes[i] && codes[i] != type->primitive; ++i) {}
        if (!codes[i]) return JBV_BAD_ARGUMENT;
        status = jbv_resolve_class(vm, jbv_text(wrappers[i]), &type);
        if (status == JBV_OK) status = jbv_mirror(vm, type, &ref);
    } else if (op == 6) {
        uint64_t bits;
        type = jbv_mirror_type(vm, a[0]); if (!type) return JBV_NULL_REFERENCE;
        if (type->primitive) {
            if (type->primitive == 'V') return JBV_BAD_ARGUMENT;
            status = jbv_unbox(vm, a[1], type->primitive, 1, &bits);
            if (status == JBV_OK) status = jbv_box(vm, type->primitive, bits, &ref);
        } else {
            JbvObject *value;
            if (a[1]) { status = jbv_object(vm,a[1],&value); if (status == JBV_OK && !jbv_assignable(value->type,type)) status = JBV_CLASS_CAST; }
            ref = a[1];
        }
    } else if (op == 8) status = jbv_capture_trace(vm, &ref);
    else status = JBV_UNSUPPORTED_FEATURE;
done:
    jbv_free(vm,(void *)name.data); jbv_free(vm,(void *)descriptor.data);
    if (status == JBV_OK) *out = (uint32_t)ref; return status;
}

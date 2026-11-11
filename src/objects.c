#include "internal.h"

int jbv_reference_type(JbvText descriptor) {
    return descriptor.size && (descriptor.data[0] == 'L' || descriptor.data[0] == '[');
}

JbvStatus jbv_bootstrap(JbvVM *vm) {
    uint32_t i;
    JbvClass *root = 0;
    for (i = 0; i < 4; ++i) {
        JbvClass *c = (JbvClass *)jbv_alloc(vm, sizeof(*c));
        if (!c) return JBV_OUT_OF_MEMORY;
        c->name = jbv_text(i == 0 ? "java/lang/Object" : i == 1 ? "java/lang/Cloneable" :
            i == 2 ? "java/io/Serializable" : "java/lang/AutoCloseable");
        c->flags = i == 0 ? 1 : 1 | JBV_INTERFACE | JBV_ABSTRACT;
        c->link_state = c->init_state = 2;
        c->super = root;
        c->next = vm->classes;
        vm->classes = c;
        if (!i || i == 3) {
            if (!i) root = c;
            c->methods = (JbvMethod *)jbv_alloc(vm, sizeof(*c->methods));
            if (!c->methods) return JBV_OUT_OF_MEMORY;
            c->method_count = 1;
            c->methods[0].name = jbv_text(i == 3 ? "close" : "<init>");
            c->methods[0].descriptor = jbv_text("()V");
            c->methods[0].flags = 1 | (i == 3 ? JBV_ABSTRACT : JBV_NATIVE);
            c->methods[0].intrinsic = i == 3 ? 0 : 1;
            jbv_prepare_method(&c->methods[0]);
        }
    }
    return jbv_library_object(vm, root);
}

JbvStatus jbv_array_class(JbvVM *vm, JbvClass *component, uint8_t kind, JbvClass **out) {
    JbvClass *c;
    uint8_t *name;
    uint32_t i, prefix, length;
    for (c = vm->classes; c; c = c->next)
        if (c->array_kind == kind && c->component == component) { *out = c; return JBV_OK; }
    if (kind == 'L' && !component) return JBV_BAD_CLASS;
    prefix = kind == 'L' && !component->array_kind ? 2u : 1u;
    length = kind == 'L' ? prefix + component->name.size + (prefix == 2 ? 1u : 0u) : 2u;
    if (length > UINT16_MAX) return JBV_BAD_CLASS;
    c = (JbvClass *)jbv_alloc(vm, sizeof(*c) + length);
    if (!c) return JBV_OUT_OF_MEMORY;
    name = (uint8_t *)(c + 1);
    name[0] = '[';
    if (kind == 'L') {
        if (prefix == 2) name[1] = 'L';
        for (i = 0; i < component->name.size; ++i) name[prefix + i] = component->name.data[i];
        if (prefix == 2) name[length - 1] = ';';
    } else name[1] = kind;
    c->name.data = name; c->name.size = (uint16_t)length;
    c->array_kind = kind;
    c->component = component;
    c->super = jbv_find_class(vm, jbv_text("java/lang/Object"));
    c->flags = 1 | JBV_FINAL;
    c->link_state = c->init_state = 2;
    c->next = vm->classes; vm->classes = c;
    *out = c;
    return JBV_OK;
}

JbvStatus jbv_lazy_class(JbvVM *vm, JbvText name, JbvClass **out) {
    const uint8_t *image;
    uint32_t size;
    JbvClass *c = 0;
    JbvStatus status = jbv_library_class(vm, name, out);
    if (status != JBV_NOT_FOUND || !vm->app.data) return status;
    status = jbv_archive_find(&vm->app, name, &image, &size);
    if (status == JBV_OK) status = jbv_parse_owned(vm, (uint8_t *)image, size, &c);
    if (status != JBV_OK) return status;
    if (!jbv_text_eq(c->name, name)) { jbv_free_class(vm, c); return JBV_LINKAGE_ERROR; }
    c->next = vm->classes; vm->classes = c; *out = c;
    return jbv_link(vm, c, 0);
}
JbvStatus jbv_resolve_class(JbvVM *vm, JbvText name, JbvClass **out) {
    JbvClass *c, *component;
    JbvStatus status;
    JbvText part;
    uint32_t dimensions = 0;
    if (jbv_exception_name(name)) return jbv_exception_class(vm, name, out);
    c = jbv_find_class(vm, name);
    if (c) { *out = c; return jbv_link(vm, c, 0); }
    status = jbv_lazy_class(vm, name, out);
    if (status != JBV_NOT_FOUND) return status;
    if (!name.size || name.data[0] != '[') return JBV_NOT_FOUND;
    while (dimensions < name.size && name.data[dimensions] == '[') ++dimensions;
    if (dimensions > 255 || dimensions >= name.size) return JBV_BAD_CLASS;
    if (name.size == 2) {
        uint8_t kind = name.data[1];
        if (kind != 'Z' && kind != 'B' && kind != 'C' && kind != 'S' && kind != 'I' &&
            kind != 'J' && kind != 'F' && kind != 'D') return JBV_BAD_CLASS;
        return jbv_array_class(vm, 0, kind, out);
    }
    part.data = name.data + 1; part.size = name.size - 1;
    if (part.data[0] == 'L') {
        if (part.size < 3 || part.data[part.size - 1] != ';') return JBV_BAD_CLASS;
        ++part.data; part.size -= 2;
    } else if (part.data[0] != '[') return JBV_BAD_CLASS;
    status = jbv_resolve_class(vm, part, &component);
    if (status != JBV_OK) return status;
    return jbv_array_class(vm, component, 'L', out);
}
JbvStatus jbv_class_constant(JbvVM *vm, JbvClass *c, uint16_t index, JbvClass **out) {
    JbvConstant *entry = &c->pool[index];
    JbvStatus status;
    /* Only UTF8 entries own text. A resolved Class reuses this otherwise empty
     * pointer; its bits still hold the independently cached Java Class mirror. */
    if (entry->text.data) { *out = (JbvClass *)entry->text.data; return JBV_OK; }
    status = jbv_resolve_class(vm, c->pool[entry->a].text, out);
    if (status == JBV_NOT_FOUND) { JbvText none = {0, 0}; return jbv_throw_detail(vm, "java/lang/NoClassDefFoundError", c->pool[entry->a].text, none, none, 0, status); }
    if (status == JBV_OK) status = jbv_class_access(vm, c, *out);
    if (status == JBV_OK) entry->text.data = (const uint8_t *)*out;
    return status;
}

JbvStatus jbv_link(JbvVM *vm, JbvClass *c, uint32_t depth) {
    JbvStatus status = JBV_OK;
    uint16_t i;
    if (c->link_state == 2) return JBV_OK;
    if (c->link_state == 1 || depth >= 256) return JBV_LINKAGE_ERROR;
    c->link_state = 1;
    if (!c->super_name.size) { status = JBV_LINKAGE_ERROR; goto fail; }
    c->super = jbv_find_class(vm, c->super_name);
    if (!c->super) {
        status = jbv_lazy_class(vm, c->super_name, &c->super);
        if (status != JBV_OK && status != JBV_NOT_FOUND) goto fail;
    }
    if (!c->super && jbv_exception_name(c->super_name)) {
        status = jbv_exception_class(vm, c->super_name, &c->super);
        if (status != JBV_OK) goto fail;
    }
    if (!c->super) { status = JBV_NOT_FOUND; goto fail; }
    if ((c->super->flags & (JBV_INTERFACE | JBV_FINAL)) || c->super->array_kind) {
        status = JBV_LINKAGE_ERROR; goto fail;
    }
    status = jbv_link(vm, c->super, depth + 1);
    if (status != JBV_OK) goto fail;
    status = jbv_class_access(vm, c, c->super);
    if (status != JBV_OK) goto fail;
    if (c->interface_count && !c->interfaces) {
        c->interfaces = (JbvClass **)jbv_alloc(vm, (size_t)c->interface_count * sizeof(*c->interfaces));
        if (!c->interfaces) { status = JBV_OUT_OF_MEMORY; goto fail; }
    }
    for (i = 0; i < c->interface_count; ++i) {
        JbvConstant *entry = &c->pool[jbv_u16(c->interface_indices + i * 2)];
        JbvConstant *name = &c->pool[entry->a];
        c->interfaces[i] = jbv_find_class(vm, name->text);
        if (!c->interfaces[i]) {
            status = jbv_lazy_class(vm, name->text, &c->interfaces[i]);
            if (status != JBV_OK && status != JBV_NOT_FOUND) goto fail;
        }
        if (!c->interfaces[i]) { status = JBV_NOT_FOUND; goto fail; }
        if (!(c->interfaces[i]->flags & JBV_INTERFACE)) { status = JBV_LINKAGE_ERROR; goto fail; }
        status = jbv_link(vm, c->interfaces[i], depth + 1);
        if (status != JBV_OK) goto fail;
        status = jbv_class_access(vm, c, c->interfaces[i]);
        if (status != JBV_OK) goto fail;
    }
    c->instance_slots = c->super->instance_slots;
    for (i = 0; i < c->field_count; ++i)
        if (!(c->fields[i].flags & JBV_STATIC)) {
            c->fields[i].slot = c->instance_slots;
            c->instance_slots += jbv_width(jbv_kind(c->fields[i].descriptor.data[0]));
        }
    c->link_state = 2;
    return JBV_OK;
fail:
    c->link_state = 0;
    return status;
}

int jbv_assignable(JbvClass *from, JbvClass *to) {
    uint16_t i;
    if (from == to) return 1;
    if (from->primitive || to->primitive) return 0;
    if (from->array_kind) {
        if (to->array_kind)
            return from->array_kind == 'L' && to->array_kind == 'L' && jbv_assignable(from->component, to->component);
        if (jbv_text_is(to->name, "java/lang/Cloneable") || jbv_text_is(to->name, "java/io/Serializable")) return 1;
    }
    for (i = 0; i < from->interface_count; ++i)
        if (jbv_assignable(from->interfaces[i], to)) return 1;
    return from->super ? jbv_assignable(from->super, to) : 0;
}
/* A declaration in any strict subinterface suppresses the inherited method,
 * including an abstract redeclaration. Traversal order must not choose a winner. */
static int interface_override(JbvClass *root, JbvClass *candidate, JbvText name, JbvText descriptor) {
    uint16_t i;
    JbvMethod *m;
    if (root != candidate && (root->flags & JBV_INTERFACE) && jbv_assignable(root, candidate)) {
        m = jbv_find_method(root, name, descriptor);
        if (m && !(m->flags & (JBV_STATIC | 0x0002))) return 1;
    }
    for (i = 0; i < root->interface_count; ++i)
        if (interface_override(root->interfaces[i], candidate, name, descriptor)) return 1;
    return root->super && interface_override(root->super, candidate, name, descriptor);
}
static int interface_method(JbvClass *root, JbvClass *c, JbvText name, JbvText descriptor,
    JbvClass **owner, JbvMethod **selected) {
    JbvMethod *m;
    uint16_t i;
    if (c->flags & JBV_INTERFACE) {
        m = jbv_find_method(c, name, descriptor);
        if (m && !(m->flags & (JBV_STATIC | 0x0002)) && !interface_override(root, c, name, descriptor)) {
            if (*selected && *owner != c && !((*selected)->flags & JBV_ABSTRACT) && !(m->flags & JBV_ABSTRACT)) return 0;
            if (!*selected || ((*selected)->flags & JBV_ABSTRACT)) { *selected = m; *owner = c; }
        }
    }
    for (i = 0; i < c->interface_count; ++i)
        if (!interface_method(root, c->interfaces[i], name, descriptor, owner, selected)) return 0;
    return !c->super || interface_method(root, c->super, name, descriptor, owner, selected);
}
JbvMethod *jbv_lookup_method(JbvClass **owner, JbvText name, JbvText descriptor) {
    JbvClass *root = *owner, *c;
    JbvMethod *m = jbv_find_method(root, name, descriptor), *selected = 0;
    if (m || jbv_text_is(name, "<init>")) return m;
    for (c = root->super; c; c = c->super) {
        m = jbv_find_method(c, name, descriptor);
        if (m && (!(root->flags & JBV_INTERFACE) || ((m->flags & 1) && !(m->flags & JBV_STATIC)))) {
            *owner = c; return m;
        }
    }
    if (!interface_method(root, root, name, descriptor, owner, &selected)) { *owner = 0; return 0; }
    return selected;
}
JbvField *jbv_lookup_field(JbvClass **owner, JbvText name, JbvText descriptor) {
    JbvClass *c = *owner;
    JbvField *f = jbv_find_field(c, name, descriptor);
    uint16_t i;
    if (f) return f;
    for (i = 0; i < c->interface_count; ++i) {
        JbvClass *parent = c->interfaces[i];
        f = jbv_lookup_field(&parent, name, descriptor);
        if (f) { *owner = parent; return f; }
    }
    if (c->super) {
        JbvClass *parent = c->super;
        f = jbv_lookup_field(&parent, name, descriptor);
        if (f) { *owner = parent; return f; }
    }
    return 0;
}

JbvStatus jbv_object(JbvVM *vm, int32_t ref, JbvObject **out) {
    uint32_t index = (uint32_t)ref & 65535u;
    if (!ref) return JBV_NULL_REFERENCE;
    if (ref < 0 || !index || index > vm->handle_capacity || !vm->handles[index].object ||
        vm->handles[index].generation != (uint32_t)ref >> 16) return JBV_BAD_REFERENCE;
    *out = vm->handles[index].object;
    return JBV_OK;
}
JbvStatus jbv_check_reference(JbvVM *vm, int32_t ref, JbvText descriptor) {
    JbvObject *object;
    JbvClass *type;
    JbvStatus status;
    if (!ref) return JBV_OK;
    status = jbv_object(vm, ref, &object);
    if (status != JBV_OK) return status;
    if (descriptor.size > 2 && descriptor.data[0] == 'L' && descriptor.data[descriptor.size - 1] == ';') {
        ++descriptor.data; descriptor.size -= 2;
    } else if (!descriptor.size || descriptor.data[0] != '[') return JBV_BAD_CLASS;
    status = jbv_resolve_class(vm, descriptor, &type);
    if (status != JBV_OK) return status;
    return jbv_assignable(object->type, type) ? JBV_OK : JBV_CLASS_CAST;
}
JBV_API JbvStatus JBV_CALL jbv_retain(JbvVM *vm, JbvRef ref) {
    JbvObject *object;
    JbvStatus status;
    JbvHandle *entry;
    if (!vm) return JBV_BAD_ARGUMENT;
    if (!ref) return JBV_OK;
    status = jbv_object(vm, ref, &object);
    if (status != JBV_OK) return status;
    entry = &vm->handles[(uint32_t)ref & 65535u];
    if (entry->pins == UINT32_MAX) return JBV_LIMIT_EXCEEDED;
    ++entry->pins;
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_release(JbvVM *vm, JbvRef ref) {
    JbvObject *object;
    JbvStatus status;
    JbvHandle *entry;
    if (!vm) return JBV_BAD_ARGUMENT;
    if (!ref) return JBV_OK;
    status = jbv_object(vm, ref, &object);
    if (status != JBV_OK) return status;
    entry = &vm->handles[(uint32_t)ref & 65535u];
    if (!entry->pins) return JBV_BAD_REFERENCE;
    --entry->pins;
    return JBV_OK;
}

static void mark(JbvVM *vm, int32_t ref, uint32_t *queue) {
    JbvObject *object;
    if (jbv_object(vm, ref, &object) != JBV_OK || object->mark) return;
    object->mark = 1;
    object->gc_next = *queue;
    *queue = (uint32_t)ref & 65535u;
}
JBV_API JbvStatus JBV_CALL jbv_collect(JbvVM *vm) {
    uint32_t i, queue = 0;
    JbvClass *c;
    JbvFrame *frame;
    if (!vm) return JBV_BAD_ARGUMENT;
    ++vm->collections;
    mark(vm, vm->exception, &queue);
    for (i = 1; i <= vm->handle_capacity; ++i) {
        JbvHandle *entry = &vm->handles[i];
        if (entry->object && (entry->pins || entry->object->monitor_depth)) mark(vm, (int32_t)((entry->generation << 16) | i), &queue);
    }
    for (frame = vm->frames; frame; frame = frame->previous) {
        uint32_t end = frame->base + frame->locals + *frame->sp;
        for (i = frame->base; i < end; ++i)
            if (vm->slot_refs[i] == JBV_REF) mark(vm, vm->slots[i], &queue);
    }
    for (c = vm->classes; c; c = c->next) {
        mark(vm, c->mirror, &queue);
        for (i = 1; i < c->pool_size; ++i) {
            JbvConstant *p = &c->pool[i];
            if (p->tag == 8 || p->tag == 15 || p->tag == 16)
                mark(vm, jbv_i32(p->bits), &queue);
        }
        for (i = 0; i < c->field_count; ++i)
            if ((c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor))
                mark(vm, c->fields[i].value, &queue);
    }
    while (queue) {
        JbvObject *object = vm->handles[queue].object;
        int32_t *data = jbv_data(object);
        queue = object->gc_next;
        if (object->type->array_kind == 'L') {
            for (i = 0; i < object->length; ++i) mark(vm, data[i], &queue);
        } else if (!object->type->array_kind) {
            for (c = object->type; c; c = c->super)
                for (i = 0; i < c->field_count; ++i)
                    if (!(c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor))
                        mark(vm, data[c->fields[i].slot], &queue);
        }
    }
    for (i = 1; i <= vm->handle_capacity; ++i) {
        JbvHandle *entry = &vm->handles[i];
        if (!entry->object) continue;
        if (entry->object->mark) { entry->object->mark = 0; continue; }
        vm->heap_bytes -= entry->object->bytes;
        --vm->object_count;
        jbv_free(vm, entry->object); entry->object = 0;
        if (entry->generation < 32767) {
            ++entry->generation;
            entry->next_free = vm->free_handle; vm->free_handle = i;
        } /* Retire a slot rather than wrap and resurrect a stale handle. */
    }
    return JBV_OK;
}
static JbvStatus grow_handles(JbvVM *vm) {
    uint32_t capacity = vm->handle_capacity ? vm->handle_capacity * 2 : 64, i;
    JbvHandle *entries;
    if (capacity > 65535) capacity = 65535;
    if (capacity == vm->handle_capacity) return JBV_OUT_OF_MEMORY;
    entries = (JbvHandle *)jbv_alloc(vm, (size_t)(capacity + 1) * sizeof(*entries));
    if (!entries) return JBV_OUT_OF_MEMORY;
    for (i = 1; i <= vm->handle_capacity; ++i) entries[i] = vm->handles[i];
    for (; i <= capacity; ++i) {
        entries[i].generation = 1;
        entries[i].next_free = i == capacity ? vm->free_handle : i + 1;
    }
    jbv_free(vm, vm->handles);
    vm->handles = entries;
    vm->free_handle = vm->handle_capacity + 1;
    vm->handle_capacity = capacity;
    return JBV_OK;
}
JbvStatus jbv_new(JbvVM *vm, JbvClass *type, int32_t length, int32_t *ref) {
    JbvObject *object;
    JbvStatus status;
    JbvClass *c;
    uint32_t count, index;
    size_t bytes;
    if (type->array_kind) {
        if (length < 0) return JBV_NEGATIVE_ARRAY_SIZE;
        count = (uint32_t)length;
        if (type->array_kind == 'C') count = (count + 1u) / 2u;
        if (type->array_kind == 'J' || type->array_kind == 'D') {
            if (count > UINT32_MAX / 2) return JBV_OUT_OF_MEMORY;
            count *= 2;
        }
    } else {
        uint16_t i;
        if (type->flags & (JBV_INTERFACE | JBV_ABSTRACT)) return JBV_LINKAGE_ERROR;
        count = type->instance_slots;
        for (c = type; c; c = c->super)
            for (i = 0; i < c->field_count; ++i) {
                JbvText d = c->fields[i].descriptor;
                if (!(c->fields[i].flags & JBV_STATIC) && !jbv_reference_type(d) &&
                    !(d.size == 1 && (d.data[0] == 'I' || d.data[0] == 'Z' || d.data[0] == 'B' || d.data[0] == 'C' || d.data[0] == 'S' || d.data[0] == 'J' || d.data[0] == 'F' || d.data[0] == 'D')))
                    return JBV_UNSUPPORTED_FEATURE;
            }
    }
    if (count > (SIZE_MAX - sizeof(*object)) / sizeof(int32_t)) return JBV_OUT_OF_MEMORY;
    bytes = sizeof(*object) + (size_t)count * sizeof(int32_t);
    if (bytes > vm->heap_limit) return JBV_OUT_OF_MEMORY;
    if (vm->heap_bytes > vm->heap_limit || bytes > vm->heap_limit - vm->heap_bytes || !vm->free_handle) (void)jbv_collect(vm);
    if (vm->heap_bytes > vm->heap_limit || bytes > vm->heap_limit - vm->heap_bytes) return JBV_OUT_OF_MEMORY;
    if (!vm->free_handle) {
        status = grow_handles(vm);
        if (status != JBV_OK) return status;
    }
    object = (JbvObject *)jbv_alloc(vm, bytes);
    if (!object) {
        (void)jbv_collect(vm);
        object = (JbvObject *)jbv_alloc(vm, bytes);
        if (!object) return JBV_OUT_OF_MEMORY;
    }
    object->type = type; object->length = type->array_kind ? (uint32_t)length : count; object->bytes = bytes;
    index = vm->free_handle;
    vm->free_handle = vm->handles[index].next_free;
    vm->handles[index].object = object;
    vm->heap_bytes += bytes; ++vm->object_count;
    *ref = (int32_t)((vm->handles[index].generation << 16) | index);
    return JBV_OK;
}
void jbv_free_heap(JbvVM *vm) {
    uint32_t i;
    for (i = 1; i <= vm->handle_capacity; ++i) {
        jbv_free(vm, vm->handles[i].object);
    }
    jbv_free(vm, vm->handles);
}
JbvStatus jbv_multi_array(JbvVM *vm, JbvClass *type, const int32_t *sizes, uint8_t dimensions, int32_t *ref) {
    JbvStatus status;
    int32_t parent = 0;
    JbvObject *object;
    uint32_t i;
    if (vm->depth >= vm->config.max_depth || !vm->remaining) return JBV_LIMIT_EXCEEDED;
    --vm->remaining;
    ++vm->depth;
    status = jbv_new(vm, type, sizes[0], &parent);
    if (status != JBV_OK) { --vm->depth; return status; }
    status = jbv_retain(vm, parent);
    if (status != JBV_OK) { --vm->depth; return status; }
    status = jbv_object(vm, parent, &object);
    if (status == JBV_OK && dimensions > 1)
        for (i = 0; i < object->length; ++i) {
            int32_t child = 0;
            status = jbv_multi_array(vm, type->component, sizes + 1, dimensions - 1, &child);
            if (status != JBV_OK) break;
            jbv_data(object)[i] = child;
        }
    (void)jbv_release(vm, parent);
    --vm->depth;
    if (status == JBV_OK) *ref = parent;
    return status;
}
JBV_API JbvStatus JBV_CALL jbv_set_heap_limit(JbvVM *vm, size_t bytes) {
    if (!vm || !bytes || bytes > vm->config.max_memory) return JBV_BAD_ARGUMENT;
    if (vm->depth) return JBV_BUSY;
    (void)jbv_collect(vm);
    if (vm->heap_bytes > bytes) return JBV_LIMIT_EXCEEDED;
    vm->heap_limit = bytes;
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_heap_stats(JbvVM *vm, JbvHeapStats *out) {
    if (!vm || !out) return JBV_BAD_ARGUMENT;
    out->bytes = vm->heap_bytes; out->objects = vm->object_count; out->collections = vm->collections;
    return JBV_OK;
}

#include "internal.h"
#include <intrin.h>

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
        if (!i) vm->object_class = c;
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
    c = jbv_find_class(vm, name);   /* loaded classes first: no name tables on the common path */
    if (c) { *out = c; return jbv_link(vm, c, 0); }
    if (jbv_exception_name(name)) return jbv_exception_class(vm, name, out);
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
    }
    c->instance_slots = c->super->instance_slots;
    for (i = 0; i < c->field_count; ++i)
        if (!(c->fields[i].flags & JBV_STATIC)) {
            JbvText d = c->fields[i].descriptor;
            if (!jbv_reference_type(d) && (d.size != 1 || !jbv_kind(d.data[0]) && d.data[0] != 'I' && d.data[0] != 'Z' && d.data[0] != 'B' && d.data[0] != 'C' && d.data[0] != 'S'))
                { status = JBV_UNSUPPORTED_FEATURE; goto fail; }
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

/* ---- References: ref = generation << 24 | handle index; handles hold object pointers. ---- */
uint32_t jbv_handle_ref(JbvVM *vm, uint32_t index) { return (uint32_t)vm->generations[index] << JBV_HANDLE_BITS | index; }
JbvStatus jbv_object(JbvVM *vm, int32_t ref, JbvObject **out) {
    uint32_t index = (uint32_t)ref & JBV_HANDLE_MASK;
    uintptr_t entry;
    if (!ref) return JBV_NULL_REFERENCE;
    if (ref < 0 || !index || index > vm->handle_capacity) return JBV_BAD_REFERENCE;
    entry = vm->handles[index];
    if (!(vm->used[index >> 5] >> (index & 31) & 1) || vm->generations[index] != (uint32_t)ref >> JBV_HANDLE_BITS) return JBV_BAD_REFERENCE;
    *out = (JbvObject *)entry;
    return JBV_OK;
}
JbvStatus jbv_check_reference(JbvVM *vm, int32_t ref, JbvText descriptor) {
    JbvObject *object;
    JbvClass *type, *actual;
    JbvStatus status;
    if (!ref) return JBV_OK;
    status = jbv_object(vm, ref, &object);
    if (status != JBV_OK) return status;
    if (descriptor.size > 2 && descriptor.data[0] == 'L' && descriptor.data[descriptor.size - 1] == ';') {
        ++descriptor.data; descriptor.size -= 2;
    } else if (!descriptor.size || descriptor.data[0] != '[') return JBV_BAD_CLASS;
    actual = object->type;   /* resolving may throw, i.e. allocate and move objects */
    status = jbv_resolve_class(vm, descriptor, &type);
    if (status != JBV_OK) return status;
    return jbv_assignable(actual, type) ? JBV_OK : JBV_CLASS_CAST;
}
/* Pins (host/native retains) are rare and short-lived: a small unsorted table. */
static JbvPin *find_pin(JbvVM *vm, uint32_t index) {
    uint32_t i;
    for (i = vm->pin_count; i--;) if (vm->pins[i].index == index) return &vm->pins[i];
    return 0;
}
JBV_API JbvStatus JBV_CALL jbv_retain(JbvVM *vm, JbvRef ref) {
    JbvObject *object;
    JbvStatus status;
    JbvPin *pin;
    if (!vm) return JBV_BAD_ARGUMENT;
    if (!ref) return JBV_OK;
    status = jbv_object(vm, ref, &object);
    if (status != JBV_OK) return status;
    pin = find_pin(vm, (uint32_t)ref & JBV_HANDLE_MASK);
    if (pin) { if (pin->count == UINT32_MAX) return JBV_LIMIT_EXCEEDED; ++pin->count; return JBV_OK; }
    if (vm->pin_count == vm->pin_capacity) {
        uint32_t capacity = vm->pin_capacity ? vm->pin_capacity * 2 : 16, i;
        JbvPin *pins = (JbvPin *)jbv_alloc(vm, capacity * sizeof(*pins));
        if (!pins) return JBV_OUT_OF_MEMORY;
        for (i = 0; i < vm->pin_count; ++i) pins[i] = vm->pins[i];
        jbv_free(vm, vm->pins); vm->pins = pins; vm->pin_capacity = capacity;
    }
    vm->pins[vm->pin_count].index = (uint32_t)ref & JBV_HANDLE_MASK; vm->pins[vm->pin_count++].count = 1;
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_release(JbvVM *vm, JbvRef ref) {
    JbvObject *object;
    JbvStatus status;
    JbvPin *pin;
    if (!vm) return JBV_BAD_ARGUMENT;
    if (!ref) return JBV_OK;
    status = jbv_object(vm, ref, &object);
    if (status != JBV_OK) return status;
    pin = find_pin(vm, (uint32_t)ref & JBV_HANDLE_MASK);
    if (!pin) return JBV_BAD_REFERENCE;
    if (!--pin->count) *pin = vm->pins[--vm->pin_count];
    return JBV_OK;
}

/* ---- Serial generational heap ------------------------------------------------------
 * Young generation: one bump region; each young block is [handle word][array length]
 * header payload, a spare word first, so the region can be
 * walked. Old generation: chunks (header: next, size) with bump allocation and
 * size-class free lists for blocks up to JBV_SMALL; larger blocks are host allocations.
 * Any allocation may collect and move objects (see JBV_GC in internal.h): a minor
 * collection promotes young survivors; a full collection also slides old objects
 * together and returns emptied chunks. Refs are handles, so moving an object only
 * rewrites its handle entry. */
#define JBV_SMALL 512u
#define JBV_CHUNK_HEADER (2 * sizeof(void *))
#define JBV_YOUNG_MAX 1048576u
static size_t align_size(size_t n) { return (n + JBV_ALIGN - 1) & ~(size_t)(JBV_ALIGN - 1); }
/* A young block starts with one spare word (kept: the layout is shared with the x86 core). */
static int young(const JbvVM *vm, const void *p) { return (uintptr_t)p - (uintptr_t)vm->nursery < vm->nursery_size; }
size_t jbv_object_bytes(const JbvObject *object) {
    const JbvClass *type = object->type;
    if (!type->array_kind) return (size_t)type->instance_slots * sizeof(int32_t);
    return (size_t)jbv_length(object) * jbv_element_bytes(type->array_kind);
}
static size_t prefix(const JbvObject *object) { return object->type->array_kind ? JBV_ALIGN : 0; }
/* Old-space block: [array length word] header payload, rounded to JBV_ALIGN. */
static size_t block_size(const JbvObject *object) { return align_size(prefix(object) + sizeof(*object) + jbv_object_bytes(object)); }
static void *block_start(JbvObject *object) { return (uint8_t *)object - prefix(object); }
static void copy_words(void *to, const void *from, size_t bytes) {
    size_t i;   /* forward copy: also correct for overlapping slides towards lower addresses */
    for (i = 0; i < bytes / sizeof(int32_t); ++i) ((int32_t *)to)[i] = ((const int32_t *)from)[i];
}
static void zero_words(void *p, size_t bytes) { size_t i; for (i = 0; i < bytes / sizeof(int32_t); ++i) ((int32_t *)p)[i] = 0; }

static void *block_alloc(JbvVM *vm, size_t size) {
    void **list, *p;
    if (size > JBV_SMALL) return jbv_alloc(vm, size);
    list = &vm->free_blocks[size / JBV_ALIGN];
    if (*list) { p = *list; *list = *(void **)p; zero_words(p, size); return p; }
    if ((size_t)(vm->bump_end - vm->bump) < size) {
        size_t chunk = vm->chunk_size ? vm->chunk_size : 2048, rest = (size_t)(vm->bump_end - vm->bump);
        void **block = (void **)jbv_alloc(vm, chunk);
        if (!block) { chunk = JBV_CHUNK_HEADER + size; block = (void **)jbv_alloc(vm, chunk); }   /* tight budget: exact chunk */
        if (!block) return 0;
        if (rest >= JBV_ALIGN) { *(void **)vm->bump = vm->free_blocks[rest / JBV_ALIGN]; vm->free_blocks[rest / JBV_ALIGN] = vm->bump; }
        block[0] = vm->chunks; ((size_t *)block)[1] = chunk; vm->chunks = block;
        vm->bump = (uint8_t *)block + JBV_CHUNK_HEADER; vm->bump_end = (uint8_t *)block + chunk;
        if (chunk >= vm->chunk_size && chunk < 65536) vm->chunk_size = chunk * 2;
    }
    p = vm->bump; vm->bump += size;   /* chunk memory arrives zeroed */
    return p;
}
static void block_free(JbvVM *vm, void *p, size_t size) {
    if (size > JBV_SMALL) { jbv_free(vm, p); return; }
    *(void **)p = vm->free_blocks[size / JBV_ALIGN]; vm->free_blocks[size / JBV_ALIGN] = p;
}
/* Growable pointer list; on failure the caller falls back to a conservative full scan. */
static int push_pointer(JbvVM *vm, void ***list, uint32_t *count, uint32_t *capacity, void *p) {
    if (*count >= 65536) return 0;   /* bounded: past this the next minor scans the old generation */
    if (*count == *capacity) {
        uint32_t size = *capacity ? *capacity * 2 : 64, i;
        void **grown = (void **)jbv_alloc(vm, size * sizeof(void *));
        if (!grown) return 0;
        for (i = 0; i < *count; ++i) grown[i] = (*list)[i];
        jbv_free(vm, *list); *list = grown; *capacity = size;
    }
    (*list)[(*count)++] = p;
    return 1;
}
/* Write barrier slow path: an old object may now reference a young one. */
void jbv_remember(JbvVM *vm, JbvObject *owner) {
    if (vm->last_remembered == owner) return;
    if (!push_pointer(vm, &vm->remembered, &vm->remembered_count, &vm->remembered_capacity, owner)) vm->remembered_overflow = 1;
    else vm->last_remembered = owner;
}
void jbv_barrier_checked(JbvVM *vm, JbvObject *owner, int32_t value) {
    JbvObject *target;
    if (vm->nursery && !young(vm, owner) && jbv_object(vm, value, &target) == JBV_OK && young(vm, target)) jbv_remember(vm, owner);
}

/* ---- Marking and scanning. A fixed mark stack; on overflow marked objects are rescanned. ---- */
/* The reference slots of a class (an oop map), built on first use; 0 if memory is short. */
static const uint16_t *ref_slots(JbvVM *vm, JbvClass *type, uint32_t *count) {
    const JbvClass *c;
    uint32_t n = 0, i;
    if (!type->ref_ready) {
        for (c = type; c; c = c->super)
            for (i = 0; i < c->field_count; ++i)
                if (!(c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor)) ++n;
        if (n) {
            type->ref_slots = (uint16_t *)jbv_alloc(vm, n * sizeof(uint16_t));
            if (!type->ref_slots) { *count = 0; return 0; }
            n = 0;
            for (c = type; c; c = c->super)
                for (i = 0; i < c->field_count; ++i)
                    if (!(c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor)) type->ref_slots[n++] = (uint16_t)c->fields[i].slot;
        }
        type->ref_count = (uint16_t)n; type->ref_ready = 1;
    }
    *count = type->ref_count;
    return type->ref_slots ? type->ref_slots : (const uint16_t *)type;   /* non-null: ready (count may be 0) */
}
static int needs_scan(const JbvClass *type) {
    const JbvClass *c;
    uint16_t i;
    if (type->array_kind) return type->array_kind == 'L';
    if (type->ref_ready) return type->ref_count != 0;
    for (c = type; c; c = c->super)
        for (i = 0; i < c->field_count; ++i)
            if (!(c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor)) return 1;
    return 0;
}
typedef void (*Visit)(JbvVM *vm, int32_t ref);
static void push_mark(JbvVM *vm, uint32_t index) {
    if (vm->mark_top < sizeof(vm->mark_stack) / sizeof(vm->mark_stack[0])) vm->mark_stack[vm->mark_top++] = index;
    else vm->mark_overflow = 1;
}
static void scan(JbvVM *vm, JbvObject *object, Visit visit) {
    int32_t *data = jbv_data(object);
    const JbvClass *c;
    uint32_t i;
    vm->scanning = object;
    if (object->type->array_kind == 'L') { for (i = jbv_length(object); i--;) visit(vm, data[i]); }
    else if (!object->type->array_kind) {
        uint32_t count;
        const uint16_t *slots = ref_slots(vm, object->type, &count);
        if (slots) { for (i = 0; i < count; ++i) visit(vm, data[slots[i]]); vm->scanning = 0; return; }
        for (c = object->type; c; c = c->super)
            for (i = 0; i < c->field_count; ++i)
                if (!(c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor)) visit(vm, data[c->fields[i].slot]);
    }
    vm->scanning = 0;
}
/* Full marking also rebuilds the remembered set (old objects referencing young ones). */
static void mark_full(JbvVM *vm, int32_t ref) {
    JbvObject *object;
    uint32_t index = (uint32_t)ref & JBV_HANDLE_MASK;
    if (jbv_object(vm, ref, &object) != JBV_OK) return;
    if (vm->scanning && !young(vm, vm->scanning) && young(vm, object)) { jbv_remember(vm, vm->scanning); }
    if (jbv_bit(vm->marks, index)) return;
    vm->marks[index >> 5] |= 1u << (index & 31);
    if (needs_scan(object->type)) push_mark(vm, index);
}
static void drain(JbvVM *vm, Visit visit) {
    while (vm->mark_top) scan(vm, (JbvObject *)vm->handles[vm->mark_stack[--vm->mark_top]], visit);
}
/* Where a class holds references outside objects (built once: fields and the pool are fixed). */
static int class_roots(JbvVM *vm, JbvClass *c) {
    uint32_t i, n = 0;
    if (c->roots_ready) return 1;
    for (i = 1; i < c->pool_size; ++i) n += c->pool[i].tag == 8 || c->pool[i].tag == 15 || c->pool[i].tag == 16;
    for (i = 0; i < c->field_count; ++i) n += (c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor);
    if (n) {
        c->root_slots = (int32_t **)jbv_alloc(vm, n * sizeof(int32_t *));
        if (!c->root_slots) return 0;
        n = 0;
        for (i = 1; i < c->pool_size; ++i)
            if (c->pool[i].tag == 8 || c->pool[i].tag == 15 || c->pool[i].tag == 16) c->root_slots[n++] = (int32_t *)&c->pool[i].bits;
        for (i = 0; i < c->field_count; ++i)
            if ((c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor)) c->root_slots[n++] = &c->fields[i].value;
    }
    c->root_count = n; c->roots_ready = 1;
    return 1;
}
static void roots(JbvVM *vm, Visit visit) {
    uint32_t i;
    JbvClass *c;
    JbvFrame *frame;
    visit(vm, vm->exception);
    for (i = 0; i < vm->pin_count; ++i) visit(vm, (int32_t)jbv_handle_ref(vm, vm->pins[i].index));
    for (i = 0; i < vm->monitor_capacity; ++i) if (vm->monitors[i].ref) visit(vm, vm->monitors[i].ref);
    for (frame = vm->frames; frame; frame = frame->previous) {
        uint32_t end = frame->base + frame->locals + frame->sp;
        for (i = frame->base; i < end; ++i) if (vm->slot_refs[i] == JBV_REF) visit(vm, vm->slots[i]);
    }
    for (c = vm->classes; c; c = c->next) {
        visit(vm, c->mirror);
        if (class_roots(vm, c)) {
            for (i = 0; i < c->root_count; ++i) visit(vm, *c->root_slots[i]);
            drain(vm, visit);
            continue;
        }
        for (i = 1; i < c->pool_size; ++i) {
            JbvConstant *p = &c->pool[i];
            if (p->tag == 8 || p->tag == 15 || p->tag == 16) visit(vm, jbv_i32(p->bits));
        }
        for (i = 0; i < c->field_count; ++i)
            if ((c->fields[i].flags & JBV_STATIC) && jbv_reference_type(c->fields[i].descriptor)) visit(vm, c->fields[i].value);
        drain(vm, visit);
    }
    drain(vm, visit);
}
static void clear_marks(JbvVM *vm) {
    uint32_t i;
    for (i = 0; i <= vm->handle_capacity >> 5; ++i) vm->marks[i] = 0;
    vm->mark_top = 0; vm->mark_overflow = 0;
}
static void finish_marking(JbvVM *vm, Visit visit) {
    uint32_t i;
    while (vm->mark_overflow) {   /* rare: rescan every marked object until nothing new is marked */
        vm->mark_overflow = 0;
        for (i = 1; i <= vm->handle_capacity; ++i)
            if (jbv_bit(vm->marks, i) && jbv_bit(vm->used, i)) { scan(vm, (JbvObject *)vm->handles[i], visit); drain(vm, visit); }
    }
}
static void free_handle(JbvVM *vm, uint32_t i) {
    uint32_t bit = ~(1u << (i & 31));
    vm->used[i >> 5] &= bit; vm->young[i >> 5] &= bit; vm->interned[i >> 5] &= bit;
    --vm->object_count;
}
/* A free handle (0 if none), found from the cursor in the allocation bitmap. Generations
 * advance on reuse (1..127): a stale ref is detected unless its slot was reused 127 times. */
static uint32_t take_handle(JbvVM *vm) {
    uint32_t words = (vm->handle_capacity >> 5) + 1, w = vm->handle_cursor, n, index;
    unsigned long bit;
    for (n = 0; n < words; ++n, w = w + 1 < words ? w + 1 : 0)
        if (_BitScanForward(&bit, ~vm->used[w])) {
            vm->used[w] |= 1u << bit; vm->handle_cursor = w; index = w << 5 | bit;
            vm->generations[index] = (uint8_t)(vm->generations[index] == 127 ? 1 : vm->generations[index] + 1);
            ++vm->object_count;
            return index;
        }
    return 0;
}

/* ---- Minor collection: promote reachable young objects, then reset the young region. ---- */
static void promote(JbvVM *vm, int32_t ref) {
    JbvObject *object;
    uint32_t index = (uint32_t)ref & JBV_HANDLE_MASK;
    uint8_t *copy;
    size_t size;
    if (jbv_object(vm, ref, &object) != JBV_OK || !young(vm, object) || jbv_bit(vm->marks, index)) return;
    size = block_size(object);
    copy = (uint8_t *)block_alloc(vm, size);
    if (!copy) { vm->promote_failed = 1; return; }
    vm->marks[index >> 5] |= 1u << (index & 31);
    copy_words(copy, block_start(object), size);
    vm->handles[index] = (uintptr_t)(copy + prefix(object));
    vm->heap_bytes += size;
    if (needs_scan(object->type)) push_mark(vm, index);
}
static void promote_children(JbvVM *vm, JbvObject *object) { scan(vm, object, promote); drain(vm, promote); }
static JbvStatus minor(JbvVM *vm) {
    uint32_t i;
    if (!vm->nursery || vm->nursery_top == vm->nursery) { vm->remembered_count = vm->recent_count = 0; vm->remembered_overflow = 0; vm->last_remembered = 0; return JBV_OK; }
    clear_marks(vm); vm->promote_failed = 0;
    roots(vm, promote);
    for (i = 0; i < vm->remembered_count; ++i) promote_children(vm, (JbvObject *)vm->remembered[i]);
    for (i = 0; i < vm->recent_count; ++i) promote_children(vm, (JbvObject *)vm->recent[i]);
    if (vm->remembered_overflow)
        for (i = 1; i <= vm->handle_capacity; ++i)
            if (jbv_bit(vm->used, i) && !young(vm, (void *)vm->handles[i]) && !jbv_bit(vm->marks, i))
                promote_children(vm, (JbvObject *)vm->handles[i]);
    finish_marking(vm, promote);
    if (vm->promote_failed) return JBV_OUT_OF_MEMORY;   /* consistent: promoted objects moved, others stay */
    /* Unreachable young objects are not touched: their handles are young and unmarked. */
    for (i = 0; i <= vm->handle_capacity >> 5; ++i)
        if (vm->young[i]) {
            uint32_t dead = vm->young[i] & ~vm->marks[i];
            vm->used[i] &= ~dead; vm->interned[i] &= ~dead; vm->object_count -= __popcnt(dead); vm->young[i] = 0;
        }
    vm->heap_bytes -= (size_t)(vm->nursery_top - vm->nursery);
#if JBV_GC_STRESS
    { uint8_t *q; for (q = vm->nursery; q < vm->nursery_top; ++q) *q = 0xcd; }   /* poison: stale pointers read garbage */
#else
    /* The young region is kept zeroed above nursery_top: allocation there needs no clearing. */
    __stosd((unsigned long *)vm->nursery, 0, (size_t)(vm->nursery_top - vm->nursery) / 4);
#endif
    vm->nursery_top = vm->nursery;
    vm->remembered_count = vm->recent_count = 0; vm->remembered_overflow = 0; vm->last_remembered = 0;
    return JBV_OK;
}

/* ---- Full collection: mark, sweep, then slide old objects together. ---- */
static uintptr_t address(JbvVM *vm, uint32_t i) { return (uintptr_t)block_start((JbvObject *)vm->handles[i]); }
static void sift(JbvVM *vm, uint32_t *a, uint32_t i, uint32_t n) {
    uint32_t x = a[i], c;
    for (; (c = 2 * i + 1) < n; i = c) {
        if (c + 1 < n && address(vm, a[c]) < address(vm, a[c + 1])) ++c;
        if (address(vm, x) >= address(vm, a[c])) break;
        a[i] = a[c];
    }
    a[i] = x;
}
/* Slide live small old objects (sorted by address) to the front of address-ordered chunks. */
static void compact(JbvVM *vm, uint32_t *live, uint32_t n, void **chunks, uint32_t count) {
    uint32_t i, j, k = 0;
    uint8_t *d, *end;
    for (i = 1; i < count; ++i) { void *x = chunks[i]; for (j = i; j && (uintptr_t)chunks[j - 1] > (uintptr_t)x; --j) chunks[j] = chunks[j - 1]; chunks[j] = x; }
    if (n > 1) { uint32_t x; for (i = n / 2; i--;) sift(vm, live, i, n); for (i = n - 1; i; --i) { x = live[0]; live[0] = live[i]; live[i] = x; sift(vm, live, 0, i); } }
    for (i = 0; i < sizeof(vm->free_blocks) / sizeof(vm->free_blocks[0]); ++i) vm->free_blocks[i] = 0;
    d = (uint8_t *)chunks[0] + JBV_CHUNK_HEADER; end = (uint8_t *)chunks[0] + ((size_t *)chunks[0])[1];
    for (i = 0; i < n; ++i) {
        JbvObject *object = (JbvObject *)vm->handles[live[i]];
        uint8_t *src = (uint8_t *)block_start(object);
        size_t size = block_size(object), pre = prefix(object);
        while ((size_t)(end - d) < size) {   /* such a gap is smaller than this block, so <= JBV_SMALL */
            if ((size_t)(end - d) >= JBV_ALIGN) block_free(vm, d, (size_t)(end - d));
            ++k; d = (uint8_t *)chunks[k] + JBV_CHUNK_HEADER; end = (uint8_t *)chunks[k] + ((size_t *)chunks[k])[1];
        }
        if (d != src) copy_words(d, src, size);
        vm->handles[live[i]] = (uintptr_t)(d + pre);
        d += size;
    }
    for (i = k + 1; i < count; ++i) jbv_free(vm, chunks[i]);   /* emptied chunks go back to the host */
    for (i = 0; i < k; ++i) *(void **)chunks[i] = chunks[i + 1];
    *(void **)chunks[k] = 0;
    zero_words(d, (size_t)(end - d));   /* bump allocation expects zeroed memory */
    vm->chunks = chunks[0]; vm->bump = d; vm->bump_end = end;
}
static JbvStatus collect(JbvVM *vm, int moving) {
    uint32_t i, n = 0, count = 0, *live = 0;
    void **chunks = 0, *chunk;
    if (!vm->marks) return JBV_OK;   /* nothing allocated yet */
    ++vm->collections;
    if (moving && minor(vm) != JBV_OK) moving = 0;
    vm->remembered_count = vm->recent_count = 0; vm->remembered_overflow = 0; vm->last_remembered = 0;
    clear_marks(vm);
    roots(vm, mark_full); finish_marking(vm, mark_full);
    for (chunk = vm->chunks; chunk; chunk = *(void **)chunk) ++count;
    if (moving && count) {   /* scratch first: if it is unavailable, sweep without moving */
        live = (uint32_t *)jbv_alloc(vm, ((size_t)vm->object_count + 1) * sizeof(*live));
        chunks = (void **)jbv_alloc(vm, count * sizeof(*chunks));
        if (!live || !chunks) { jbv_free(vm, live); jbv_free(vm, chunks); live = 0; chunks = 0; }
        for (i = 0, chunk = vm->chunks; chunks && chunk; chunk = *(void **)chunk) chunks[i++] = chunk;
    }
    for (i = 1; i <= vm->handle_capacity; ++i) {
        JbvObject *object = (JbvObject *)vm->handles[i];
        size_t size;
        if (!jbv_bit(vm->used, i)) continue;
        size = block_size(object);
        if (jbv_bit(vm->marks, i)) { if (live && !young(vm, object) && size <= JBV_SMALL) live[n++] = i; continue; }
        if (!young(vm, object)) {   /* young garbage is reclaimed when the young region resets */
            vm->heap_bytes -= size;
            if (!live || size > JBV_SMALL) block_free(vm, block_start(object), size);
        }
        free_handle(vm, i);
    }
    if (live) { compact(vm, live, n, chunks, count); jbv_free(vm, live); jbv_free(vm, chunks); }
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_collect(JbvVM *vm) {
    if (!vm) return JBV_BAD_ARGUMENT;
    /* From the host with no Java running nothing holds raw pointers: compact. */
    return collect(vm, 1);
}
static JbvStatus grow_handles(JbvVM *vm) {
    uint32_t old = vm->handle_capacity, capacity = old ? old * 2 : 255, words, i;
    uintptr_t *handles;
    uint8_t *generations;
    uint32_t *marks, *interned, *used, *young;
    if (capacity > JBV_HANDLE_MASK) capacity = JBV_HANDLE_MASK;
    if (capacity == old) return JBV_OUT_OF_MEMORY;
    words = (capacity >> 5) + 1;
    handles = (uintptr_t *)jbv_alloc(vm, (size_t)(capacity + 1) * sizeof(*handles));
    generations = (uint8_t *)jbv_alloc(vm, (size_t)capacity + 1);
    marks = (uint32_t *)jbv_alloc(vm, (size_t)words * sizeof(*marks));
    interned = (uint32_t *)jbv_alloc(vm, (size_t)words * sizeof(*interned));
    used = (uint32_t *)jbv_alloc(vm, (size_t)words * sizeof(*used));
    young = (uint32_t *)jbv_alloc(vm, (size_t)words * sizeof(*young));
    if (!handles || !generations || !marks || !interned || !used || !young) {
        jbv_free(vm, handles); jbv_free(vm, generations); jbv_free(vm, marks); jbv_free(vm, interned); jbv_free(vm, used); jbv_free(vm, young);
        return JBV_OUT_OF_MEMORY;
    }
    for (i = 1; i <= old; ++i) { handles[i] = vm->handles[i]; generations[i] = vm->generations[i]; }
    for (i = 0; old && i <= old >> 5; ++i) { marks[i] = vm->marks[i]; interned[i] = vm->interned[i]; used[i] = vm->used[i]; young[i] = vm->young[i]; }
    if (old) used[old >> 5] &= (old & 31) == 31 ? ~0u : (2u << (old & 31)) - 1;   /* the old tail becomes allocatable */
    else used[0] = 1;                                                           /* handle 0 is null */
    for (i = old + 1; i <= capacity; ++i) generations[i] = 1;
    if ((capacity & 31) != 31) used[capacity >> 5] |= ~((2u << (capacity & 31)) - 1);   /* past the end: never free */
    jbv_free(vm, vm->handles); jbv_free(vm, vm->generations); jbv_free(vm, vm->marks); jbv_free(vm, vm->interned); jbv_free(vm, vm->used); jbv_free(vm, vm->young);
    vm->handles = handles; vm->generations = generations; vm->marks = marks; vm->interned = interned; vm->used = used; vm->young = young;
    vm->handle_cursor = (old + 1) >> 5;
    vm->handle_capacity = capacity;
    return JBV_OK;
}
/* Out of host memory: promote everything, give the young region back, continue old-only. */
JBV_GC static int drop_young(JbvVM *vm, int moving) {
    if (!vm->nursery || (vm->nursery_top != vm->nursery && (!moving || minor(vm) != JBV_OK))) return 0;
    jbv_free(vm, vm->nursery);
    vm->nursery = vm->nursery_top = 0; vm->nursery_size = 0; vm->nursery_disabled = 1;
    return 1;
}
JbvStatus jbv_new(JbvVM *vm, JbvClass *type, int32_t length, int32_t *ref) {
    JbvObject *object;
    JbvStatus status;
    uint32_t index;
    uint64_t payload;
    size_t bytes, pre = 0;
    uint8_t *block = 0;
    int moving = 1, in_young = 0;
#if !JBV_GC_STRESS
    /* The common case: a plain object that fits the young region (pre-zeroed), a free handle. */
    if (!type->array_kind && vm->object_count < vm->handle_capacity && !(type->flags & (JBV_INTERFACE | JBV_ABSTRACT))) {
        bytes = JBV_ALIGN + align_size(sizeof(*object) + (size_t)type->instance_slots * sizeof(int32_t));
        if (bytes <= JBV_ALIGN + JBV_SMALL && (size_t)(vm->nursery + vm->nursery_size - vm->nursery_top) >= bytes &&
            vm->heap_bytes <= vm->heap_limit && bytes <= vm->heap_limit - vm->heap_bytes) {
            block = vm->nursery_top; vm->nursery_top += bytes; vm->heap_bytes += bytes;
            object = (JbvObject *)(block + JBV_ALIGN);
            object->type = type;
            index = take_handle(vm);
            vm->handles[index] = (uintptr_t)object;
            vm->young[index >> 5] |= 1u << (index & 31);
            *ref = (int32_t)jbv_handle_ref(vm, index);
            return JBV_OK;
        }
    }
#endif
    if (type->array_kind) {
        if (length < 0) return JBV_NEGATIVE_ARRAY_SIZE;
        payload = (uint64_t)(uint32_t)length * jbv_element_bytes(type->array_kind);
        pre = JBV_ALIGN;
    } else {
        if (type->flags & (JBV_INTERFACE | JBV_ABSTRACT)) return JBV_LINKAGE_ERROR;
        payload = (uint64_t)type->instance_slots * sizeof(int32_t);
    }
    if (payload > SIZE_MAX / 2) return JBV_OUT_OF_MEMORY;
    bytes = align_size(pre + sizeof(*object) + (size_t)payload);
    if (bytes > vm->heap_limit) return JBV_OUT_OF_MEMORY;
#if JBV_GC_STRESS
    /* Stress mode: move objects at every allocation to expose stale pointers and missing barriers. */
    /* JBV_GC_STRESS = N: a minor collection every N allocations, a full compacting one every 32 of those. */
    if (vm->handles && !(++vm->stress % JBV_GC_STRESS)) (void)(vm->stress % (32u * JBV_GC_STRESS) ? minor(vm) : collect(vm, 1));
#endif
    if (vm->heap_bytes > vm->heap_limit || bytes > vm->heap_limit - vm->heap_bytes || vm->object_count >= vm->handle_capacity) {
        (void)collect(vm, moving);
        /* Grow the handle table early when it stays mostly live, so collections stay amortized. */
        if (vm->handle_capacity - vm->object_count < vm->handle_capacity / 4 && vm->handle_capacity < JBV_HANDLE_MASK) (void)grow_handles(vm);
    }
    if (vm->heap_bytes > vm->heap_limit || bytes > vm->heap_limit - vm->heap_bytes) return JBV_OUT_OF_MEMORY;
    if (bytes <= JBV_YOUNG_MAX / 8) {
        if (!vm->nursery && !vm->nursery_disabled) {   /* lazily, 1/8 of the heap up to 1 MiB */
            size_t size = vm->heap_limit / 8 > JBV_YOUNG_MAX ? JBV_YOUNG_MAX : (vm->heap_limit / 8) & ~(size_t)(JBV_ALIGN - 1);
            if (size >= 16384) vm->nursery = (uint8_t *)jbv_alloc(vm, size);
            if (vm->nursery) { vm->nursery_size = size; vm->nursery_top = vm->nursery; } else vm->nursery_disabled = 1;
        }
        /* Arrays up to 1/8 of the young region start young too (no write barrier while young). */
        if (vm->nursery && bytes > JBV_SMALL && JBV_ALIGN + bytes > vm->nursery_size / 8) goto old;
        if (vm->nursery && (size_t)(vm->nursery + vm->nursery_size - vm->nursery_top) < JBV_ALIGN + bytes && moving) (void)minor(vm);
        if (vm->nursery && (size_t)(vm->nursery + vm->nursery_size - vm->nursery_top) >= JBV_ALIGN + bytes) {
            block = vm->nursery_top + JBV_ALIGN; vm->nursery_top += JBV_ALIGN + bytes;
#if JBV_GC_STRESS
            zero_words(block - JBV_ALIGN, JBV_ALIGN + bytes);   /* poisoned after each minor collection */
#endif
            vm->heap_bytes += JBV_ALIGN + bytes; in_young = 1;
        }
    }
old:
    if (!block) {
        block = (uint8_t *)block_alloc(vm, bytes);
        if (!block) {
            (void)collect(vm, moving);
            block = (uint8_t *)block_alloc(vm, bytes);
            if (!block && drop_young(vm, moving)) block = (uint8_t *)block_alloc(vm, bytes);
            if (!block) return JBV_OUT_OF_MEMORY;
        }
        vm->heap_bytes += bytes;
    }
    if (vm->object_count >= vm->handle_capacity) {   /* only when no collection could free one: grow */
        status = grow_handles(vm);
        if (status != JBV_OK) {
            if (in_young) { vm->nursery_top -= JBV_ALIGN + bytes; vm->heap_bytes -= JBV_ALIGN + bytes; zero_words(vm->nursery_top, JBV_ALIGN + bytes); }
            else { vm->heap_bytes -= bytes; block_free(vm, block, bytes); }
            return status;
        }
    }
    if (pre) *(uint32_t *)(block + pre - sizeof(uint32_t)) = (uint32_t)length;
    object = (JbvObject *)(block + pre);
    object->type = type;
    index = take_handle(vm);
    vm->handles[index] = (uintptr_t)object;
    if (in_young) vm->young[index >> 5] |= 1u << (index & 31);
    else if (vm->nursery && !push_pointer(vm, &vm->recent, &vm->recent_count, &vm->recent_capacity, object)) vm->remembered_overflow = 1;
    *ref = (int32_t)jbv_handle_ref(vm, index);
    return JBV_OK;
}
void jbv_free_heap(JbvVM *vm) {
    uint32_t i;
    void *chunk;
    for (i = 1; i <= vm->handle_capacity; ++i) {
        JbvObject *object = (JbvObject *)vm->handles[i];
        if (jbv_bit(vm->used, i) && !young(vm, object) && block_size(object) > JBV_SMALL) jbv_free(vm, block_start(object));
    }
    while ((chunk = vm->chunks) != 0) { vm->chunks = *(void **)chunk; jbv_free(vm, chunk); }
    jbv_free(vm, vm->nursery);
    jbv_free(vm, vm->handles); jbv_free(vm, vm->generations); jbv_free(vm, vm->marks); jbv_free(vm, vm->interned);
    jbv_free(vm, vm->used); jbv_free(vm, vm->young);
    jbv_free(vm, vm->pins); jbv_free(vm, vm->remembered); jbv_free(vm, vm->recent);
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
    if (dimensions > 1)
        for (i = 0; i < (uint32_t)sizes[0]; ++i) {
            int32_t child = 0;
            status = jbv_multi_array(vm, type->component, sizes + 1, dimensions - 1, &child);
            if (status != JBV_OK) break;
            (void)jbv_object(vm, parent, &object);   /* the child allocation may have moved it */
            jbv_data(object)[i] = child; jbv_barrier(vm, object, child);
        }
    (void)jbv_release(vm, parent);
    --vm->depth;
    if (status == JBV_OK) *ref = parent;
    return status;
}
JBV_GC JBV_API JbvStatus JBV_CALL jbv_set_heap_limit(JbvVM *vm, size_t bytes) {
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

#include "internal.h"

/* Preserve allocation alignment. The VM itself is allocated directly and
 * accounted separately during creation; all other blocks carry their size. */
typedef union JbvAllocation {
    size_t bytes;
    uint64_t alignment; /* All VM payload types require at most 8-byte alignment. */
} JbvAllocation;

uint16_t jbv_u16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
uint32_t jbv_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}
void *jbv_alloc(JbvVM *vm, size_t bytes) {
    JbvAllocation *allocation;
    size_t total, i;
    volatile uint8_t *data;
    if (!bytes) bytes = 1;
    if (bytes > SIZE_MAX - sizeof(*allocation)) return 0;
    total = bytes + sizeof(*allocation);
    if (total > vm->config.max_memory - vm->memory_used) return 0;
    allocation = (JbvAllocation *)vm->config.alloc(vm->config.allocator_user, total);
    if (!allocation) return 0;
    allocation->bytes = total;
    vm->memory_used += total;
    if (vm->memory_used > vm->memory_peak) vm->memory_peak = vm->memory_used;
    data = (volatile uint8_t *)(allocation + 1);
    /* Volatile keeps the freestanding build independent of CRT memset. */
    for (i = 0; i < bytes; ++i) data[i] = 0;
    return allocation + 1;
}
void jbv_free(JbvVM *vm, void *memory) {
    if (memory) {
        JbvAllocation *allocation = (JbvAllocation *)memory - 1;
        vm->memory_used -= allocation->bytes;
        vm->config.free(vm->config.allocator_user, allocation);
    }
}
JBV_API JbvStatus JBV_CALL jbv_memory_stats(JbvVM *vm, JbvMemoryStats *out) {
    if (!vm || !out) return JBV_BAD_ARGUMENT;
    out->used = vm->memory_used; out->peak = vm->memory_peak; out->limit = vm->config.max_memory;
    return JBV_OK;
}
JbvText jbv_text(const char *s) {
    JbvText t;
    size_t n = 0;
    while (s[n] && n < UINT16_MAX) ++n;
    t.data = (const uint8_t *)s;
    t.size = (uint16_t)n;
    return t;
}
int jbv_text_eq(JbvText a, JbvText b) {
    uint16_t i;
    if (a.size != b.size) return 0;
    for (i = 0; i < a.size; ++i) if (a.data[i] != b.data[i]) return 0;
    return 1;
}
int jbv_text_is(JbvText a, const char *s) {
    uint16_t i;
    for (i = 0; i < a.size; ++i)
        if (!s[i] || a.data[i] != (uint8_t)s[i]) return 0;
    return s[a.size] == 0;
}
JbvConstant *jbv_cp(JbvClass *c, uint16_t index, uint8_t tag) {
    return index && index < c->pool_size && c->pool[index].tag == tag ? &c->pool[index] : 0;
}
static uint32_t name_slot(JbvText name) {
    uint32_t h = name.size, i;
    for (i = 0; i < name.size; ++i) h = h * 31 + name.data[i];
    return (h ^ h >> 7) & 63u;
}
JbvClass *jbv_find_class(JbvVM *vm, JbvText name) {
    JbvClass *c;
    uint32_t slot = name_slot(name);
    c = vm->class_cache[slot];
    if (c && jbv_text_eq(c->name, name)) return c;
    for (c = vm->classes; c; c = c->next) if (!c->primitive && jbv_text_eq(c->name, name)) { vm->class_cache[slot] = c; return c; }
    return 0;
}
JbvMethod *jbv_find_method(JbvClass *c, JbvText name, JbvText descriptor) {
    uint16_t i;
    for (i = 0; i < c->method_count; ++i)
        if (jbv_text_eq(c->methods[i].name, name) &&
            jbv_text_eq(c->methods[i].descriptor, descriptor)) return &c->methods[i];
    return 0;
}
JbvField *jbv_find_field(JbvClass *c, JbvText name, JbvText descriptor) {
    uint16_t i;
    for (i = 0; i < c->field_count; ++i)
        if (jbv_text_eq(c->fields[i].name, name) &&
            jbv_text_eq(c->fields[i].descriptor, descriptor)) return &c->fields[i];
    return 0;
}
static int inside(const JbvArchive *a, const uint8_t *p) { return a->data && p >= a->data && p < a->data + a->size; }
void jbv_free_image(JbvVM *vm, uint8_t *image) {
    if (!inside(&vm->library, image) && !inside(&vm->app, image)) jbv_free(vm, image);
}
void jbv_free_class(JbvVM *vm, JbvClass *c) {
    uint32_t slot;
    if (!c) return;
    for (slot = 0; slot < 64; ++slot) if (vm->class_cache[slot] == c) vm->class_cache[slot] = 0;
    if (vm->throwable_class == c || vm->trace_element_class == c) {
        vm->throwable_class = vm->trace_element_class = 0;
        for (slot = 0; slot < 5; ++slot) vm->throwable_init[slot] = 0;
    }
    jbv_free(vm, c->ref_slots);
    jbv_free(vm, c->root_slots);
    jbv_free(vm, c->methods);
    jbv_free(vm, c->fields);
    jbv_free(vm, c->interfaces);
    if (c->pool) {
        uint16_t i;
        for (i = 1; i < c->pool_size; ++i)
            if (c->pool[i].tag >= 9 && c->pool[i].tag <= 11) jbv_free(vm, (void *)c->pool[i].text.data);
    }
    jbv_free(vm, c->pool);
    jbv_free_image(vm, c->image);
    jbv_free(vm, c);
}
JBV_API JbvStatus JBV_CALL jbv_create(const JbvConfig *config, JbvVM **out) {
    JbvVM *vm;
    JbvStatus status;
    size_t i;
    size_t memory_limit;
    if (!out) return JBV_BAD_ARGUMENT;
    *out = 0;
    if (!config || !config->alloc || !config->free || config->max_depth > 256 ||
        config->max_slots > 16777216) return JBV_BAD_ARGUMENT;
    memory_limit = config->max_memory ? config->max_memory : 10u * 1024u * 1024u;
    if (config->max_heap > memory_limit) return JBV_BAD_ARGUMENT;
    if (memory_limit < sizeof(*vm)) return JBV_OUT_OF_MEMORY;
    vm = (JbvVM *)config->alloc(config->allocator_user, sizeof(*vm));
    if (!vm) return JBV_OUT_OF_MEMORY;
    for (i = 0; i < sizeof(*vm); ++i) ((volatile uint8_t *)vm)[i] = 0;
    vm->config = *config;
    vm->config.max_memory = memory_limit;
    vm->memory_used = vm->memory_peak = sizeof(*vm);
    if (!vm->config.max_depth) vm->config.max_depth = 64;
    if (!vm->config.max_slots) vm->config.max_slots = 16384;
    if (!vm->config.max_instructions) vm->config.max_instructions = 10000000;
    vm->classes = 0;
    vm->depth = vm->used_slots = 0;
    vm->remaining = 0;
    vm->heap_limit = config->max_heap ? config->max_heap : memory_limit;
    vm->slots = (int32_t *)jbv_alloc(vm, (size_t)vm->config.max_slots * sizeof(int32_t));
    if (!vm->slots) { config->free(config->allocator_user, vm); return JBV_OUT_OF_MEMORY; }
    vm->slot_refs = (uint8_t *)jbv_alloc(vm, vm->config.max_slots);
    if (!vm->slot_refs) { (void)jbv_destroy(vm); return JBV_OUT_OF_MEMORY; }
    status = jbv_bootstrap(vm);
    if (status != JBV_OK) { (void)jbv_destroy(vm); return status; }
    *out = vm;
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_destroy(JbvVM *vm) {
    JbvClass *c, *next;
    if (!vm) return JBV_BAD_ARGUMENT;
    if (vm->depth) return JBV_BUSY;
    jbv_free_heap(vm);
    jbv_free(vm, vm->monitors);
    for (c = vm->classes; c; c = next) { next = c->next; jbv_free_class(vm, c); }
    jbv_free(vm, vm->library.data);
    jbv_free(vm, vm->app.data);
    jbv_free(vm, vm->slots);
    jbv_free(vm, vm->slot_refs);
    vm->config.free(vm->config.allocator_user, vm);
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_load_jar(JbvVM *vm, const void *bytes, size_t size) {
    if (!vm || !bytes || vm->app.data) return JBV_BAD_ARGUMENT;
    if (vm->depth) return JBV_BUSY;
    return jbv_archive_open(vm, &vm->app, (const uint8_t *)bytes, size, 1);
}
JBV_API JbvStatus JBV_CALL jbv_load_class(JbvVM *vm, const void *bytes, size_t size) {
    JbvClass *c = 0;
    JbvStatus status;
    if (!vm || !bytes) return JBV_BAD_ARGUMENT;
    if (vm->depth) return JBV_BUSY;
    status = jbv_parse(vm, bytes, size, &c);
    if (status != JBV_OK) return status;
    /* Built-in layouts are owned by the runtime, including before lazy creation. */
    status = jbv_classpath_find(vm, c->name, 0, 0);
    if (status != JBV_OK && status != JBV_NOT_FOUND) { jbv_free_class(vm, c); return status; }
    if (jbv_find_class(vm, c->name) || jbv_library_id(c->name) || status == JBV_OK || jbv_exception_name(c->name) ||
        jbv_archive_find(&vm->app, c->name, 0, 0) == JBV_OK) {
        jbv_free_class(vm, c); return JBV_LINKAGE_ERROR;
    }
    c->next = vm->classes;
    vm->classes = c;
    return JBV_OK;
}
static JbvStatus bind_native(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvNative callback, JbvNativeSlots wide, void *user) {
    JbvClass *c;
    JbvMethod *m;
    if (!vm || !class_name || !name || !descriptor || (!callback && !wide)) return JBV_BAD_ARGUMENT;
    if (vm->depth) return JBV_BUSY;
    c = jbv_find_class(vm, jbv_text(class_name));
    if (!c) { JbvStatus status = jbv_lazy_class(vm, jbv_text(class_name), &c); if (status != JBV_OK) return status; }
    m = jbv_find_method(c, jbv_text(name), jbv_text(descriptor));
    if (!m) return JBV_NOT_FOUND;
    if (!(m->flags & JBV_NATIVE) || m->intrinsic) return JBV_LINKAGE_ERROR;
    if (!(m->flags & JBV_STATIC)) return JBV_UNSUPPORTED_FEATURE;
    if (!wide && m->result_kind && jbv_width((uint8_t)(m->result_kind - 1)) == 2) return JBV_UNSUPPORTED_FEATURE;
    m->flags &= (uint16_t)~JBV_TYPED_NATIVE;
    m->native = callback;
    m->native_slots = wide;
    m->native_user = user;
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_bind_native(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvNative callback, void *user) {
    return bind_native(vm, class_name, name, descriptor, callback, 0, user);
}
JBV_API JbvStatus JBV_CALL jbv_bind_native_slots(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, JbvNativeSlots callback, void *user) {
    return bind_native(vm, class_name, name, descriptor, 0, callback, user);
}
JBV_GC JBV_API JbvStatus JBV_CALL jbv_call(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, const int32_t *args,
    uint16_t count, int32_t *result) {
    uint64_t value = 0;
    uint16_t expected;
    int returns;
    JbvStatus status;
    if (!descriptor || !result) return JBV_BAD_ARGUMENT;
    status = jbv_signature(jbv_text(descriptor), &expected, &returns);
    if (status != JBV_OK) return status;
    if (returns && jbv_width((uint8_t)(returns - 1)) == 2) return JBV_UNSUPPORTED_FEATURE;
    status = jbv_call_slots(vm, class_name, name, descriptor, args, count, &value);
    if (status == JBV_OK) *result = jbv_i32((uint32_t)value);
    return status;
}
JBV_GC JBV_API JbvStatus JBV_CALL jbv_call_slots(JbvVM *vm, const char *class_name,
    const char *name, const char *descriptor, const int32_t *args,
    uint16_t count, uint64_t *result) {
    JbvMethodId id;
    JbvStatus status;
    if (!vm || !result || (count && !args)) return JBV_BAD_ARGUMENT;
    jbv_begin_call(vm);
    status = jbv_resolve_method(vm, class_name, name, descriptor, &id);
    if (status != JBV_OK) return status;
    if (!(((JbvMethod *)id.method)->flags & JBV_STATIC)) return JBV_UNSUPPORTED_FEATURE;
    return jbv_invoke(vm, &id, args, count, result);
}

JBV_API const char *JBV_CALL jbv_status_string(JbvStatus status) {
    switch (status) {
    case JBV_OK: return "ok";
    case JBV_BAD_ARGUMENT: return "bad argument";
    case JBV_OUT_OF_MEMORY: return "out of memory";
    case JBV_BAD_CLASS: return "malformed class or bytecode";
    case JBV_UNSUPPORTED_VERSION: return "unsupported class version (requires non-preview Java 25)";
    case JBV_INDY_DISABLED: return "invokedynamic is disabled";
    case JBV_UNSUPPORTED_FEATURE: return "feature is not implemented in this slice";
    case JBV_NOT_FOUND: return "class or member not found";
    case JBV_LINKAGE_ERROR: return "linkage or class initialization error";
    case JBV_DIVIDE_BY_ZERO: return "integer division by zero";
    case JBV_LIMIT_EXCEEDED: return "execution resource limit exceeded";
    case JBV_BUSY: return "VM is executing";
    case JBV_NULL_REFERENCE: return "null reference";
    case JBV_ARRAY_BOUNDS: return "array index out of bounds";
    case JBV_NEGATIVE_ARRAY_SIZE: return "negative array size";
    case JBV_ARRAY_STORE: return "incompatible array element type";
    case JBV_CLASS_CAST: return "incompatible reference type";
    case JBV_BAD_REFERENCE: return "invalid or stale reference handle";
    case JBV_MONITOR_STATE: return "monitor is not owned by this execution thread";
    case JBV_ILLEGAL_STATE: return "illegal state";
    case JBV_NATIVE_ERROR: return "native operation failed";
    case JBV_EXCEPTION: return "uncaught Java exception";
    default: return "unknown status";
    }
}

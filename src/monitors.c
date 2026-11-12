#include "library.h"
#if !defined(_M_IX86)   /* monitors_x86.asm; this is the reference */

/* One host thread owns a VM. These are reentrant Java monitors, not OS mutexes.
 * Each acquisition is one table entry keyed by object ref or by class (static
 * synchronized / Class objects), remembering the acquiring frame so resource-limit
 * unwinding releases locks even when compiler-generated finally cannot execute.
 * The depth of a monitor is its entry count, so objects need no header space. */
static int same(const JbvMonitor *m, int32_t ref, const JbvClass *type) { return type ? m->type == type : m->ref == ref && !m->type; }
JbvStatus jbv_monitor(JbvVM *vm, JbvClass *type, int32_t ref, int action) {
    JbvObject *o;
    JbvStatus status;
    uint32_t i;
    if (!type) {
        status = jbv_object(vm, ref, &o);
        if (status != JBV_OK) return status;
        if (o->type->builtin == B_CLASS) {
            type = (JbvClass *)(uintptr_t)jbv_slot_bits(jbv_data(o), JBV_LONG);
            if (!type) return JBV_BAD_REFERENCE;
        }
    }
    if (type) ref = 0;
    if (action <= 0) {
        /* Structured locking exits an acquisition in the current frame first. */
        for (i = vm->monitor_capacity; i--;) if ((vm->monitors[i].ref || vm->monitors[i].type) && same(&vm->monitors[i], ref, type)) {
            uint32_t j;
            if (!action) return JBV_OK;
            for (j = i + 1; j--;) if ((vm->monitors[j].ref || vm->monitors[j].type) && same(&vm->monitors[j], ref, type) && vm->monitors[j].frame == vm->frames) { i = j; break; }
            vm->monitors[i].ref = 0; vm->monitors[i].type = 0; vm->monitors[i].frame = 0;
            return JBV_OK;
        }
        return JBV_MONITOR_STATE;
    }
    for (i = 0; i < vm->monitor_capacity && (vm->monitors[i].ref || vm->monitors[i].type); ++i) {}
    if (i == vm->monitor_capacity) {
        uint32_t size = i ? i * 2 : 8, j;
        JbvMonitor *entries;
        if (size > vm->config.max_slots) size = vm->config.max_slots;
        if (size <= i) return JBV_LIMIT_EXCEEDED;
        entries = (JbvMonitor *)jbv_alloc(vm, size * sizeof(*entries));
        if (!entries) return JBV_OUT_OF_MEMORY;
        for (j = 0; j < i; ++j) entries[j] = vm->monitors[j];
        jbv_free(vm, vm->monitors); vm->monitors = entries; vm->monitor_capacity = size;
    }
    vm->monitors[i].ref = ref; vm->monitors[i].type = type; vm->monitors[i].frame = vm->frames;
    if (vm->frames) vm->frames->has_monitors = 1;
    return JBV_OK;
}
void jbv_release_monitors(JbvVM *vm, JbvFrame *frame) {
    uint32_t i;
    for (i = 0; i < vm->monitor_capacity; ++i) {
        JbvMonitor *entry = &vm->monitors[i];
        if ((entry->ref || entry->type) && entry->frame == frame) { entry->ref = 0; entry->type = 0; entry->frame = 0; }
    }
}
#endif

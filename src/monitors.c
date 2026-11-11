#include "library.h"

/* One host thread owns a VM. These are reentrant Java monitors, not OS mutexes.
 * Entries remember the acquiring frame so resource-limit unwinding releases
 * locks even when Java's compiler-generated finally cannot execute. */
JbvStatus jbv_monitor(JbvVM *vm, JbvClass *type, int32_t ref, int action) {
    JbvObject *o;
    JbvStatus status;
    uint16_t *counter;
    uint32_t i;
    if (!type) {
        status = jbv_object(vm, ref, &o);
        if (status != JBV_OK) return status;
        if (o->type->builtin == B_CLASS) {
            type = (JbvClass *)(uintptr_t)jbv_slot_bits(jbv_data(o), JBV_LONG);
            if (!type) return JBV_BAD_REFERENCE;
        }
        counter = type ? &type->monitor_depth : &o->monitor_depth;
    } else counter = &type->monitor_depth;
    if (action <= 0) {
        if (!*counter) return JBV_MONITOR_STATE;
        if (!action) return JBV_OK;
        /* Structured locking exits an acquisition in the current frame. Reused
         * free entries are not ordered by acquisition time. */
        for (i = vm->monitor_capacity; i--;) if (vm->monitors[i].counter == counter && vm->monitors[i].frame == vm->frames) {
            --*counter; vm->monitors[i].counter = 0; return JBV_OK;
        }
        for (i = vm->monitor_capacity; i--;) if (vm->monitors[i].counter == counter) {
            --*counter; vm->monitors[i].counter = 0; return JBV_OK;
        }
        return JBV_MONITOR_STATE;
    }
    if (*counter == UINT16_MAX) return JBV_LIMIT_EXCEEDED;
    for (i = 0; i < vm->monitor_capacity && vm->monitors[i].counter; ++i) {}
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
    vm->monitors[i].counter = counter; vm->monitors[i].frame = vm->frames;
    vm->frames->has_monitors = 1; ++*counter;
    return JBV_OK;
}
void jbv_release_monitors(JbvVM *vm, JbvFrame *frame) {
    uint32_t i;
    for (i = 0; i < vm->monitor_capacity; ++i) {
        JbvMonitor *entry = &vm->monitors[i];
        if (entry->counter && entry->frame == frame) { --*entry->counter; entry->counter = 0; }
    }
}

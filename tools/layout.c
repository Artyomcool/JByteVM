/* Prints the x86 struct offsets the assembly files use (tools/gen_layout.py builds it once
 * per profile): "NAME offset" lines; the generator writes src/layout_x86.inc and the
 * static checks in src/layout_check.h from them. */
#include <stdio.h>
#include <stddef.h>
#include "internal.h"
#define F(T, f, name) printf("%s %u " #T " " #f "\n", name, (unsigned)offsetof(T, f))
#define Z(T, name) printf("%s %u " #T " sizeof\n", name, (unsigned)sizeof(T))
int main(void) {
    Z(JbvText, "TEXT_SIZEOF"); F(JbvText, data, "TEXT_DATA"); F(JbvText, size, "TEXT_SIZE");
    Z(JbvConstant, "CP_SIZEOF"); F(JbvConstant, tag, "CP_TAG"); F(JbvConstant, a, "CP_A"); F(JbvConstant, b, "CP_B");
    F(JbvConstant, bits, "CP_BITS"); F(JbvConstant, bits_hi, "CP_BITS_HI"); F(JbvConstant, text, "CP_TEXT");
    Z(JbvField, "FIELD_SIZEOF"); F(JbvField, flags, "FIELD_FLAGS"); F(JbvField, constant, "FIELD_CONSTANT");
    F(JbvField, name, "FIELD_NAME"); F(JbvField, descriptor, "FIELD_DESCRIPTOR"); F(JbvField, value, "FIELD_VALUE");
    F(JbvField, value_hi, "FIELD_VALUE_HI"); F(JbvField, slot, "FIELD_SLOT");
    Z(JbvMethod, "M_SIZEOF"); F(JbvMethod, flags, "M_FLAGS"); F(JbvMethod, max_stack, "M_MAX_STACK"); F(JbvMethod, max_locals, "M_MAX_LOCALS");
    F(JbvMethod, name, "M_NAME"); F(JbvMethod, descriptor, "M_DESCRIPTOR"); F(JbvMethod, code, "M_CODE");
    F(JbvMethod, exception_table, "M_EXCEPTIONS"); F(JbvMethod, handlers, "M_HANDLERS"); F(JbvMethod, line_count, "M_LINE_COUNT");
    F(JbvMethod, lines, "M_LINES"); F(JbvMethod, accessor, "M_ACCESSOR");
    Z(JbvClass, "C_SIZEOF"); F(JbvClass, image, "C_IMAGE"); F(JbvClass, pool, "C_POOL"); F(JbvClass, pool_size, "C_POOL_SIZE");
    F(JbvClass, method_count, "C_METHOD_COUNT"); F(JbvClass, field_count, "C_FIELD_COUNT"); F(JbvClass, name, "C_NAME");
    F(JbvClass, super_name, "C_SUPER_NAME"); F(JbvClass, source_file, "C_SOURCE_FILE"); F(JbvClass, methods, "C_METHODS");
    F(JbvClass, fields, "C_FIELDS"); F(JbvClass, flags, "C_FLAGS"); F(JbvClass, interface_count, "C_INTERFACE_COUNT");
    F(JbvClass, interface_indices, "C_INTERFACE_INDICES");
    F(JbvClass, next, "C_NEXT"); F(JbvClass, super, "C_SUPER"); F(JbvClass, instance_slots, "C_INSTANCE_SLOTS");
    F(JbvClass, link_state, "C_LINK_STATE"); F(JbvClass, init_state, "C_INIT_STATE");
    F(JbvMethod, intrinsic, "M_INTRINSIC"); F(JbvMethod, native, "M_NATIVE"); F(JbvMethod, native_user, "M_NATIVE_USER");
    Z(JbvFrame, "FR_SIZEOF"); F(JbvFrame, previous, "FR_PREVIOUS"); F(JbvFrame, owner, "FR_OWNER"); F(JbvFrame, method, "FR_METHOD");
    F(JbvFrame, pc, "FR_PC");
    F(JbvVM, classes, "VM_CLASSES"); F(JbvVM, throwable_class, "VM_THROWABLE"); F(JbvVM, trace_element_class, "VM_TRACE_ELEMENT");
    F(JbvVM, throwable_init, "VM_THROWABLE_INIT"); F(JbvVM, frames, "VM_FRAMES"); F(JbvVM, exception, "VM_EXCEPTION");
    F(JbvVM, emergency_oom, "VM_EMERGENCY_OOM"); F(JbvVM, exception_status, "VM_EXCEPTION_STATUS"); F(JbvVM, heap_limit, "VM_HEAP_LIMIT");
    F(JbvVM, handles, "VM_HANDLES");
    F(JbvVM, config.alloc, "VM_ALLOC"); F(JbvVM, config.free, "VM_FREE"); F(JbvVM, config.allocator_user, "VM_ALLOC_USER");
    F(JbvVM, config.max_memory, "VM_MAX_MEMORY"); F(JbvVM, memory_used, "VM_MEMORY_USED"); F(JbvVM, memory_peak, "VM_MEMORY_PEAK");
    F(JbvVM, class_cache, "VM_CLASS_CACHE"); F(JbvVM, library, "VM_LIBRARY"); F(JbvVM, app, "VM_APP");
    F(JbvClass, primitive, "C_PRIMITIVE"); F(JbvClass, ref_slots, "C_REF_SLOTS"); F(JbvClass, root_slots, "C_ROOT_SLOTS");
    F(JbvClass, interfaces, "C_INTERFACES"); F(JbvClass, builtin, "C_BUILTIN"); F(JbvClass, array_kind, "C_ARRAY_KIND"); F(JbvClass, component, "C_COMPONENT");
    F(JbvVM, interned, "VM_INTERNED"); F(JbvVM, handle_capacity, "VM_HANDLE_CAPACITY"); F(JbvVM, generations, "VM_GENERATIONS");
    Z(JbvConfig, "CFG_SIZEOF"); F(JbvConfig, alloc, "CFG_ALLOC"); F(JbvConfig, free, "CFG_FREE"); F(JbvConfig, allocator_user, "CFG_USER");
    F(JbvConfig, max_slots, "CFG_MAX_SLOTS"); F(JbvConfig, max_depth, "CFG_MAX_DEPTH"); F(JbvConfig, max_instructions, "CFG_MAX_INSTRUCTIONS");
    F(JbvConfig, max_memory, "CFG_MAX_MEMORY"); F(JbvConfig, max_heap, "CFG_MAX_HEAP");
    Z(JbvVM, "VM_SIZEOF"); F(JbvVM, config, "VM_CONFIG"); F(JbvVM, slots, "VM_SLOTS"); F(JbvVM, slot_refs, "VM_SLOT_REFS");
    F(JbvVM, depth, "VM_DEPTH"); F(JbvVM, monitors, "VM_MONITORS");
    F(JbvMethod, native_slots, "M_NATIVE_SLOTS"); F(JbvMethod, result_kind, "M_RESULT_KIND");
#if JBV_PROFILE_FULL
    F(JbvField, attributes, "FIELD_ATTRIBUTES"); F(JbvMethod, attributes, "M_ATTRIBUTES"); F(JbvClass, attributes, "C_ATTRIBUTES");
#endif
    return 0;
}

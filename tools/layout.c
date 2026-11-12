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
#if JBV_PROFILE_FULL
    F(JbvField, attributes, "FIELD_ATTRIBUTES"); F(JbvMethod, attributes, "M_ATTRIBUTES"); F(JbvClass, attributes, "C_ATTRIBUTES");
#endif
    return 0;
}

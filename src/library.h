#ifndef JBV_LIBRARY_H
#define JBV_LIBRARY_H
#include "internal.h"

enum { B_NONE, B_OBJECT, B_CLASS, B_STRING, B_BUILDER, B_ABUILDER, B_NUMBER, B_SEQUENCE,
    B_COMPARABLE, B_APPENDABLE, B_BOOLEAN, B_BYTE, B_CHAR, B_SHORT, B_INT,
    B_LONG, B_FLOAT, B_DOUBLE, B_VOID };
enum { O_INIT, O_EQUALS, O_HASH, O_CLASS, O_TEXT, O_NOTIFY, O_CLONE,
    C_NAME, C_ARRAY, C_PRIMITIVE, C_INTERFACE, C_SUPER, C_COMPONENT, C_ASSIGN,
    C_INSTANCE, C_CAST, C_TEXT, C_REFLECT,
    S_INIT, S_LENGTH, S_EMPTY, S_CHAR, S_EQUALS, S_HASH, S_TEXT, S_COMPARE,
    S_SUBSTRING, S_CHARS, S_GET_CHARS, S_CONCAT, S_INTERN, S_STARTS, S_ENDS,
    S_INDEX, S_LAST_INDEX, S_VALUE, S_TRIM, S_REPLACE, S_CONTAINS, S_REPEAT,
    A_INIT, A_APPEND, A_LENGTH, A_CAPACITY, A_ENSURE, A_SET_LENGTH, A_CHAR,
    A_SET_CHAR, A_TEXT, A_SUBSTRING, A_REVERSE, A_COMPARE, A_INSERT, A_DELETE, A_DELETE_CHAR, A_REPLACE, A_CODEPOINT, A_TRIM };
typedef struct JbvTextView { uint16_t *data; uint32_t length; } JbvTextView;
JbvStatus jbv_string_view(JbvVM *vm, int32_t ref, JbvTextView *out);
JbvStatus jbv_string_alloc(JbvVM *vm, uint32_t length, int32_t *ref, uint16_t **data);
JbvStatus jbv_string_mutf(JbvVM *vm, JbvText text, int32_t *out);
JbvStatus jbv_string_intern(JbvVM *vm, int32_t ref, int32_t *out);
JbvStatus jbv_object_text(JbvVM *vm, int32_t ref, int32_t *out);
JbvStatus jbv_text_native(JbvVM *vm, uint32_t op, uint8_t kind, const int32_t *args, uint16_t count, uint64_t *out);
uint32_t jbv_integer_text(uint64_t magnitude, int negative, uint32_t radix, uint16_t *out);
uint32_t jbv_decimal_text(uint64_t bits, int single, uint16_t *out);
#endif

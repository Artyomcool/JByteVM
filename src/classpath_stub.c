#include "classpath.h"

JbvStatus jbv_classpath_load(JbvVM *vm, JbvText name, JbvClass **out) { (void)vm; (void)name; (void)out; return JBV_NOT_FOUND; }
JbvStatus jbv_constant(JbvVM *vm, JbvClass *owner, uint16_t index, uint64_t *out, uint8_t *kind) {
    (void)vm; (void)owner; (void)index; (void)out; (void)kind; return JBV_UNSUPPORTED_FEATURE;
}
JbvStatus jbv_polymorphic(JbvVM *vm, int32_t handle, JbvText descriptor, const int32_t *args, int exact, uint64_t *out) {
    (void)vm; (void)handle; (void)descriptor; (void)args; (void)exact; (void)out; return JBV_UNSUPPORTED_FEATURE;
}
#if defined(_M_IX86)   /* the assembly calls it; C sees the macro */
#undef jbv_classpath_find
JbvStatus jbv_classpath_find(JbvVM *vm, JbvText name, const uint8_t **data, uint32_t *size) {
    (void)vm; (void)name; (void)data; (void)size; return JBV_NOT_FOUND;
}
#else
JbvStatus jbv_capture_trace(JbvVM *vm, int32_t *out) { (void)vm; (void)out; return JBV_UNSUPPORTED_FEATURE; }
#endif

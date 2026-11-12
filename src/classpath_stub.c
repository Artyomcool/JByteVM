#include "classpath.h"
#if !defined(_M_IX86)   /* core_x86.asm; this is the reference */
JbvStatus jbv_classpath_load(JbvVM *vm, JbvText name, JbvClass **out) { (void)vm; (void)name; (void)out; return JBV_NOT_FOUND; }
JbvStatus jbv_constant(JbvVM *vm, JbvClass *owner, uint16_t index, uint64_t *out, uint8_t *kind) {
    (void)vm; (void)owner; (void)index; (void)out; (void)kind; return JBV_UNSUPPORTED_FEATURE;
}
JbvStatus jbv_polymorphic(JbvVM *vm, int32_t handle, JbvText descriptor, const int32_t *args, int exact, uint64_t *out) {
    (void)vm; (void)handle; (void)descriptor; (void)args; (void)exact; (void)out; return JBV_UNSUPPORTED_FEATURE;
}
JbvStatus jbv_capture_trace(JbvVM *vm, int32_t *out) { (void)vm; (void)out; return JBV_UNSUPPORTED_FEATURE; }
#endif

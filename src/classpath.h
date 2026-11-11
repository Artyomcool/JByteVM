#ifndef JBV_CLASSPATH_H
#define JBV_CLASSPATH_H
#include "library.h"
/* The class library is an ordinary deflated JAR embedded as read-only data. */
extern const uint8_t jbv_library_jar[];
extern const uint32_t jbv_library_jar_size;
JbvStatus jbv_classpath_load(JbvVM *vm, JbvText name, JbvClass **out);
JBV_GC JbvStatus jbv_parse_fp(JbvVM *vm, int32_t string, int single, uint64_t *out);
JBV_GC JbvStatus jbv_primitive_mirror(JbvVM *vm, uint8_t kind, int32_t *out);
JbvClass *jbv_mirror_type(JbvVM *vm, int32_t ref);
JbvStatus jbv_text_bytes(JbvVM *vm, int32_t ref, JbvText *out);
JBV_GC JbvStatus jbv_type_class(JbvVM *vm, JbvText descriptor, JbvClass **out);
JBV_GC JbvStatus jbv_box(JbvVM *vm, uint8_t code, uint64_t bits, int32_t *out);
JbvStatus jbv_unbox(JbvVM *vm, int32_t ref, uint8_t target, int explicit_cast, uint64_t *out);
JbvStatus jbv_from_object(JbvVM *vm, int32_t ref, JbvText type, uint64_t *out);
JBV_GC JbvStatus jbv_reflect_class(JbvVM *vm, uint32_t op, const int32_t *a, uint64_t *out);
JBV_GC JbvStatus JBV_CALL jbv_reflect_native(JbvVM *vm, void *user, const int32_t *a, uint16_t count, uint64_t *out);
const uint8_t *jbv_attribute(JbvClass *owner, const uint8_t *p, const char *key);
JBV_GC JbvStatus jbv_annotation_value(JbvVM *vm, JbvClass *owner, const uint8_t **p, JbvText expected, int32_t *ref);
JBV_GC JbvStatus jbv_annotations(JbvVM *vm, JbvClass *owner, const uint8_t *p, int32_t *ref);
const uint8_t *jbv_skip_annotations(const uint8_t *p);
#endif

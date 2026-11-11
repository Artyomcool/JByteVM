#ifndef JBV_JAR_H
#define JBV_JAR_H
#include "internal.h"
/* Finds entry name+suffix in an in-memory JAR. With out == 0 only checks
 * presence. Otherwise *out is a jbv_alloc buffer owned by the caller. */
JbvStatus jbv_jar_read(JbvVM *vm, const uint8_t *jar, size_t size, JbvText name, const char *suffix, uint8_t **out, size_t *out_size);
#endif

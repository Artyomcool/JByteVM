/* Freestanding compiler helpers: no CRT DLL or startup is required. */
#include <stddef.h>
#include <string.h>
#ifdef _MSC_VER
#pragma function(memcpy, memset)
#endif
void *__cdecl memcpy(void *destination, const void *source, size_t size) {
    volatile unsigned char *out = (volatile unsigned char *)destination;
    const unsigned char *in = (const unsigned char *)source;
    size_t i;
    for (i = 0; i < size; ++i) out[i] = in[i];
    return destination;
}
void *__cdecl memset(void *destination, int value, size_t size) {
    volatile unsigned char *out = (volatile unsigned char *)destination;
    size_t i;
    for (i = 0; i < size; ++i) out[i] = (unsigned char)value;
    return destination;
}

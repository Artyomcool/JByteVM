#include "jbytevm.h"
#include <stdio.h>
#include <stdlib.h>

static void *allocate(void *user, size_t bytes) { (void)user; return malloc(bytes); }
static void release(void *user, void *p) { (void)user; free(p); }

static JbvStatus leaf(JbvVM *vm, void *user, const int32_t *args, uint16_t count, int32_t *result) {
    (void)vm; (void)user;
    if (count != 1) return JBV_BAD_ARGUMENT;
    /* Demo input is deliberately small; VM integer wraparound is tested separately. */
    *result = args[0] * 2;
    return JBV_OK;
}
static JbvStatus bridge(JbvVM *vm, void *user, const int32_t *args, uint16_t count, int32_t *result) {
    (void)user;
    return jbv_call(vm, "Core", "callback", "(I)I", args, count, result);
}
int main(int argc, char **argv) {
    FILE *file = 0;
    long length;
    void *bytes;
    JbvVM *vm = 0;
    JbvConfig config = { allocate, release, 0, 0, 0, 0, 0, 0 };
    JbvStatus status;
    int32_t arg = 7, result = 0;
    if (argc != 2) { fprintf(stderr, "usage: jbytevm-demo Core.class\n"); return 2; }
#ifdef _MSC_VER
    if (fopen_s(&file, argv[1], "rb")) return 2;
#else
    file = fopen(argv[1], "rb");
    if (!file) return 2;
#endif
    if (fseek(file, 0, SEEK_END) || (length = ftell(file)) <= 0 || fseek(file, 0, SEEK_SET)) {
        fclose(file); return 2;
    }
    bytes = malloc((size_t)length);
    if (!bytes) { fclose(file); return 2; }
    if (fread(bytes, 1, (size_t)length, file) != (size_t)length) { free(bytes); fclose(file); return 2; }
    fclose(file);
    status = jbv_create(&config, &vm);
    if (status == JBV_OK) status = jbv_load_class(vm, bytes, (size_t)length);
    free(bytes);
    if (status == JBV_OK) status = jbv_bind_native(vm, "Core", "bridge", "(I)I", bridge, 0);
    if (status == JBV_OK) status = jbv_bind_native(vm, "Core", "leaf", "(I)I", leaf, 0);
    if (status == JBV_OK) status = jbv_call(vm, "Core", "entry", "(I)I", &arg, 1, &result);
    if (status == JBV_OK) printf("%s: %d\n", "native -> Java -> native -> Java -> native", (int)result);
    else fprintf(stderr, "%s\n", jbv_status_string(status));
    if (vm) (void)jbv_destroy(vm);
    return status == JBV_OK && result == 28 ? 0 : 1;
}

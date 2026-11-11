#include "jbytevm_native.h"
#include <stdio.h>
#include <stdlib.h>

static void *JBV_CALL allocate(void *user, size_t bytes) { (void)user; return malloc(bytes); }
static void JBV_CALL release(void *user, void *p) { (void)user; free(p); }
typedef struct CallbackContext {
    JbvVM *vm;
    JbvMethodId method;
    JbvStatus status;
} CallbackContext;

/* An ordinary typed native API and callback. Their calling conventions are
 * handled by the host C compiler; the VM generates no machine code. */
typedef int64_t (__stdcall *TypedCallback)(void *, int64_t, double, int);
static __declspec(noinline) int64_t __stdcall typed_library(TypedCallback callback, void *context, int64_t value, double scale, int n) {
    return callback(context, value, scale, n);
}
static int64_t __stdcall typed_callback(void *user, int64_t value, double scale, int n) {
    CallbackContext *context = (CallbackContext *)user;
    JbvValue result;
    context->status = jbv_invoke_args(context->vm, &context->method, &result, value, scale, n);
    return context->status == JBV_OK ? result.j : 0;
}
static int64_t JBV_CALL bridge(JbvVM *vm, int64_t value, double scale, int32_t n) {
    CallbackContext *context = (CallbackContext *)jbv_native_context(vm);
    int64_t result;
    context->status = jbv_collect(vm);
    if (context->status != JBV_OK) { jbv_native_fail(vm, context->status); return 0; }
    result = typed_library(typed_callback, context, value, scale, n);
    if (context->status != JBV_OK) jbv_native_fail(vm, context->status);
    return result;
}
static int64_t JBV_CALL leaf(JbvVM *vm, int64_t value, double scale, int32_t n) {
    (void)vm;
    return value + (int64_t)(scale * n);
}
static const JbvNativeEntry natives[] = {
    { "bridge", "(JDI)J", JBV_NATIVE_FN(bridge) },
    { "leaf", "(JDI)J", JBV_NATIVE_FN(leaf) }
};
int main(int argc, char **argv) {
    FILE *file = 0;
    long length;
    void *bytes;
    JbvVM *vm = 0;
    JbvConfig config = { allocate, release, 0, 0, 0, 0, 0, 0 };
    CallbackContext context = {0};
    JbvStatus status;
    int32_t n = 7;
    uint64_t result = 0;
    if (argc != 2) { fprintf(stderr, "usage: jbytevm-native-demo NativeDemo.class\n"); return 2; }
    if (fopen_s(&file, argv[1], "rb")) return 2;
    if (fseek(file, 0, SEEK_END) || (length = ftell(file)) <= 0 || fseek(file, 0, SEEK_SET)) { fclose(file); return 2; }
    bytes = malloc((size_t)length);
    if (!bytes) { fclose(file); return 2; }
    if (fread(bytes, 1, (size_t)length, file) != (size_t)length) { free(bytes); fclose(file); return 2; }
    fclose(file);
    status = jbv_create(&config, &vm);
    if (status == JBV_OK) status = jbv_load_class(vm, bytes, (size_t)length);
    free(bytes);
    context.vm = vm;
    if (status == JBV_OK) status = jbv_resolve_method(vm, "NativeDemo", "callback", "(JDI)J", &context.method);
    if (status == JBV_OK) status = jbv_register_natives(vm, "NativeDemo", natives, 2, &context);
    if (status == JBV_OK) status = jbv_call_slots(vm, "NativeDemo", "entry", "(I)J", &n, 1, &result);
    if (status == JBV_OK) printf("typed native -> Java -> native: 0x%llx\n", (unsigned long long)result);
    else fprintf(stderr, "%s\n", jbv_status_string(status));
    if (vm) (void)jbv_destroy(vm);
    return status == JBV_OK && result == UINT64_C(0x1234000000000019) ? 0 : 1;
}

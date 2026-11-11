#include "jbytevm_native.h"
#include "typed_max_args.inc"
#define EXPORT __declspec(dllexport)

static uint8_t JBV_CALL invert(JbvVM *vm, uint8_t x) { (void)vm; return (uint8_t)(x ^ 1); }
static int8_t JBV_CALL byte_value(JbvVM *vm, int8_t x) { (void)vm; return x; }
static uint16_t JBV_CALL char_value(JbvVM *vm, uint16_t x) { (void)vm; return x; }
static int16_t JBV_CALL short_value(JbvVM *vm, int16_t x) { (void)vm; return x; }
static int32_t JBV_CALL add_int(JbvVM *vm, int32_t x, int32_t y) { (void)vm; return (int32_t)((uint32_t)x + (uint32_t)y); }
static int32_t JBV_CALL subtract(JbvVM *vm, int32_t x, int32_t y) { (void)vm; return (int32_t)((uint32_t)x - (uint32_t)y); }
static int64_t JBV_CALL add_long(JbvVM *vm, int64_t x, int64_t y) { (void)vm; return (int64_t)((uint64_t)x + (uint64_t)y); }
static float JBV_CALL float_value(JbvVM *vm, float x) { (void)vm; return x + 0.25f; }
static double JBV_CALL double_value(JbvVM *vm, double x) { (void)vm; return x + 0.5; }
static JbvRef JBV_CALL identity(JbvVM *vm, JbvRef x) { jbv_collect(vm); return x; }
static int32_t JBV_CALL context(JbvVM *vm) { return (int32_t)(uintptr_t)jbv_native_context(vm); }
static void JBV_CALL nothing(JbvVM *vm) { jbv_collect(vm); }
static int64_t JBV_CALL mixed(JbvVM *vm, int32_t i, int64_t j, float f, double d,
    JbvRef ref, int8_t b, uint16_t c, int16_t s, uint8_t z) {
    JbvStatus status = jbv_collect(vm);
    if (status != JBV_OK) { jbv_native_fail(vm, status); return 0; }
    return j + i + (int64_t)f + (int64_t)d + (ref ? 100 : 0) + b + c + s + z;
}
static void JBV_CALL throw_it(JbvVM *vm, JbvRef ref) { jbv_throw(vm, ref); jbv_collect(vm); }
static void JBV_CALL fail(JbvVM *vm, int32_t status) { jbv_native_fail(vm, (JbvStatus)status); }
static int32_t JBV_CALL outer(JbvVM *vm, uint8_t recover) {
    void *before = jbv_native_context(vm);
    JbvMethodId method;
    JbvValue value = {0};
    int32_t inner;
    JbvStatus status = jbv_resolve_method(vm, "TypedInner", "context", "()I", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value);
    if (status != JBV_OK) { jbv_native_fail(vm, status); return 0; }
    inner = value.i;
    status = jbv_resolve_method(vm, "TypedInner", "fail", "(I)V", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value, (int32_t)JBV_LIMIT_EXCEEDED);
    if (before != jbv_native_context(vm)) { jbv_native_fail(vm, JBV_NATIVE_ERROR); return 0; }
    if (status != JBV_LIMIT_EXCEEDED) { jbv_native_fail(vm, JBV_NATIVE_ERROR); return 0; }
    if (!recover) { jbv_native_fail(vm, status); return 0; }
    return inner ^ (int32_t)(uintptr_t)before;
}
static int32_t JBV_CALL again(JbvVM *vm, int32_t n) {
    JbvMethodId method;
    JbvValue value = {0};
    JbvStatus status = jbv_resolve_method(vm, "TypedNatives", "recurse", "(I)I", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value, n);
    if (status != JBV_OK) { jbv_native_fail(vm, status); return 0; }
    return value.i;
}
static JbvRef JBV_CALL bad_reference(JbvVM *vm) { (void)vm; return INT32_MAX; }
static float JBV_CALL special_float(JbvVM *vm, int32_t which) {
    JbvValue value = {0};
    (void)vm;
    value.bits = which == 0 ? UINT32_C(0x80000000) : which == 1 ? UINT32_C(0x7f800000) : UINT32_C(0x7fc12345);
    return value.f;
}
static double JBV_CALL special_double(JbvVM *vm, int32_t which) {
    JbvValue value = {0};
    (void)vm;
    value.bits = which == 0 ? UINT64_C(0x8000000000000000) : which == 1 ? UINT64_C(0x7ff0000000000000) : UINT64_C(0x7ff8123456789abc);
    return value.d;
}
static int32_t JBV_CALL rebind(JbvVM *vm) {
    JbvNativeEntry entry = { "add", "(II)I", JBV_NATIVE_FN(subtract) };
    return (int32_t)jbv_register_natives(vm, "TypedNatives", &entry, 1, 0);
}
static int32_t JBV_CALL invoke_convenience(JbvVM *vm) {
    JbvMethodId method;
    JbvValue value = {0};
    JbvRef array = 0, object = 0;
    uint64_t element = 7;
    JbvStatus status = jbv_new_array(vm, "[I", 1, &array);
    if (status == JBV_OK) status = jbv_array_write(vm, array, 0, 1, &element);
    if (status == JBV_OK) status = jbv_alloc_object(vm, "java/lang/Object", &object);
    if (status == JBV_OK) status = jbv_resolve_method(vm, "TypedNatives", "javaMixed", "(JDF[ILjava/lang/Object;BCSZ)J", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value, INT64_C(0x1234000000000000), 13.5, 2.5f, array, object, (int8_t)-5, (uint16_t)40000, (int16_t)-1000, (uint8_t)1);
    if (status == JBV_OK && value.j != INT64_C(0x12340000000098ce)) status = JBV_NATIVE_ERROR;
    if (status == JBV_OK) status = jbv_resolve_method(vm, "TypedNatives", "javaFloat", "(F)F", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value, 2.5f);
    if (status == JBV_OK && value.f != 2.75f) status = JBV_NATIVE_ERROR;
    if (status == JBV_OK) status = jbv_resolve_method(vm, "TypedNatives", "javaDouble", "(D)D", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value, 3.25);
    if (status == JBV_OK && value.d != 3.75) status = JBV_NATIVE_ERROR;
    if (status == JBV_OK) status = jbv_resolve_method(vm, "TypedNatives", "javaReference", "(Ljava/lang/Object;)Ljava/lang/Object;", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value, object);
    if (status == JBV_OK) {
        if (value.ref != object) status = JBV_NATIVE_ERROR;
        jbv_release(vm, value.ref);
    }
    if (status == JBV_OK) status = jbv_resolve_method(vm, "TypedNatives", "javaVoid", "()V", &method);
    if (status == JBV_OK) status = jbv_invoke_args(vm, &method, &value);
    if (status == JBV_OK && value.bits != 0) status = JBV_NATIVE_ERROR;
    jbv_release(vm, object); jbv_release(vm, array);
    if (status != JBV_OK) { jbv_native_fail(vm, status); return 0; }
    return 42;
}

static const JbvNativeEntry entries[] = {
    { "invert", "(Z)Z", JBV_NATIVE_FN(invert) },
    { "byteValue", "(B)B", JBV_NATIVE_FN(byte_value) },
    { "charValue", "(C)C", JBV_NATIVE_FN(char_value) },
    { "shortValue", "(S)S", JBV_NATIVE_FN(short_value) },
    { "add", "(II)I", JBV_NATIVE_FN(add_int) },
    { "add", "(JJ)J", JBV_NATIVE_FN(add_long) },
    { "floatValue", "(F)F", JBV_NATIVE_FN(float_value) },
    { "doubleValue", "(D)D", JBV_NATIVE_FN(double_value) },
    { "identity", "(Ljava/lang/Object;)Ljava/lang/Object;", JBV_NATIVE_FN(identity) },
    { "array", "([I)[I", JBV_NATIVE_FN(identity) },
    { "context", "()I", JBV_NATIVE_FN(context) },
    { "nothing", "()V", JBV_NATIVE_FN(nothing) },
    { "mixed", "(IJFDLjava/lang/Object;BCSZ)J", JBV_NATIVE_FN(mixed) },
    { "throwIt", "(Ljava/lang/Throwable;)V", JBV_NATIVE_FN(throw_it) },
    { "fail", "(I)V", JBV_NATIVE_FN(fail) },
    { "outer", "(Z)I", JBV_NATIVE_FN(outer) },
    { "again", "(I)I", JBV_NATIVE_FN(again) },
    { "badReference", "()Ljava/lang/Object;", JBV_NATIVE_FN(bad_reference) },
    { "specialFloat", "(I)F", JBV_NATIVE_FN(special_float) },
    { "specialDouble", "(I)D", JBV_NATIVE_FN(special_double) },
    { "rebind", "()I", JBV_NATIVE_FN(rebind) },
    { "invokeConvenience", "()I", JBV_NATIVE_FN(invoke_convenience) }
};

/* Deliberately poison rounding, precision, DAZ and FTZ at both boundaries. */
static void fp_set(uint16_t cw, uint32_t mx) {
    __asm { fldcw cw }
    __asm { ldmxcsr mx }
}
static void fp_get(uint16_t *cw, uint32_t *mx) {
    __asm { mov eax,cw }
    __asm { fnstcw [eax] }
    __asm { mov eax,mx }
    __asm { stmxcsr [eax] }
}
static int32_t JBV_CALL fp_nested(JbvVM *vm) {
    uint16_t cw;
    uint32_t mx;
    uint64_t result = 0;
    JbvStatus status;
    fp_set(0x087f, 0xdfc0); /* single precision, upward; SSE downward, DAZ/FTZ */
    status = jbv_call_slots(vm, "LibraryValues", "fpProbe", "(DD)I",
        (const int32_t[]){0,0x3ff00000,1,0}, 4, &result);
    fp_get(&cw,&mx);
    if (status != JBV_OK || result != 7 || cw != 0x087f || mx != 0xdfc0) {
        jbv_native_fail(vm, JBV_NATIVE_ERROR); return 0;
    }
    return 42;
}
EXPORT int32_t JBV_CALL typed_fp_environment(JbvVM *vm) {
    uint16_t oldcw, cw;
    uint32_t oldmx, mx;
    uint64_t result = 0;
    JbvStatus status;
    int32_t answer = 0;
    JbvNativeEntry entry = { "fpNested", "()I", JBV_NATIVE_FN(fp_nested) };
    status = jbv_register_natives(vm, "LibraryValues", &entry, 1, 0);
    if (status != JBV_OK) return -1;
    fp_get(&oldcw,&oldmx);
    fp_set(0x0f7f,0xffc0);
    status = jbv_call_slots(vm,"LibraryValues","fpChain","()I",0,0,&result);
    fp_get(&cw,&mx);
    if (status == JBV_OK && result == 42 && cw == 0x0f7f && mx == 0xffc0) answer = 1;
    fp_set(oldcw,oldmx);
    return answer;
}
EXPORT JbvStatus JBV_CALL typed_install(JbvVM *vm, void *user) {
    return jbv_register_natives(vm, "TypedNatives", entries, sizeof(entries) / sizeof(entries[0]), user);
}
EXPORT JbvStatus JBV_CALL typed_install_inner(JbvVM *vm, void *user) {
    JbvNativeEntry inner[] = { entries[10], entries[14] };
    return jbv_register_natives(vm, "TypedInner", inner, 2, user);
}
EXPORT JbvNativeFunction JBV_CALL typed_address(int32_t which) {
    return which == -1 ? JBV_NATIVE_FN(subtract) : entries[(uint32_t)which % (sizeof(entries) / sizeof(entries[0]))].function;
}
EXPORT JbvStatus JBV_CALL typed_install_max(JbvVM *vm) {
    const JbvNativeEntry entry = { "maxArgs", TYPED_MAX_DESCRIPTOR, JBV_NATIVE_FN(max_args) };
    return jbv_register_natives(vm, "TypedMax", &entry, 1, 0);
}

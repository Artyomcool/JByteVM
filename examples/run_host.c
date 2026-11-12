/* Runs `static int run(String[] args)` of a class in an application JAR, with
 * minimal file access for Java tools: jbvhost.Host.read/write/list natives,
 * System.out/err through the host write service, and the exit code from run().
 * Usage: jbytevm-run app.jar pkg/Class [args...] */
#include <jbytevm.h>
#include <jbytevm_native.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

static void *JBV_CALL allocate(void *user, size_t bytes) { (void)user; return malloc(bytes); }
static void JBV_CALL release(void *user, void *p) { (void)user; free(p); }

/* Java String -> malloc'ed NUL-terminated UTF-8. */
static char *utf8(JbvVM *vm, JbvRef text) {
    uint32_t length = 0, bytes = 0;
    char *out;
    if (jbv_string_length(vm, text, &length) != JBV_OK) return 0;
    out = (char *)malloc((size_t)length * 3 + 1);
    if (!out) return 0;
    if (jbv_string_read_utf8(vm, text, out, length * 3, &bytes) != JBV_OK) { free(out); return 0; }
    out[bytes] = 0;
    return out;
}
static JbvStatus JBV_CALL host_write(JbvVM *vm, void *user, JbvRef text, int error) {
    char *s = utf8(vm, text);
    (void)user;
    if (!s) return JBV_OUT_OF_MEMORY;
    fputs(s, error ? stderr : stdout);
    free(s);
    return JBV_OK;
}
static int64_t JBV_CALL clock_now(void *user, int monotonic) {
    LARGE_INTEGER t, f;
    (void)user;
    QueryPerformanceCounter(&t); QueryPerformanceFrequency(&f);
    return monotonic ? (int64_t)((double)t.QuadPart * 1e9 / (double)f.QuadPart) : (int64_t)GetTickCount64();
}
/* Byte array <-> host buffer through the array API (one 64-bit value per element). */
static JbvRef byte_array(JbvVM *vm, const unsigned char *data, size_t n) {
    JbvRef array = 0;
    uint64_t *values = (uint64_t *)malloc((n ? n : 1) * sizeof(uint64_t));
    size_t i;
    if (!values || jbv_new_array(vm, "[B", (int32_t)n, &array) != JBV_OK) { free(values); jbv_native_fail(vm, JBV_OUT_OF_MEMORY); return 0; }
    for (i = 0; i < n; ++i) values[i] = (uint64_t)(int64_t)(signed char)data[i];
    if (jbv_array_write(vm, array, 0, (uint32_t)n, values) != JBV_OK) jbv_native_fail(vm, JBV_NATIVE_ERROR);
    free(values);
    jbv_release(vm, array);   /* results are borrowed */
    return array;
}
static int32_t JBV_CALL host_read(JbvVM *vm, int32_t path_ref) {
    char *path = utf8(vm, path_ref);
    FILE *file = 0;
    long length;
    unsigned char *data;
    JbvRef array;
    if (!path || fopen_s(&file, path, "rb") || !file) { free(path); jbv_native_fail(vm, JBV_NOT_FOUND); return 0; }
    free(path);
    fseek(file, 0, SEEK_END); length = ftell(file); fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(length > 0 ? (size_t)length : 1);
    if (!data || fread(data, 1, (size_t)length, file) != (size_t)length) { fclose(file); free(data); jbv_native_fail(vm, JBV_NATIVE_ERROR); return 0; }
    fclose(file);
    array = byte_array(vm, data, (size_t)length);
    free(data);
    return array;
}
static void JBV_CALL host_write_file(JbvVM *vm, int32_t path_ref, int32_t array) {
    char *path = utf8(vm, path_ref);
    uint32_t n = 0, i;
    char kind;
    uint64_t *values;
    unsigned char *data;
    FILE *file = 0;
    if (!path || jbv_array_info(vm, array, &n, &kind) != JBV_OK) { free(path); jbv_native_fail(vm, JBV_BAD_ARGUMENT); return; }
    values = (uint64_t *)malloc((n ? n : 1) * sizeof(uint64_t)); data = (unsigned char *)malloc(n ? n : 1);
    if (!values || !data || jbv_array_read(vm, array, 0, n, values) != JBV_OK || fopen_s(&file, path, "wb") || !file) {
        free(path); free(values); free(data); jbv_native_fail(vm, JBV_NATIVE_ERROR); return;
    }
    for (i = 0; i < n; ++i) data[i] = (unsigned char)values[i];
    fwrite(data, 1, n, file); fclose(file);
    free(path); free(values); free(data);
}
static JbvRef string_array(JbvVM *vm, char **items, int n) {
    JbvRef array = 0, item;
    int i;
    if (jbv_new_array(vm, "[Ljava/lang/String;", n, &array) != JBV_OK) return 0;
    for (i = 0; i < n; ++i) {
        uint64_t value;
        if (jbv_string_new_utf8(vm, items[i], (uint32_t)strlen(items[i]), &item) != JBV_OK) { jbv_release(vm, array); return 0; }
        value = (uint32_t)item;
        jbv_array_write(vm, array, (uint32_t)i, 1, &value);
        jbv_release(vm, item);
    }
    return array;   /* retained */
}
static int32_t JBV_CALL host_list(JbvVM *vm, int32_t dir_ref) {
    char *dir = utf8(vm, dir_ref), pattern[MAX_PATH], *names[4096];
    WIN32_FIND_DATAA found;
    HANDLE h;
    int n = 0, i;
    JbvRef array;
    if (!dir) { jbv_native_fail(vm, JBV_OUT_OF_MEMORY); return 0; }
    snprintf(pattern, sizeof pattern, "%s\\*", dir); free(dir);
    h = FindFirstFileA(pattern, &found);
    if (h != INVALID_HANDLE_VALUE) {
        do if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && n < 4096) names[n++] = _strdup(found.cFileName);
        while (FindNextFileA(h, &found));
        FindClose(h);
    }
    array = string_array(vm, names, n);
    for (i = 0; i < n; ++i) free(names[i]);
    if (!array) { jbv_native_fail(vm, JBV_OUT_OF_MEMORY); return 0; }
    jbv_release(vm, array);
    return array;
}
static const JbvNativeEntry natives[] = {
    { "read", "(Ljava/lang/String;)[B", JBV_NATIVE_FN(host_read) },
    { "write", "(Ljava/lang/String;[B)V", JBV_NATIVE_FN(host_write_file) },
    { "list", "(Ljava/lang/String;)[Ljava/lang/String;", JBV_NATIVE_FN(host_list) },
};

/* Crash report: faulting address relative to jbytevm.dll and the registers. */
static LONG WINAPI crashed(EXCEPTION_POINTERS *info) {
    uintptr_t base = (uintptr_t)GetModuleHandleA("jbytevm.dll"), ip = (uintptr_t)info->ExceptionRecord->ExceptionAddress;
    CONTEXT *r = info->ContextRecord;
    fprintf(stderr, "crash %08lx at rva %x (eax %08lx ebx %08lx ecx %08lx edx %08lx esi %08lx edi %08lx ebp %08lx esp %08lx)\n",
        info->ExceptionRecord->ExceptionCode, (unsigned)(ip - base), r->Eax, r->Ebx, r->Ecx, r->Edx, r->Esi, r->Edi, r->Ebp, r->Esp);
    return EXCEPTION_EXECUTE_HANDLER;
}

int main(int argc, char **argv) {
    SetUnhandledExceptionFilter(crashed);
    JbvConfig config = { allocate, release, 0, 0, 0, 0, 0, 0 };
    JbvHostServices services = { 0 };
    JbvVM *vm = 0;
    JbvStatus status;
    FILE *file = 0;
    long length;
    unsigned char *bytes;
    JbvRef args;
    int32_t result = 1;
    if (argc < 3) { fprintf(stderr, "usage: %s app.jar pkg/Class [args...]\n", argv[0]); return 2; }
    if (fopen_s(&file, argv[1], "rb") || !file) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    fseek(file, 0, SEEK_END); length = ftell(file); fseek(file, 0, SEEK_SET);
    bytes = (unsigned char *)malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) return 2;
    fclose(file);
    config.max_memory = 256u * 1024 * 1024;
    config.max_instructions = UINT64_C(1) << 40;
    config.max_slots = 1u << 20;
    config.max_depth = 256;
    status = jbv_create(&config, &vm);
    services.write = host_write; services.clock = clock_now;
    if (status == JBV_OK) status = jbv_set_host_services(vm, &services);
    if (status == JBV_OK) status = jbv_load_jar(vm, bytes, (size_t)length);
    free(bytes);
    if (status == JBV_OK) {   /* optional: only applications that bundle jbvhost.Host use files */
        status = jbv_register_natives(vm, "jbvhost/Host", natives, 3, 0);
        if (status == JBV_NOT_FOUND) status = JBV_OK;
    }
    if (status == JBV_OK) {
        args = string_array(vm, argv + 3, argc - 3);
        status = args ? jbv_call(vm, argv[2], "run", "([Ljava/lang/String;)I", &args, 1, &result) : JBV_OUT_OF_MEMORY;
        if (args) jbv_release(vm, args);
    }
    if (status != JBV_OK) {
        JbvRef exception = 0;
        fprintf(stderr, "jbytevm-run: %s\n", jbv_status_string(status));
        if (jbv_exception(vm, &exception) == JBV_OK && exception) {
            JbvMethodId text;
            uint64_t ref = 0;
            if (jbv_resolve_method(vm, "java/lang/Throwable", "toString", "()Ljava/lang/String;", &text) == JBV_OK &&
                jbv_invoke(vm, &text, &exception, 1, &ref) == JBV_OK) {
                char *s = utf8(vm, (JbvRef)ref);
                if (s) { fprintf(stderr, "  %s\n", s); free(s); }
                jbv_release(vm, (JbvRef)ref);
            }
            jbv_release(vm, exception);
        }
        result = 1;
    }
    fflush(stdout);
    jbv_destroy(vm);
    return (int)result;
}

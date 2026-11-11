/* Times a static ()I method from an application JAR with a plain malloc host.
 * Usage: jbytevm-bench app.jar pkg/Class method [rounds] */
#include <jbytevm.h>
#include <jbytevm_native.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

static void *allocate(void *user, size_t bytes) { (void)user; return malloc(bytes); }
static void release(void *user, void *memory) { (void)user; free(memory); }
static int64_t JBV_CALL clock_now(void *user, int monotonic) {
    LARGE_INTEGER t, f;
    (void)user;
    QueryPerformanceCounter(&t); QueryPerformanceFrequency(&f);
    return monotonic ? (int64_t)((double)t.QuadPart * 1e9 / (double)f.QuadPart) : (int64_t)GetTickCount64();
}

int main(int argc, char **argv) {
    JbvConfig config = { allocate, release, 0, 0, 0, 0, 0, 0 };
    JbvHostServices services = { 0 };
    JbvVM *vm = 0;
    JbvStatus status;
    FILE *file = 0;
    long length;
    unsigned char *bytes;
    int rounds = argc > 4 ? atoi(argv[4]) : 5, i;
    double best = 1e300, first = 0;
    LARGE_INTEGER frequency;
    int32_t result = 0;
    if (argc < 4) { fprintf(stderr, "usage: %s app.jar pkg/Class method [rounds]\n", argv[0]); return 2; }
    if (fopen_s(&file, argv[1], "rb") || !file) return 2;
    fseek(file, 0, SEEK_END); length = ftell(file); fseek(file, 0, SEEK_SET);
    bytes = (unsigned char *)malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) return 2;
    fclose(file);
    config.max_instructions = 4000000000u;
    status = jbv_create(&config, &vm);
    services.clock = clock_now;
    if (status == JBV_OK) status = jbv_set_host_services(vm, &services);
    if (status == JBV_OK) status = jbv_load_jar(vm, bytes, (size_t)length);
    free(bytes);
    QueryPerformanceFrequency(&frequency);
    for (i = 0; status == JBV_OK && i <= rounds; ++i) {
        LARGE_INTEGER start, end;
        double ms;
        QueryPerformanceCounter(&start);
        status = jbv_call(vm, argv[2], argv[3], "()I", 0, 0, &result);
        QueryPerformanceCounter(&end);
        ms = (double)(end.QuadPart - start.QuadPart) * 1000.0 / (double)frequency.QuadPart;
        if (i == 0) first = ms; else if (ms < best) best = ms;
        if (status == JBV_OK) status = jbv_collect(vm);
    }
    if (status != JBV_OK) { fprintf(stderr, "%s: %s\n", argv[3], jbv_status_string(status)); return 1; }
    printf("%s %.3f %.3f %d\n", argv[3], first, best, (int)result);
    jbv_destroy(vm);
    return 0;
}

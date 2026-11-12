/* Times a static ()I method from an application JAR with a plain malloc host
 * (wall time and thread cycles).
 * Usage: jbytevm-bench app.jar pkg/Class method [rounds]
 * JBV_AFFINITY=mask pins the process (hybrid CPUs: keep to one performance core).
 * JBV_SAMPLE=file records the interpreter thread's EIP every millisecond,
 * as "rva" lines relative to jbytevm.dll (others: "other"), for profiling. */
#include <jbytevm.h>
#include <jbytevm_native.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#pragma comment(lib, "winmm.lib")

static void *allocate(void *user, size_t bytes) { (void)user; return malloc(bytes); }
static void release(void *user, void *memory) { (void)user; free(memory); }
static int64_t JBV_CALL clock_now(void *user, int monotonic) {
    LARGE_INTEGER t, f;
    (void)user;
    QueryPerformanceCounter(&t); QueryPerformanceFrequency(&f);
    return monotonic ? (int64_t)((double)t.QuadPart * 1e9 / (double)f.QuadPart) : (int64_t)GetTickCount64();
}

static HANDLE target;
static volatile LONG sampling;
static FILE *samples;
static DWORD WINAPI sampler(LPVOID unused) {
    uintptr_t base = (uintptr_t)GetModuleHandleA("jbytevm.dll");
    (void)unused;
    timeBeginPeriod(1);
    while (sampling) {
        CONTEXT context;
        Sleep(1);
        if (SuspendThread(target) == (DWORD)-1) break;
        context.ContextFlags = CONTEXT_CONTROL;
        if (GetThreadContext(target, &context)) {
#if defined(_M_IX86)
            uintptr_t ip = context.Eip;
#else
            uintptr_t ip = (uintptr_t)context.Rip;
#endif
            if (ip >= base && ip < base + 0x100000) fprintf(samples, "%x\n", (unsigned)(ip - base));
            else fprintf(samples, "other\n");
        }
        ResumeThread(target);
    }
    timeEndPeriod(1);
    return 0;
}

/* Crash report: faulting address relative to jbytevm.dll and the registers. */
static LONG WINAPI crashed(EXCEPTION_POINTERS *info) {
    uintptr_t base = (uintptr_t)GetModuleHandleA("jbytevm.dll"), ip = (uintptr_t)info->ExceptionRecord->ExceptionAddress;
#if defined(_M_IX86)
    CONTEXT *r = info->ContextRecord;
    fprintf(stderr, "crash %08lx at rva %x (eax %08lx ebx %08lx ecx %08lx edx %08lx esi %08lx edi %08lx ebp %08lx esp %08lx)\n",
        info->ExceptionRecord->ExceptionCode, (unsigned)(ip - base), r->Eax, r->Ebx, r->Ecx, r->Edx, r->Esi, r->Edi, r->Ebp, r->Esp);
#else
    fprintf(stderr, "crash %08lx at rva %x\n", info->ExceptionRecord->ExceptionCode, (unsigned)(ip - base));
#endif
    return EXCEPTION_EXECUTE_HANDLER;
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
    ULONG64 cycles_best = ~(ULONG64)0;
    LARGE_INTEGER frequency;
    int32_t result = 0;
    char *env = 0;
    size_t env_size = 0;
    HANDLE thread = 0;
    if (argc < 4) { fprintf(stderr, "usage: %s app.jar pkg/Class method [rounds]\n", argv[0]); return 2; }
    SetUnhandledExceptionFilter(crashed);
    if (!_dupenv_s(&env, &env_size, "JBV_AFFINITY") && env) { SetProcessAffinityMask(GetCurrentProcess(), (DWORD_PTR)strtoul(env, 0, 0)); free(env); env = 0; }
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
        ULONG64 c0, c1;
        double ms;
        if (i == 1 && !_dupenv_s(&env, &env_size, "JBV_SAMPLE") && env) {   /* profile the measured rounds */
            if (!fopen_s(&samples, env, "w") && samples) {
                DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &target, 0, FALSE, DUPLICATE_SAME_ACCESS);
                sampling = 1;
                thread = CreateThread(0, 0, sampler, 0, 0, 0);
            }
            free(env); env = 0;
        }
        QueryThreadCycleTime(GetCurrentThread(), &c0);
        QueryPerformanceCounter(&start);
        status = jbv_call(vm, argv[2], argv[3], "()I", 0, 0, &result);
        QueryPerformanceCounter(&end);
        QueryThreadCycleTime(GetCurrentThread(), &c1);
        if (i && c1 - c0 < cycles_best) cycles_best = c1 - c0;
        ms = (double)(end.QuadPart - start.QuadPart) * 1000.0 / (double)frequency.QuadPart;
        if (i == 0) first = ms; else if (ms < best) best = ms;
        if (status == JBV_OK) status = jbv_collect(vm);
    }
    if (thread) { sampling = 0; WaitForSingleObject(thread, INFINITE); fclose(samples); }
    if (status != JBV_OK) { fprintf(stderr, "%s: %s\n", argv[3], jbv_status_string(status)); return 1; }
    /* first ms, best ms, result, best Mcycles of this thread (immune to preemption) */
    printf("%s %.3f %.3f %d %.2f\n", argv[3], first, best, (int)result, (double)cycles_best / 1e6);
    jbv_destroy(vm);
    return 0;
}

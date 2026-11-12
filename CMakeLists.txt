cmake_minimum_required(VERSION 3.20)
project(JByteVM VERSION 0.8.0 LANGUAGES C ASM_MASM)
set(JBV_PROFILE "full" CACHE STRING "Runtime profile: full, text, core")
set_property(CACHE JBV_PROFILE PROPERTY STRINGS full text core)
if(NOT JBV_PROFILE MATCHES "^(full|text|core)$")
    message(FATAL_ERROR "Unknown JBV_PROFILE: ${JBV_PROFILE}")
endif()
if(NOT MSVC OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")
    message(FATAL_ERROR "JByteVM is x86 assembly: configure MSVC with -A Win32 (build.py does).")
endif()

set(JBV_GC_STRESS 0 CACHE STRING "1: collect and move objects at almost every safepoint (testing)")
# The profile as assembler constants (src/layout.inc includes it).
set(JBV_FULL 0)
set(JBV_CORE 0)
if(JBV_PROFILE STREQUAL "full")
    set(JBV_FULL 1)
elseif(JBV_PROFILE STREQUAL "core")
    set(JBV_CORE 1)
endif()
file(WRITE "${CMAKE_BINARY_DIR}/profile.inc" "JBV_PROFILE_FULL EQU ${JBV_FULL}
JBV_PROFILE_CORE EQU ${JBV_CORE}
JBV_GC_STRESS EQU ${JBV_GC_STRESS}
")
# The VM is assembly only (MASM). The C below are example hosts and test fixtures.
add_library(jbytevm SHARED src/native.asm src/interp.asm src/lzma.asm src/numeric.asm src/classfile.asm
    src/jar.asm src/throw.asm src/vm.asm src/classes.asm src/gc.asm src/monitors.asm src/api.asm src/link.asm
    src/slow.asm src/run.asm)
if(JBV_PROFILE STREQUAL "full")
    target_sources(jbytevm PRIVATE src/values.asm src/classpath.asm src/annotations.asm src/dynamic.asm
        src/reflection.asm "${CMAKE_BINARY_DIR}/generated_classpath.asm")
else()
    target_sources(jbytevm PRIVATE src/core.asm)
endif()
if(NOT JBV_PROFILE STREQUAL "core")
    target_sources(jbytevm PRIVATE src/text.asm src/decimal.asm src/library.asm)
endif()
target_include_directories(jbytevm PUBLIC include)
target_compile_options(jbytevm PRIVATE /safeseh "/I${CMAKE_SOURCE_DIR}/src" "/I${CMAKE_BINARY_DIR}")
# 64-bit division and remainder come from the compiler's helpers (_alldiv, _allrem); nothing else
# of the CRT. No entry point, no OS imports: the host supplies memory and services.
target_link_libraries(jbytevm PRIVATE libcmt)
target_link_options(jbytevm PRIVATE /NODEFAULTLIB /NOENTRY /INCREMENTAL:NO /OPT:REF /OPT:ICF /MAP)

function(jbv_host name source options)
    add_executable(${name} ${source})
    target_compile_definitions(${name} PRIVATE JBV_USE_DLL)
    target_link_libraries(${name} PRIVATE jbytevm)
    set_property(TARGET ${name} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
    target_compile_options(${name} PRIVATE /W4 /WX ${options})
endfunction()
jbv_host(jbytevm-demo examples/host.c /O1)
jbv_host(jbytevm-bench examples/bench_host.c /O2)
jbv_host(jbytevm-run examples/run_host.c /O2)
jbv_host(jbytevm-native-demo examples/native_host.c /O1)
add_library(jbytevm-typed-fixture SHARED tests/typed_fixture.c)
target_compile_definitions(jbytevm-typed-fixture PRIVATE JBV_USE_DLL)
target_link_libraries(jbytevm-typed-fixture PRIVATE jbytevm)
set_property(TARGET jbytevm-typed-fixture PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
target_compile_options(jbytevm-typed-fixture PRIVATE /W4 /WX /O1 /Gr /fp:strict)

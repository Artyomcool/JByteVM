; Typed static native calls: cdecl R function(JbvVM *, Java arguments...).
; JVM slots already have the Win32 scalar argument order/width (low word first).
; This is one shared call site, with no generated code or per-method stubs.
.686
.model flat, C
option casemap:none
PUBLIC jbv_native_x86

.code
jbv_native_x86 PROC
    push ebp
    mov ebp, esp
    push esi
    push edi
    mov ecx, [ebp+20]            ; JVM argument slot count, at most 255
    lea eax, [ecx*4+4]           ; plus JbvVM *
    sub esp, eax
    and esp, -16
    mov eax, [ebp+12]
    mov [esp], eax
    lea edi, [esp+4]
    mov esi, [ebp+16]
    rep movsd
    call DWORD PTR [ebp+8]
    ; Native code may change x87 rounding; capture FP returns with Java rounding.
    push 027fh
    fldcw WORD PTR [esp]
    add esp, 4
    cmp DWORD PTR [ebp+24], 5    ; JBV_FLOAT + 1
    je native_float
    cmp DWORD PTR [ebp+24], 6    ; JBV_DOUBLE + 1
    jne native_return
    sub esp, 8
    fstp QWORD PTR [esp]
    pop eax
    pop edx
    jmp native_return
native_float:
    sub esp, 4
    fstp DWORD PTR [esp]
    pop eax
    xor edx, edx
native_return:
    lea esp, [ebp-8]
    pop edi
    pop esi
    pop ebp
    ret
jbv_native_x86 ENDP
END

; Native calls and the host API: the FP
; environment switch, built-in and typed natives, method/field/array access, exceptions.
.686
.xmm
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_text@4:PROC
EXTERN SYSCALL @jbv_text_is@12:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_lazy_class@16:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC
EXTERN SYSCALL @jbv_lookup_field@20:PROC
EXTERN SYSCALL @jbv_arguments@28:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_kind@4:PROC
EXTERN SYSCALL @jbv_descriptor_type@16:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_check_reference@16:PROC
EXTERN SYSCALL @jbv_narrow@8:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_array_get@12:PROC
EXTERN SYSCALL @jbv_array_set@20:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC
EXTERN jbv_native_x86:PROC

S_BAD_ARG   EQU 1
S_BAD_CLASS EQU 3
S_UNSUPPORTED EQU 6
S_NOT_FOUND EQU 7
S_LINKAGE   EQU 8
S_BUSY      EQU 11
S_NULL      EQU 12
S_BOUNDS    EQU 13
S_STORE     EQU 15
S_CAST      EQU 16
S_EXCEPTION EQU 22
K_INT       EQU 0
K_REF       EQU 1
K_LONG      EQU 2
K_FLOAT     EQU 4
K_DOUBLE    EQU 5
DATA0       EQU 4
ACC_STATIC  EQU 8
NATIVE      EQU 100h
TYPED       EQU 8000h

.const
s_clinit    DB '<clinit>', 0
s_init      DB '<init>', 0
s_throwable DB 'Ljava/lang/Throwable;'

.code
; ---- FP environment: natives run with the host's x87/SSE state, Java with its own
@jbv_fp_enter@4 PROC SYSCALL        ; ecx = JbvFPEnv*
    fnstenv [ecx]
    stmxcsr DWORD PTR [ecx+28]
    fnclex
    push 027Fh
    fldcw WORD PTR [esp]
    mov DWORD PTR [esp], 01F80h
    ldmxcsr DWORD PTR [esp]
    pop ecx
    ret
@jbv_fp_enter@4 ENDP
@jbv_fp_restore@4 PROC SYSCALL
    fldenv [ecx]
    ldmxcsr DWORD PTR [ecx+28]
    ret
@jbv_fp_restore@4 ENDP

; eax = the function, edx = out; ebx = vm, esi = method, [ebp+8] args, [ebp+12] count
call5:
    push edx
    movzx ecx, WORD PTR [ebp+12]
    push ecx
    push DWORD PTR [ebp+8]
    push DWORD PTR [esi+M_NATIVE_USER]
    push ebx
    call eax
    add esp, 20
    ret
; the slot native, else the int one ([ebp-4] its result) -> eax status
dispatch:
    mov eax, [esi+M_NATIVE_SLOTS]
    mov edx, [ebp+16]
    test eax, eax
    jnz call5
    mov eax, [esi+M_NATIVE]
    test eax, eax
    jz ds_none
    mov DWORD PTR [ebp-4], 0
    lea edx, [ebp-4]
    call call5
    mov ecx, [ebp+16]
    mov edx, [ebp-4]
    mov [ecx], edx
    mov DWORD PTR [ecx+4], 0
    ret
ds_none:
    mov eax, S_NOT_FOUND
    ret
@jbv_native_call@20 PROC SYSCALL    ; ecx vm, edx method, [ebp+8] args, count, out
    push ebp
    mov ebp, esp
    push 0
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    cmp BYTE PTR [esi+M_INTRINSIC], 0   ; built-in: the VM's FP state, no switch
    je @F
    call dispatch
    jmp nc_ret
@@:
    sub esp, 32
    mov ecx, esp
    call @jbv_fp_enter@4
    mov BYTE PTR [ebx+VM_FP_READY], 0
    test WORD PTR [esi+M_FLAGS], TYPED
    jz @F
    push DWORD PTR [ebp+16]
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    mov edx, esi
    mov ecx, ebx
    call @jbv_typed_call@20
    jmp nc_restore
@@:
    cmp DWORD PTR [esi+M_NATIVE_SLOTS], 0
    jne nc_dispatch
    movzx eax, BYTE PTR [esi+M_RESULT_KIND]   ; an int native cannot return long/double
    cmp eax, K_LONG+1
    je nc_unsupported
    cmp eax, K_DOUBLE+1
    je nc_unsupported
nc_dispatch:
    call dispatch
    jmp nc_restore
nc_unsupported:
    mov eax, S_UNSUPPORTED
nc_restore:
    mov edi, eax
    mov ecx, esp
    call @jbv_fp_restore@4
    mov BYTE PTR [ebx+VM_FP_READY], 1
    mov eax, edi
nc_ret:
    lea esp, [ebp-16]
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 12
@jbv_native_call@20 ENDP
; a typed native: cdecl R function(vm, Java arguments...) in a JbvNativeFrame {previous, user, status}
@jbv_typed_call@20 PROC SYSCALL     ; ecx vm, edx method, [ebp+8] args, count, out
    push ebp
    mov ebp, esp
    sub esp, 12
    push ebx
    mov ebx, ecx
    mov eax, [ebx+VM_NATIVE_FRAME]
    mov [ebp-12], eax
    mov eax, [edx+M_NATIVE_USER]
    mov [ebp-8], eax
    mov DWORD PTR [ebp-4], 0
    lea eax, [ebp-12]
    mov [ebx+VM_NATIVE_FRAME], eax
    movzx eax, BYTE PTR [edx+M_RESULT_KIND]
    push eax
    movzx eax, WORD PTR [ebp+12]
    push eax
    push DWORD PTR [ebp+8]
    push ebx
    push DWORD PTR [edx+M_NATIVE_SLOTS]
    call jbv_native_x86
    add esp, 20
    mov ecx, [ebp+16]
    mov [ecx], eax
    mov [ecx+4], edx
    mov eax, [ebp-12]
    mov [ebx+VM_NATIVE_FRAME], eax
    mov eax, [ebp-4]
    test eax, eax
    jnz @F
    cmp DWORD PTR [ebx+VM_EXCEPTION], 0
    je @F
    mov eax, [ebx+VM_EXCEPTION_STATUS]
@@:
    pop ebx
    mov esp, ebp
    pop ebp
    ret 12
@jbv_typed_call@20 ENDP
jbv_native_context PROC EXPORT      ; (vm) -> the running typed native's user pointer
    mov eax, [esp+4]
    test eax, eax
    jz @F
    mov eax, [eax+VM_NATIVE_FRAME]
    test eax, eax
    jz @F
    mov eax, [eax+4]
@@:
    ret
jbv_native_context ENDP
jbv_native_fail PROC EXPORT         ; (vm, status): the typed native's result status
    mov ecx, [esp+4]
    mov eax, [esp+8]
    jecxz nf_bad
    mov ecx, [ecx+VM_NATIVE_FRAME]
    jecxz nf_bad
    test eax, eax
    jz nf_bad
    mov [ecx+8], eax
    ret
nf_bad:
    mov eax, S_BAD_ARG
    ret
jbv_native_fail ENDP
@jbv_begin_call@4 PROC SYSCALL      ; an outer call: a fresh budget and no pending exception
    cmp DWORD PTR [ecx+VM_DEPTH], 0
    jne @F
    mov eax, [ecx+VM_MAX_INSTRUCTIONS]
    mov edx, [ecx+VM_MAX_INSTRUCTIONS+4]
    mov [ecx+VM_REMAINING], eax
    mov [ecx+VM_REMAINING+4], edx
    xor eax, eax
    mov [ecx+VM_EXCEPTION], eax
    mov [ecx+VM_EXCEPTION_STATUS], eax
@@:
    ret
@jbv_begin_call@4 ENDP
jbv_throw PROC EXPORT               ; (vm, ref): a Throwable becomes the pending exception
    push ebx
    mov ebx, [esp+8]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz th_ret
    mov edx, [esp+12]
    mov eax, S_NULL
    test edx, edx
    jz th_ret
    push 21
    push OFFSET s_throwable
    mov ecx, ebx
    call @jbv_check_reference@16
    test eax, eax
    jnz th_ret
    mov eax, [esp+12]
    mov [ebx+VM_EXCEPTION], eax
    mov eax, S_EXCEPTION
    mov [ebx+VM_EXCEPTION_STATUS], eax
th_ret:
    pop ebx
    ret
jbv_throw ENDP
jbv_clear_exception PROC EXPORT
    mov ecx, [esp+4]
    mov eax, S_BAD_ARG
    jecxz @F
    xor eax, eax
    mov [ecx+VM_EXCEPTION], eax
    mov [ecx+VM_EXCEPTION_STATUS], eax
@@:
    ret
jbv_clear_exception ENDP

; ---- typed natives: static native methods bound to cdecl functions
; edi = class, esi = an entry {name, descriptor, function} -> eax = its method
entry_method:
    mov ecx, [esi+4]
    call @jbv_text@4
    push edx
    push eax
    mov ecx, [esi]
    call @jbv_text@4
    push edx
    push eax
    mov ecx, edi
    call @jbv_find_method@20
    ret
R_VM    EQU 8
R_NAME  EQU 12
R_TABLE EQU 16
R_COUNT EQU 20
R_USER  EQU 24
jbv_register_natives PROC EXPORT    ; (vm, class_name, entries, count, user)
    push ebp
    mov ebp, esp
    push 0
    push ebx
    push esi
    push edi
    mov ebx, [ebp+R_VM]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz rn_ret
    cmp DWORD PTR [ebp+R_NAME], 0
    je rn_ret
    cmp DWORD PTR [ebp+R_COUNT], 0
    je @F
    cmp DWORD PTR [ebp+R_TABLE], 0
    je rn_ret
@@:
    mov eax, S_BUSY
    cmp DWORD PTR [ebx+VM_DEPTH], 0
    jne rn_ret
    mov ecx, [ebp+R_NAME]
    call @jbv_text@4
    push edx
    push eax
    push edx
    push eax
    mov ecx, ebx
    call @jbv_find_class@12
    mov [ebp-4], eax
    test eax, eax
    lea edx, [ebp-4]
    mov ecx, ebx
    jnz @F
    call @jbv_lazy_class@16
    test eax, eax
    jnz rn_ret
    jmp rn_found
@@:
    add esp, 8
rn_found:
    mov edi, [ebp-4]
    movzx eax, WORD PTR [edi+C_METHOD_COUNT]
    cmp [ebp+R_COUNT], eax
    mov eax, S_BAD_ARG
    ja rn_ret
    ; check the whole table first: nothing changes unless every entry binds
    xor ebx, ebx                        ; i (vm no longer needed)
rn_check:
    cmp ebx, [ebp+R_COUNT]
    jae rn_bind
    imul esi, ebx, 12
    add esi, [ebp+R_TABLE]
    mov eax, S_BAD_ARG
    cmp DWORD PTR [esi], 0
    je rn_ret
    cmp DWORD PTR [esi+4], 0
    je rn_ret
    cmp DWORD PTR [esi+8], 0
    je rn_ret
    call entry_method
    mov ecx, eax
    mov eax, S_NOT_FOUND
    test ecx, ecx
    jz rn_ret
    mov eax, S_LINKAGE
    test WORD PTR [ecx+M_FLAGS], NATIVE
    jz rn_ret
    cmp BYTE PTR [ecx+M_INTRINSIC], 0
    jne rn_ret
    mov eax, S_UNSUPPORTED
    test WORD PTR [ecx+M_FLAGS], ACC_STATIC
    jz rn_ret
    push edi
    mov edi, ecx                        ; the method; earlier entries must name others
    mov esi, [ebp+R_TABLE]
    mov ecx, ebx
rn_twice:
    jecxz rn_unique
    push ecx
    push DWORD PTR [edi+M_NAME+TEXT_SIZE]
    push DWORD PTR [edi+M_NAME+TEXT_DATA]
    mov ecx, [esi]
    call @jbv_text_is@12
    test eax, eax
    jz @F
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_DATA]
    mov ecx, [esi+4]
    call @jbv_text_is@12
@@:
    pop ecx
    test eax, eax
    jnz rn_duplicate
    add esi, 12
    dec ecx
    jmp rn_twice
rn_duplicate:
    pop edi
    mov eax, S_BAD_ARG
    jmp rn_ret
rn_unique:
    pop edi
    inc ebx
    jmp rn_check
rn_bind:
    xor ebx, ebx
@@:
    cmp ebx, [ebp+R_COUNT]
    jae rn_ok
    imul esi, ebx, 12
    add esi, [ebp+R_TABLE]
    call entry_method
    mov ecx, [esi+8]
    mov [eax+M_NATIVE_SLOTS], ecx
    mov DWORD PTR [eax+M_NATIVE], 0
    mov ecx, [ebp+R_USER]
    mov [eax+M_NATIVE_USER], ecx
    or WORD PTR [eax+M_FLAGS], TYPED
    inc ebx
    jmp @B
rn_ok:
    xor eax, eax
rn_ret:
    lea esp, [ebp-16]
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_register_natives ENDP

; ---- methods
; ebx = vm, edx = &class, [esp+4] = a C string -> eax status (the class resolved)
resolve_named:
    mov ecx, [esp+4]
    push edx
    call @jbv_text@4
    pop ecx
    push edx
    push eax
    mov edx, ecx
    mov ecx, ebx
    call @jbv_resolve_class@16
    ret 4
M_C     EQU -4
M_N     EQU -12       ; JbvText name
M_D     EQU -20       ; JbvText descriptor
jbv_resolve_method PROC EXPORT      ; (vm, class_name, name, descriptor, out)
    push ebp
    mov ebp, esp
    sub esp, 20
    push ebx
    push esi
    mov ebx, [ebp+8]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz rm_ret
    cmp DWORD PTR [ebp+12], 0
    je rm_ret
    cmp DWORD PTR [ebp+16], 0
    je rm_ret
    cmp DWORD PTR [ebp+20], 0
    je rm_ret
    cmp DWORD PTR [ebp+24], 0
    je rm_ret
    mov ecx, [ebp+16]
    call @jbv_text@4
    mov [ebp+M_N], eax
    mov [ebp+M_N+4], edx
    mov ecx, [ebp+20]
    call @jbv_text@4
    mov [ebp+M_D], eax
    mov [ebp+M_D+4], edx
    push DWORD PTR [ebp+M_N+4]
    push DWORD PTR [ebp+M_N]
    mov ecx, OFFSET s_clinit
    call @jbv_text_is@12
    test eax, eax
    mov eax, S_UNSUPPORTED
    jnz rm_ret
    push DWORD PTR [ebp+12]
    lea edx, [ebp+M_C]
    call resolve_named
    test eax, eax
    jnz rm_ret
    push DWORD PTR [ebp+M_N+4]
    push DWORD PTR [ebp+M_N]
    mov ecx, OFFSET s_init
    call @jbv_text_is@12
    mov esi, eax
    push DWORD PTR [ebp+M_D+4]
    push DWORD PTR [ebp+M_D]
    push DWORD PTR [ebp+M_N+4]
    push DWORD PTR [ebp+M_N]
    test esi, esi                       ; constructors exactly, else up the hierarchy
    jz @F
    mov ecx, [ebp+M_C]
    call @jbv_find_method@20
    jmp rm_found
@@:
    lea ecx, [ebp+M_C]
    call @jbv_lookup_method@20
rm_found:
    test eax, eax
    jnz @F
    cmp DWORD PTR [ebp+M_C], 1          ; no method: NOT_FOUND, or LINKAGE when the lookup failed
    sbb eax, eax
    neg eax
    add eax, S_NOT_FOUND
    jmp rm_ret
@@:
    mov ecx, [ebp+24]
    mov edx, [ebp+M_C]
    mov [ecx], edx
    mov [ecx+4], eax
    xor eax, eax
rm_ret:
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_resolve_method ENDP
I_ID    EQU 12
I_ARGS  EQU 16
I_COUNT EQU 20
I_OUT   EQU 24
I_OWNER EQU -4        ; the target's class
I_RECV  EQU -8
I_VALUE EQU -16
jbv_invoke PROC EXPORT              ; (vm, id, args, count, result)
    push ebp
    mov ebp, esp
    sub esp, 16
    push ebx
    push esi
    push edi
    mov ebx, [ebp+8]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz iv_ret
    mov ecx, [ebp+I_ID]
    test ecx, ecx
    jz iv_ret
    cmp DWORD PTR [ecx], 0
    je iv_ret
    cmp DWORD PTR [ecx+4], 0
    je iv_ret
    cmp DWORD PTR [ebp+I_OUT], 0
    je iv_ret
    movzx edx, WORD PTR [ebp+I_COUNT]
    test edx, edx
    jz @F
    cmp DWORD PTR [ebp+I_ARGS], 0
    je iv_ret
@@:
    mov ecx, ebx
    call @jbv_begin_call@4
    mov ecx, [ebp+I_ID]
    mov eax, [ecx]
    mov [ebp+I_OWNER], eax
    mov esi, [ecx+4]                    ; m
    mov edi, esi                        ; the target
    xor eax, eax
    mov [ebp+I_VALUE], eax
    mov [ebp+I_VALUE+4], eax
    movzx eax, WORD PTR [ebp+I_COUNT]
    cmp ax, [esi+M_ARG_SLOTS]
    mov eax, S_BAD_ARG
    jne iv_ret
    push 1
    call arguments
    test eax, eax
    jnz iv_ret
    test WORD PTR [esi+M_FLAGS], ACC_STATIC
    jz @F
    mov edx, [ebp+I_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    jmp iv_execute
@@:
    xor eax, eax                        ; private methods and constructors exactly; else virtual
    test WORD PTR [esi+M_FLAGS], 2
    jnz iv_execute
    push DWORD PTR [esi+M_NAME+TEXT_SIZE]
    push DWORD PTR [esi+M_NAME+TEXT_DATA]
    mov ecx, OFFSET s_init
    call @jbv_text_is@12
    test eax, eax
    mov eax, 0
    jnz iv_execute
    lea eax, [ebp+I_RECV]
    push eax
    mov edx, [ebp+I_ARGS]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz iv_execute
    mov eax, [ebp+I_RECV]
    mov eax, [eax]
    mov [ebp+I_OWNER], eax
    push DWORD PTR [esi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [esi+M_DESCRIPTOR+TEXT_DATA]
    push DWORD PTR [esi+M_NAME+TEXT_SIZE]
    push DWORD PTR [esi+M_NAME+TEXT_DATA]
    lea ecx, [ebp+I_OWNER]
    call @jbv_lookup_method@20
    mov edi, eax
    test eax, eax
    jz iv_linkage
    test WORD PTR [eax+M_FLAGS], ACC_STATIC or 400h
    mov eax, 0
    jz iv_execute
iv_linkage:
    mov eax, S_LINKAGE
iv_execute:
    test eax, eax
    jnz iv_unpin
    lea eax, [ebp+I_VALUE]
    push eax
    movzx eax, WORD PTR [ebp+I_COUNT]
    push eax
    push 0
    push DWORD PTR [ebp+I_ARGS]
    push edi
    mov edx, [ebp+I_OWNER]
    mov ecx, ebx
    call @jbv_execute@28
    test eax, eax
    jnz iv_unpin
    cmp BYTE PTR [esi+M_RESULT_KIND], K_REF+1   ; a returned reference becomes the host's handle
    jne iv_unpin
    push DWORD PTR [ebp+I_VALUE]
    push ebx
    call jbv_retain
    add esp, 8
iv_unpin:
    push eax
    push -1
    call arguments
    pop eax
    test eax, eax
    jnz iv_ret
    mov ecx, [ebp+I_OUT]
    mov edx, [ebp+I_VALUE]
    mov [ecx], edx
    mov edx, [ebp+I_VALUE+4]
    mov [ecx+4], edx
iv_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_invoke ENDP
; jbv_arguments(vm, id->owner, m, args, count, 0, pin): pin pushed by the caller (popped here)
arguments:
    pop eax                             ; the return address
    push 0
    movzx ecx, WORD PTR [ebp+I_COUNT]
    push ecx
    push DWORD PTR [ebp+I_ARGS]
    push esi
    push eax
    mov ecx, [ebp+I_ID]
    mov edx, [ecx]
    mov ecx, ebx
    jmp @jbv_arguments@28
V_SLOTS EQU -1020     ; int32_t[255]
V_POS   EQU -1024
V_WIDTH EQU -1028
V_RES   EQU -1036
jbv_invoke_args PROC EXPORT         ; (vm, id, out, ...): a static method with C arguments
    push ebp
    mov ebp, esp
    sub esp, 1036
    push ebx
    push esi
    push edi
    mov eax, S_BAD_ARG
    cmp DWORD PTR [ebp+8], 0
    je ia_ret
    mov ecx, [ebp+12]
    test ecx, ecx
    jz ia_ret
    cmp DWORD PTR [ecx], 0
    je ia_ret
    mov esi, [ecx+4]
    test esi, esi
    jz ia_ret
    cmp DWORD PTR [ebp+16], 0
    je ia_ret
    mov eax, S_UNSUPPORTED
    test WORD PTR [esi+M_FLAGS], ACC_STATIC
    jz ia_ret
    lea edi, [ebp+20]                   ; the variable arguments
    xor ebx, ebx                        ; slots used
    mov DWORD PTR [ebp+V_POS], 1
ia_next:
    mov eax, [esi+M_DESCRIPTOR+TEXT_DATA]
    mov ecx, [ebp+V_POS]
    movzx ecx, BYTE PTR [eax+ecx]
    cmp cl, ')'
    je ia_call
    call @jbv_kind@4
    push eax
    push DWORD PTR [esi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [esi+M_DESCRIPTOR+TEXT_DATA]
    lea edx, [ebp+V_WIDTH]
    lea ecx, [ebp+V_POS]
    call @jbv_descriptor_type@16
    pop ecx                             ; the kind
    test eax, eax
    mov eax, S_BAD_CLASS
    jz ia_ret
    mov eax, 255
    sub eax, ebx
    cmp [ebp+V_WIDTH], eax
    mov eax, S_BAD_ARG
    ja ia_ret
    lea edx, [ebp+V_SLOTS+ebx*4]
    cmp cl, K_FLOAT
    je ia_float
    mov eax, [edi]
    mov [edx], eax
    add edi, 4
    cmp cl, K_LONG
    je ia_high
    cmp cl, K_DOUBLE
    jne ia_put
ia_high:
    mov eax, [edi]
    mov [edx+4], eax
    add edi, 4
    jmp ia_put
ia_float:                               ; promoted to double by the caller
    fld QWORD PTR [edi]
    fstp DWORD PTR [edx]
    add edi, 8
ia_put:
    add ebx, [ebp+V_WIDTH]
    jmp ia_next
ia_call:
    lea eax, [ebp+V_RES]
    push eax
    push ebx
    lea eax, [ebp+V_SLOTS]
    push eax
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call jbv_invoke
    add esp, 20
    test eax, eax
    jnz ia_ret
    mov ecx, [ebp+16]
    mov edx, [ebp+V_RES]
    mov [ecx], edx
    mov edx, [ebp+V_RES+4]
    mov [ecx+4], edx
ia_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_invoke_args ENDP

; ---- objects and arrays from the host
jbv_alloc_object PROC EXPORT        ; (vm, class_name, out): an initialized instance, retained
    xor eax, eax
    jmp new_common
jbv_alloc_object ENDP
jbv_new_array PROC EXPORT           ; (vm, descriptor, length, out): a retained array
    mov eax, 1
    jmp new_common
jbv_new_array ENDP
; eax = 1 for an array; [ebp+8] vm, name, (length), out
new_common:
    push ebp
    mov ebp, esp
    push 0                              ; the class, then the ref
    push ebx
    push esi
    mov ebx, [ebp+8]
    mov esi, eax
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz nw_ret
    mov ecx, [ebp+12]
    jecxz nw_ret
    mov edx, [ebp+16+esi*4]             ; out
    test edx, edx
    jz nw_ret
    test esi, esi
    jnz @F
    mov ecx, ebx
    call @jbv_begin_call@4
    jmp nw_resolve
@@:
    cmp BYTE PTR [ecx], '['
    jne nw_ret
nw_resolve:
    push DWORD PTR [ebp+12]
    lea edx, [ebp-4]
    call resolve_named
    test eax, eax
    jnz nw_ret
    xor ecx, ecx                        ; the length
    test esi, esi
    jnz nw_array
    mov edx, [ebp-4]
    mov eax, S_BAD_ARG
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    jne nw_ret
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz nw_ret
    xor ecx, ecx
    jmp nw_make
nw_array:
    mov ecx, [ebp+16]
nw_make:
    lea eax, [ebp-4]
    push eax
    push ecx
    mov edx, [ebp-4]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz nw_ret
    push DWORD PTR [ebp-4]
    push ebx
    call jbv_retain
    add esp, 8
    test eax, eax
    jnz nw_ret
    mov ecx, [ebp+16+esi*4]
    mov edx, [ebp-4]
    mov [ecx], edx
nw_ret:
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret

jbv_resolve_field PROC EXPORT       ; (vm, class_name, name, descriptor, out)
    push ebp
    mov ebp, esp
    push 0
    push ebx
    mov ebx, [ebp+8]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz rf_ret
    xor ecx, ecx
@@:
    cmp DWORD PTR [ebp+12+ecx*4], 0
    je rf_ret
    inc ecx
    cmp ecx, 4
    jb @B
    push DWORD PTR [ebp+12]
    lea edx, [ebp-4]
    call resolve_named
    test eax, eax
    jnz rf_ret
    mov ecx, [ebp+20]
    call @jbv_text@4
    push edx
    push eax
    mov ecx, [ebp+16]
    call @jbv_text@4
    push edx
    push eax
    lea ecx, [ebp-4]
    call @jbv_lookup_field@20
    test eax, eax
    jnz @F
    mov eax, S_NOT_FOUND
    jmp rf_ret
@@:
    mov ecx, [ebp+24]
    mov edx, [ebp-4]
    mov [ecx], edx
    mov [ecx+4], eax
    xor eax, eax
rf_ret:
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_resolve_field ENDP
; ebx = vm, esi = the field id, edx = the receiver -> eax status, edx = the field's slots
; (statics initialize their class: Java code may run and collect)
field_location:
    push edi
    mov edi, [esi+4]                    ; the field
    test WORD PTR [edi+FIELD_FLAGS], ACC_STATIC
    jz fl_instance
    mov eax, S_BAD_ARG
    test edx, edx
    jnz fl_ret
    mov edx, [esi]
    cmp BYTE PTR [edx+C_INIT_STATE], 2
    je @F
    mov ecx, ebx
    call @jbv_begin_call@4
@@:
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_initialize@8
    lea edx, [edi+FIELD_VALUE]
    jmp fl_ret
fl_instance:
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop edx
    test eax, eax
    jnz fl_ret
    push edx
    mov ecx, [edx]
    mov edx, [esi]
    call @jbv_assignable@8
    pop edx
    test eax, eax
    mov eax, S_CAST
    jz fl_ret
    mov eax, [edi+FIELD_SLOT]
    lea edx, [edx+eax*4+DATA0]
    xor eax, eax
fl_ret:
    pop edi
    ret
; [esp+8] vm, id (after the caller's ebx/esi pushes and its return) -> ebx vm, esi id, edi kind; ZF = bad
field_args:
    mov ebx, [ebp+8]
    mov esi, [ebp+12]
    test ebx, ebx
    jz @F
    test esi, esi
    jz @F
    cmp DWORD PTR [esi], 0
    je @F
    mov eax, [esi+4]
    test eax, eax
    jz @F
    mov eax, [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    movzx ecx, BYTE PTR [eax]
    call @jbv_kind@4
    movzx edi, al
    or esp, esp                         ; ZF = 0
@@:
    ret
jbv_get_field PROC EXPORT           ; (vm, id, receiver, out): a reference result is retained
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    call field_args
    mov eax, S_BAD_ARG
    jz gf_ret
    cmp DWORD PTR [ebp+20], 0
    je gf_ret
    mov edx, [ebp+16]
    call field_location
    test eax, eax
    jnz gf_ret
    mov esi, [edx]
    xor ecx, ecx
    cmp edi, K_LONG
    je @F
    cmp edi, K_DOUBLE
    jne gf_value
@@:
    mov ecx, [edx+4]
gf_value:
    push ecx
    cmp edi, K_REF
    jne @F
    push esi
    push ebx
    call jbv_retain
    add esp, 8
@@:
    pop ecx
    test eax, eax
    jnz gf_ret
    mov edx, [ebp+20]
    mov [edx], esi
    mov [edx+4], ecx
gf_ret:
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
jbv_get_field ENDP
jbv_set_field PROC EXPORT           ; (vm, id, receiver, value)
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    call field_args
    mov eax, S_BAD_ARG
    jz sf_ret
    cmp edi, K_REF
    jne sf_locate
    mov eax, [esi+4]                    ; a reference: checked, and held across initialization
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    mov edx, [ebp+20]
    mov ecx, ebx
    call @jbv_check_reference@16
    test eax, eax
    jnz sf_ret
    push DWORD PTR [ebp+20]
    push ebx
    call jbv_retain
    add esp, 8
    test eax, eax
    jnz sf_ret
sf_locate:
    mov edx, [ebp+16]
    call field_location
    test eax, eax
    jnz sf_release
    mov ecx, [ebp+20]
    test edi, edi
    jnz @F
    push edx
    mov eax, [esi+4]
    mov eax, [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    movzx edx, BYTE PTR [eax]
    call @jbv_narrow@8
    pop edx
    mov ecx, eax
@@:
    mov [edx], ecx
    cmp edi, K_LONG
    je @F
    cmp edi, K_DOUBLE
    jne sf_stored
@@:
    mov eax, [ebp+24]
    mov [edx+4], eax
sf_stored:
    xor eax, eax
    cmp edi, K_REF
    jne sf_ret
    cmp DWORD PTR [ebp+16], 0
    je sf_release
    push 0
    push esp
    mov edx, [ebp+16]
    mov ecx, ebx
    call @jbv_object@12
    pop edx
    test eax, eax
    jnz @F
    push DWORD PTR [ebp+20]
    mov ecx, ebx
    call @jbv_barrier_checked@12
@@:
    xor eax, eax
sf_release:
    cmp edi, K_REF
    jne sf_ret
    push eax
    push DWORD PTR [ebp+20]
    push ebx
    call jbv_release
    add esp, 8
    pop eax
sf_ret:
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
jbv_set_field ENDP

; [ebp+8] vm, ref, start, count -> eax status, ebx = vm, esi = the array, edi = its element data at start
array_range:
    mov ebx, [ebp+8]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz ar_ret
    push 0
    push esp
    mov edx, [ebp+12]
    mov ecx, ebx
    call @jbv_object@12
    pop esi
    test eax, eax
    jnz ar_ret
    mov ecx, [esi]
    mov eax, S_BAD_ARG
    cmp BYTE PTR [ecx+C_ARRAY_KIND], 0
    je ar_ret
    mov eax, S_BOUNDS
    mov ecx, [esi-4]
    mov edx, [ebp+16]
    cmp edx, ecx
    ja ar_ret
    sub ecx, edx
    cmp [ebp+20], ecx
    ja ar_ret
    lea edi, [esi+edx*4+DATA0]
    xor eax, eax
ar_ret:
    ret
array_frame MACRO
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
ENDM
array_leave MACRO
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
ENDM
jbv_array_info PROC EXPORT          ; (vm, ref, length, kind)
    array_frame
    mov eax, S_BAD_ARG
    mov ecx, [ebp+16]
    test ecx, ecx
    jz ai_ret
    mov edx, [ebp+20]
    push edx
    push ecx
    mov DWORD PTR [ebp+16], 0           ; start 0, count 0 (the arguments are reused)
    mov DWORD PTR [ebp+20], 0
    call array_range
    pop ecx
    pop edx
    test eax, eax
    jnz ai_ret
    mov eax, [esi-4]
    mov [ecx], eax
    xor eax, eax
    test edx, edx
    jz ai_ret
    mov ecx, [esi]
    mov cl, [ecx+C_ARRAY_KIND]
    mov [edx], cl
ai_ret:
    array_leave
jbv_array_info ENDP
jbv_array_read PROC EXPORT          ; (vm, ref, start, count, out): references are retained
    array_frame
    mov eax, S_BAD_ARG
    cmp DWORD PTR [ebp+20], 0
    je @F
    cmp DWORD PTR [ebp+24], 0
    je ard_ret
@@:
    call array_range
    test eax, eax
    jnz ard_ret
    mov eax, [esi]
    cmp BYTE PTR [eax+C_ARRAY_KIND], 'L'
    je ard_refs
    xor edi, edi
@@:
    cmp edi, [ebp+20]
    jae ard_ok
    mov eax, [esi]
    movzx eax, BYTE PTR [eax+C_ARRAY_KIND]
    push eax
    mov edx, [ebp+16]
    add edx, edi
    mov ecx, esi
    call @jbv_array_get@12
    mov ecx, [ebp+24]
    mov [ecx+edi*8], eax
    mov [ecx+edi*8+4], edx
    inc edi
    jmp @B
ard_refs:
    xor esi, esi                        ; retained so far
@@:
    cmp esi, [ebp+20]
    jae ard_copy
    push DWORD PTR [edi+esi*4]
    push ebx
    call jbv_retain
    add esp, 8
    test eax, eax
    jnz ard_undo
    inc esi
    jmp @B
ard_undo:
    push eax
@@:
    test esi, esi
    jz @F
    dec esi
    push DWORD PTR [edi+esi*4]
    push ebx
    call jbv_release
    add esp, 8
    jmp @B
@@:
    pop eax
    jmp ard_ret
ard_copy:
    mov ecx, [ebp+20]
    mov edx, [ebp+24]
    jecxz ard_ok
@@:
    mov eax, [edi]
    add edi, 4
    mov [edx], eax
    mov DWORD PTR [edx+4], 0
    add edx, 8
    loop @B
ard_ok:
    xor eax, eax
ard_ret:
    array_leave
jbv_array_read ENDP
jbv_array_write PROC EXPORT         ; (vm, ref, start, count, values)
    array_frame
    mov eax, S_BAD_ARG
    cmp DWORD PTR [ebp+20], 0
    je @F
    cmp DWORD PTR [ebp+24], 0
    je aw_ret
@@:
    call array_range
    test eax, eax
    jnz aw_ret
    mov eax, [esi]
    cmp BYTE PTR [eax+C_ARRAY_KIND], 'L'
    je aw_refs
    xor edi, edi
aw_value:
    cmp edi, [ebp+20]
    jae aw_ok
    mov eax, [ebp+24]
    mov ecx, [eax+edi*8]
    mov edx, [eax+edi*8+4]
    mov eax, [esi]
    movzx eax, BYTE PTR [eax+C_ARRAY_KIND]
    push edx
    push ecx
    push eax
    mov ecx, eax
    call @jbv_kind@4
    test al, al
    jnz @F                              ; int kinds are narrowed to the element type
    mov edx, [esp]
    mov ecx, [esp+4]
    call @jbv_narrow@8
    mov [esp+4], eax
    mov DWORD PTR [esp+8], 0
@@:
    mov edx, [ebp+16]
    add edx, edi
    mov ecx, esi
    call @jbv_array_set@20
    inc edi
    jmp aw_value
aw_refs:                                ; every element checked before any store
    push edi
    xor edi, edi
aw_check:
    cmp edi, [ebp+20]
    jae aw_checked
    mov eax, [ebp+24]
    mov edx, [eax+edi*8]
    test edx, edx
    jz aw_next
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz aw_fail
    mov ecx, [ecx]
    mov edx, [esi]
    mov edx, [edx+C_COMPONENT]
    call @jbv_assignable@8
    test eax, eax
    mov eax, S_STORE
    jz aw_fail
aw_next:
    inc edi
    jmp aw_check
aw_fail:
    pop edi
    jmp aw_ret
aw_checked:
    pop edi
    xor ecx, ecx
@@:
    cmp ecx, [ebp+20]
    jae aw_ok
    push ecx
    mov eax, [ebp+24]
    mov eax, [eax+ecx*8]
    mov [edi+ecx*4], eax
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_barrier_checked@12
    pop ecx
    inc ecx
    jmp @B
aw_ok:
    xor eax, eax
aw_ret:
    array_leave
jbv_array_write ENDP
END

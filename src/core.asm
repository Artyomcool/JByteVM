; The reduced profiles: without the class library, core has Object's identity, cloning and monitors
; only; text adds strings but no classpath.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_object_bytes@4:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_monitor@16:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_prepare_method@4:PROC

S_OOM         EQU 2
S_UNSUPPORTED EQU 6
S_NOT_FOUND   EQU 7
S_EXCEPTION   EQU 22
DATA0         EQU 4
NATIVE        EQU 100h

.code
; ---- no class library (core and text)
@jbv_classpath_find@20 PROC SYSCALL
    mov eax, S_NOT_FOUND
    ret 12
@jbv_classpath_find@20 ENDP
@jbv_classpath_load@16 PROC SYSCALL
    mov eax, S_NOT_FOUND
    ret 8
@jbv_classpath_load@16 ENDP
@jbv_constant@20 PROC SYSCALL       ; no MethodType/MethodHandle constants
    mov eax, S_UNSUPPORTED
    ret 12
@jbv_constant@20 ENDP

IF JBV_PROFILE_CORE
.const
o_names DB 6, '<init>', 3, '()V', 6, 'equals', 21, '(Ljava/lang/Object;)Z', 8, 'hashCode', 3, '()I'
    DB 5, 'clone', 20, '()Ljava/lang/Object;', 6, 'notify', 3, '()V', 9, 'notifyAll', 3, '()V'
n_cloneable DB 'java/lang/Cloneable'
n_clone_error DB 'java/lang/CloneNotSupportedException', 0
.code
; JbvStatus JBV_CALL core_native(vm, user, a, count, out): equals 1, hashCode 2, clone 3, notify 4
core_native PROC
    push ebx
    push esi
    push edi
    mov ebx, [esp+16]
    mov esi, [esp+24]
    mov edi, [esp+32]
    mov eax, [esp+20]
    xor ecx, ecx
    mov [edi+4], ecx
    cmp eax, 1
    jne @F
    mov eax, [esi]
    cmp eax, [esi+4]
    sete cl
    mov [edi], ecx
    xor eax, eax
    jmp cn_ret
@@:
    cmp eax, 2
    jne @F
    mov eax, [esi]
    mov [edi], eax
    xor eax, eax
    jmp cn_ret
@@:
    cmp eax, 4
    jne cn_clone
    push 0
    push DWORD PTR [esi]
    xor edx, edx
    mov ecx, ebx
    call @jbv_monitor@16
    jmp cn_ret
cn_clone:                               ; Cloneable objects and arrays: a shallow copy
    push 0
    push esp
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz cn_drop
    push 19
    push OFFSET n_cloneable
    mov ecx, ebx
    call @jbv_find_class@12
    mov edx, eax
    mov ecx, [esp]
    mov ecx, [ecx]
    call @jbv_assignable@8
    test eax, eax
    jnz @F
    push S_EXCEPTION
    push 0
    mov edx, OFFSET n_clone_error
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp cn_drop
@@:
    pop eax                             ; the object
    mov edx, [eax]
    xor ecx, ecx
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    je @F
    mov ecx, [eax-4]
@@:
    push edi                            ; the new ref in *out
    push ecx
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz cn_ret
    push 0
    push esp
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    push 0
    push esp
    mov edx, [edi]
    mov ecx, ebx
    call @jbv_object@12
    pop edx                             ; the copy
    mov ecx, [esp]
    call @jbv_object_bytes@4
    mov ecx, eax
    pop esi
    add esi, DATA0
    push edi
    lea edi, [edx+DATA0]
    rep movsb
    pop edi
    xor eax, eax
    jmp cn_ret
cn_drop:
    pop ecx
cn_ret:
    pop edi
    pop esi
    pop ebx
    ret
core_native ENDP
@jbv_library_object@8 PROC SYSCALL  ; ecx vm, edx class: java/lang/Object's natives
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    mov edx, [edi+C_METHODS]
    call @jbv_free@8
    mov DWORD PTR [edi+C_METHODS], 0
    mov WORD PTR [edi+C_METHOD_COUNT], 0
    mov edx, 6*M_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jnz @F
    mov eax, S_OOM
    jmp lo_ret
@@:
    mov [edi+C_METHODS], eax
    mov WORD PTR [edi+C_METHOD_COUNT], 6
    mov edi, eax
    mov esi, OFFSET o_names
    xor ebx, ebx                        ; i
lo_method:
    movzx ecx, BYTE PTR [esi]
    inc esi
    mov [edi+M_NAME+TEXT_DATA], esi
    mov [edi+M_NAME+TEXT_SIZE], cx
    add esi, ecx
    movzx ecx, BYTE PTR [esi]
    inc esi
    mov [edi+M_DESCRIPTOR+TEXT_DATA], esi
    mov [edi+M_DESCRIPTOR+TEXT_SIZE], cx
    add esi, ecx
    mov eax, NATIVE or 1                ; clone is protected
    cmp ebx, 3
    jne @F
    mov eax, NATIVE or 4
@@:
    mov [edi+M_FLAGS], ax
    mov al, 3                           ; <init>: the no-op intrinsic
    test ebx, ebx
    jnz @F
    mov al, 1
@@:
    mov [edi+M_INTRINSIC], al
    mov DWORD PTR [edi+M_NATIVE_SLOTS], OFFSET core_native
    mov eax, ebx                        ; notifyAll as notify
    cmp eax, 5
    jne @F
    mov eax, 4
@@:
    mov [edi+M_NATIVE_USER], eax
    mov ecx, edi
    call @jbv_prepare_method@4
    add edi, M_SIZEOF
    inc ebx
    cmp ebx, 6
    jb lo_method
    xor eax, eax
lo_ret:
    pop edi
    pop esi
    pop ebx
    ret
@jbv_library_object@8 ENDP
@jbv_library_id@8 PROC SYSCALL      ; no built-in library classes
    xor eax, eax
    ret 8
@jbv_library_id@8 ENDP
@jbv_library_class@16 PROC SYSCALL
    mov eax, S_NOT_FOUND
    ret 8
@jbv_library_class@16 ENDP
@jbv_library_initialize@8 PROC SYSCALL
    xor eax, eax
    ret
@jbv_library_initialize@8 ENDP
@jbv_literal@16 PROC SYSCALL        ; no String or Class literals
    mov eax, S_UNSUPPORTED
    ret 8
@jbv_literal@16 ENDP
@jbv_mirror@12 PROC SYSCALL
    mov eax, S_UNSUPPORTED
    ret 4
@jbv_mirror@12 ENDP
jbv_string_new_utf16 PROC EXPORT    ; the string API without strings
jbv_string_new_utf16 ENDP
jbv_string_new_utf8 PROC EXPORT
jbv_string_new_utf8 ENDP
jbv_string_length PROC EXPORT
jbv_string_length ENDP
jbv_string_read_utf16 PROC EXPORT
jbv_string_read_utf16 ENDP
jbv_string_read_utf8 PROC EXPORT
    mov eax, S_UNSUPPORTED
    ret
jbv_string_read_utf8 ENDP
ENDIF
END

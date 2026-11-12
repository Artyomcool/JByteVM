; Values between Java and C: Class
; mirrors, String -> class-file text, descriptor -> class, boxing and unboxing.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_string_view@12:PROC
EXTERN SYSCALL @jbv_primitive_mirror@12:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_narrow@8:PROC
EXTERN SYSCALL @jbv_reference_type@8:PROC
EXTERN SYSCALL @jbv_check_reference@16:PROC
EXTERN jbv_numeric:PROC

S_BAD_ARG  EQU 1
S_OOM      EQU 2
S_NOT_FOUND EQU 7
S_CAST     EQU 16
B_CLASS    EQU 2
DATA0      EQU 4

.const
codes    DB 'ZBCSIJFDV'
; the wrappers in codes order: counted names
wrappers DB 17, 'java/lang/Boolean', 14, 'java/lang/Byte', 19, 'java/lang/Character', 15, 'java/lang/Short'
         DB 17, 'java/lang/Integer', 14, 'java/lang/Long', 15, 'java/lang/Float', 16, 'java/lang/Double', 14, 'java/lang/Void'
n_value  DB 'valueOf'

.code
; eax = index -> ecx = the wrapper's name, edx = its length
wrapper:
    mov ecx, OFFSET wrappers
wr_next:
    movzx edx, BYTE PTR [ecx]
    inc ecx
    dec eax
    js wr_ret
    add ecx, edx
    jmp wr_next
wr_ret:
    ret
; al = a primitive descriptor char -> eax = its slot kind index for conversions: I 0, J 1, F 2, D 3
conversion_index:
    cmp al, 'J'
    je ci_long
    cmp al, 'F'
    je ci_float
    cmp al, 'D'
    je ci_double
    xor eax, eax
    ret
ci_long:
    mov eax, 1
    ret
ci_float:
    mov eax, 2
    ret
ci_double:
    mov eax, 3
    ret
@jbv_mirror_type@8 PROC SYSCALL     ; ecx vm, edx ref -> the class of a Class object, or 0
    push 0
    push esp
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz mt_none
    mov eax, [ecx]
    cmp BYTE PTR [eax+C_BUILTIN], B_CLASS
    jne mt_none
    mov eax, [ecx+DATA0]
    ret
mt_none:
    xor eax, eax
    ret
@jbv_mirror_type@8 ENDP
; a String as class-file text (MUTF-8: NUL as C0 80), at most 65535 bytes, in a new block
@jbv_text_bytes@12 PROC SYSCALL     ; ecx vm, edx ref, [esp+4] out
    push ebx
    push esi
    push edi
    mov ebx, ecx
    sub esp, 8
    push esp
    call @jbv_string_view@12
    pop esi                             ; the view
    pop ecx
    test eax, eax
    jnz tb_ret
    push esi
    push ecx
    xor edx, edx                        ; the bytes
    jecxz tb_counted
tb_count:
    movzx eax, WORD PTR [esi]
    add esi, 2
    inc edx
    dec eax                             ; 1..127: one byte
    cmp eax, 127
    jb tb_count_next
    inc edx
    cmp WORD PTR [esi-2], 2048          ; 0 and 128..2047: two
    jb tb_count_next
    inc edx
tb_count_next:
    cmp edx, 0FFFFh
    ja tb_bad
    loop tb_count
tb_counted:
    push edx
    mov ecx, ebx
    call @jbv_alloc@8
    pop edx
    pop ecx
    pop esi
    test eax, eax
    jz tb_oom
    mov edi, eax
    mov ebx, [esp+16]
    mov [ebx+TEXT_DATA], eax
    mov [ebx+TEXT_SIZE], dx
    jecxz tb_ok
tb_char:
    movzx eax, WORD PTR [esi]
    add esi, 2
    lea edx, [eax-1]
    cmp edx, 127
    jae tb_wide
    stosb
    jmp tb_next
tb_wide:
    mov edx, eax
    cmp eax, 2048
    jb tb_two
    shr eax, 12
    or al, 0E0h
    stosb
    mov eax, edx
    shr eax, 6
    and al, 3Fh
    or al, 80h
    jmp tb_last
tb_two:
    shr eax, 6
    or al, 0C0h
tb_last:
    stosb
    mov eax, edx
    and al, 3Fh
    or al, 80h
    stosb
tb_next:
    loop tb_char
tb_ok:
    xor eax, eax
    jmp tb_ret
tb_bad:
    add esp, 8
    mov eax, S_BAD_ARG
    jmp tb_ret
tb_oom:
    mov eax, S_OOM
tb_ret:
    pop edi
    pop esi
    pop ebx
    ret 4
@jbv_text_bytes@12 ENDP
; the class of a field/parameter descriptor: a primitive's Class, else L...; or an array
@jbv_type_class@16 PROC SYSCALL     ; ecx vm, edx out, [esp+4] descriptor
    push ebx
    push esi
    mov ebx, ecx
    mov esi, edx
    mov eax, [esp+12]
    movzx ecx, WORD PTR [esp+16]
    cmp ecx, 1
    jne tc_reference
    push 0
    push esp
    movzx edx, BYTE PTR [eax]
    mov ecx, ebx
    call @jbv_primitive_mirror@12
    pop edx
    test eax, eax
    jnz tc_ret
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [esi], eax
    xor eax, eax
    jmp tc_ret
tc_reference:
    jecxz tc_resolve
    cmp BYTE PTR [eax], 'L'
    jne tc_resolve
    inc eax
    sub ecx, 2
tc_resolve:
    push ecx
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_resolve_class@16
tc_ret:
    pop esi
    pop ebx
    ret 8
@jbv_type_class@16 ENDP

; a primitive value boxed by its wrapper's valueOf(primitive)
B_ARGS  EQU -8        ; two slots
B_RES   EQU -16       ; uint64_t result
B_TYPE  EQU -20
B_CODE  EQU -24
@jbv_box@20 PROC SYSCALL            ; ecx vm, edx code, [ebp+8] bits, [ebp+16] out
    push ebp
    mov ebp, esp
    sub esp, 24
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov [ebp+B_CODE], edx
    mov eax, edx
    mov edi, OFFSET codes
    mov ecx, 8                          ; not V
    repne scasb
    mov eax, S_BAD_ARG
    jne bx_ret
    sub edi, OFFSET codes+1
    mov eax, edi
    call wrapper
    push edx
    push ecx
    lea edx, [ebp+B_TYPE]
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz bx_ret
    mov esi, [ebp+B_TYPE]
    movzx ecx, WORD PTR [esi+C_METHOD_COUNT]
    mov edi, [esi+C_METHODS]
    jecxz bx_none
bx_method:
    cmp WORD PTR [edi+M_NAME+TEXT_SIZE], 7
    jne bx_next
    mov eax, [edi+M_DESCRIPTOR+TEXT_DATA]   ; (code)...
    mov dl, [ebp+B_CODE]
    cmp [eax+1], dl
    jne bx_next
    cmp BYTE PTR [eax+2], ')'
    jne bx_next
    push ecx
    push esi
    push edi
    mov esi, [edi+M_NAME+TEXT_DATA]
    mov edi, OFFSET n_value
    mov ecx, 7
    repe cmpsb
    pop edi
    pop esi
    pop ecx
    je bx_found
bx_next:
    add edi, M_SIZEOF
    loop bx_method
bx_none:
    mov eax, S_NOT_FOUND
    jmp bx_ret
bx_found:
    mov eax, [ebp+8]
    mov [ebp+B_ARGS], eax
    mov eax, [ebp+12]
    mov [ebp+B_ARGS+4], eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz bx_ret
    lea eax, [ebp+B_RES]
    push eax
    mov eax, 1                          ; one slot, two for long and double
    cmp BYTE PTR [ebp+B_CODE], 'J'
    je @F
    cmp BYTE PTR [ebp+B_CODE], 'D'
    jne bx_width
@@:
    inc eax
bx_width:
    push eax
    push 0
    lea eax, [ebp+B_ARGS]
    push eax
    push edi
    mov edx, esi
    mov ecx, ebx
    call @jbv_execute@28
    test eax, eax
    jnz bx_ret
    mov ecx, [ebp+16]
    mov edx, [ebp+B_RES]
    mov [ecx], edx
bx_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 12
@jbv_box@20 ENDP

; a wrapper's value as the primitive target (implicit conversions only widen, as the JLS)
U_TARGET EQU 8
U_EXPL   EQU 12
U_OUT    EQU 16
U_SRC    EQU -4
U_BITS   EQU -12      ; uint64_t
@jbv_unbox@20 PROC SYSCALL          ; ecx vm, edx ref, [ebp+8] target, [ebp+12] explicit, [ebp+16] out
    push ebp
    mov ebp, esp
    sub esp, 12
    push ebx
    push esi
    push edi
    mov ebx, ecx
    test edx, edx
    jnz @F
    cmp DWORD PTR [ebp+U_EXPL], 0
    je @F
    xor eax, eax                        ; an explicit cast of null: 0
    mov ecx, [ebp+U_OUT]
    mov [ecx], eax
    mov [ecx+4], eax
    jmp ub_ret
@@:
    push 0
    push esp
    call @jbv_object@12
    pop esi                             ; the object
    test eax, eax
    jnz ub_ret
    xor edi, edi                        ; which wrapper
ub_wrapper:
    cmp edi, 8
    je ub_cast
    mov eax, edi
    call wrapper
    mov eax, [esi]
    cmp dx, WORD PTR [eax+C_NAME+TEXT_SIZE]
    jne ub_next_wrapper
    push esi
    push edi
    mov esi, [eax+C_NAME+TEXT_DATA]
    mov edi, ecx
    mov ecx, edx
    repe cmpsb
    pop edi
    pop esi
    je ub_found
ub_next_wrapper:
    inc edi
    jmp ub_wrapper
ub_found:
    movzx eax, BYTE PTR [codes+edi]
    mov [ebp+U_SRC], eax
    mov dl, [ebp+U_TARGET]
    cmp DWORD PTR [ebp+U_EXPL], 0
    jne ub_convert
    cmp al, dl
    je ub_convert
    cmp al, 'Z'
    je ub_cast
    cmp dl, 'Z'
    je ub_cast
    cmp dl, 'B'
    je ub_cast
    cmp dl, 'C'
    je ub_cast
    cmp dl, 'S'
    jne @F
    cmp al, 'B'
    jne ub_cast
@@:
    cmp dl, 'I'
    jne @F
    cmp al, 'J'
    je ub_cast
    cmp al, 'F'
    je ub_cast
    cmp al, 'D'
    je ub_cast
@@:
    cmp dl, 'J'
    jne @F
    cmp al, 'F'
    je ub_cast
    cmp al, 'D'
    je ub_cast
@@:
    cmp dl, 'F'
    jne ub_convert
    cmp al, 'D'
    je ub_cast
ub_convert:
    mov eax, [esi+DATA0]                ; the value's slot bits
    mov [ebp+U_BITS], eax
    mov DWORD PTR [ebp+U_BITS+4], 0
    mov eax, [ebp+U_SRC]
    call conversion_index
    mov edi, eax                        ; row
    cmp edi, 1
    je @F
    cmp edi, 3
    jne ub_bits
@@:
    mov eax, [esi+DATA0+4]
    mov [ebp+U_BITS+4], eax
ub_bits:
    movzx eax, BYTE PTR [ebp+U_TARGET]
    call conversion_index               ; col
    cmp eax, edi
    je ub_narrow
    lea ecx, [edi+edi*2]                ; op = 133 + row * 3 + col - (col > row)
    lea ecx, [ecx+eax+133]
    cmp eax, edi
    jbe @F
    dec ecx
@@:
    lea eax, [ebp+U_BITS]
    push eax
    push 0
    push 0
    push DWORD PTR [ebp+U_BITS+4]
    push DWORD PTR [ebp+U_BITS]
    push ecx
    call jbv_numeric
    add esp, 24
    test eax, eax
    jnz ub_ret
ub_narrow:
    movzx eax, BYTE PTR [ebp+U_TARGET]
    call conversion_index
    test eax, eax
    jnz ub_store
    movzx edx, BYTE PTR [ebp+U_TARGET]
    mov ecx, [ebp+U_BITS]
    call @jbv_narrow@8
    mov [ebp+U_BITS], eax
    mov DWORD PTR [ebp+U_BITS+4], 0
ub_store:
    mov ecx, [ebp+U_OUT]
    mov eax, [ebp+U_BITS]
    mov [ecx], eax
    mov eax, [ebp+U_BITS+4]
    mov [ecx+4], eax
    xor eax, eax
    jmp ub_ret
ub_cast:
    mov eax, S_CAST
ub_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 12
@jbv_unbox@20 ENDP
; a reference checked against a reference type, else unboxed to a primitive one
@jbv_from_object@20 PROC SYSCALL    ; ecx vm, edx ref, [esp+4] type, [esp+12] out
    push ebx
    push esi
    mov ebx, ecx
    mov esi, edx
    push DWORD PTR [esp+16]
    push DWORD PTR [esp+16]
    call @jbv_reference_type@8
    test eax, eax
    jz fo_unbox
    push DWORD PTR [esp+16]
    push DWORD PTR [esp+16]
    mov edx, esi
    mov ecx, ebx
    call @jbv_check_reference@16
    test eax, eax
    jnz fo_ret
    mov ecx, [esp+20]
    mov [ecx], esi
    mov DWORD PTR [ecx+4], 0
    jmp fo_ret
fo_unbox:
    push DWORD PTR [esp+20]
    push 0
    mov eax, [esp+20]
    movzx eax, BYTE PTR [eax]
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_unbox@20
fo_ret:
    pop esi
    pop ebx
    ret 12
@jbv_from_object@20 ENDP
END

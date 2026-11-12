; The interpreter's slow bytecodes for x86 (slow_op in interpreter.c is the reference and
; serves x64): everything that may resolve, allocate, call or throw, wide and two-slot
; locals, long/float/double arithmetic and switches. The frame is synced on entry.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
EXTERN SYSCALL @jbv_constant@20:PROC
EXTERN SYSCALL @jbv_literal@16:PROC
EXTERN SYSCALL @jbv_numeric_types@4:PROC
EXTERN SYSCALL @jbv_link_member@16:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_narrow@8:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_virtual_method@12:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC
EXTERN SYSCALL @jbv_text_is@12:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_class_constant@16:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_multi_array@20:PROC
EXTERN SYSCALL @jbv_monitor@16:PROC
IF JBV_PROFILE_FULL
EXTERN SYSCALL @jbv_signature@16:PROC
EXTERN SYSCALL @jbv_polymorphic@28:PROC
ENDIF
EXTERN jbv_numeric:PROC

S_UNSUPPORTED EQU 6
S_INDY      EQU 5
S_LINKAGE   EQU 8
S_LIMIT     EQU 10
S_NULL      EQU 12
S_NEGATIVE  EQU 14
S_CAST      EQU 16
S_EXCEPTION EQU 22
K_INT       EQU 0
K_REF       EQU 1
K_LONG      EQU 2
K_FLOAT     EQU 4
K_DOUBLE    EQU 5
K_TOP       EQU 7
ACC_STATIC  EQU 8
ACC_SUPER   EQU 20h
ACC_INTERFACE EQU 200h
ACC_ABSTRACT EQU 400h
DATA0       EQU 4

; the frame: [ebp+8] frame, op, state, stack, stack_refs, locals, local_refs
P_FRAME  EQU 8
P_OP     EQU 12
P_STATE  EQU 16
P_STACK  EQU 20
P_SREFS  EQU 24
P_LOCALS EQU 28
P_LREFS  EQU 32
L_CLASS  EQU -4
L_CODE   EQU -8
L_START  EQU -12
L_PC     EQU -16
L_A      EQU -20      ; per op
L_B      EQU -24
L_C      EQU -28
L_D      EQU -32
L_E      EQU -36
L_F      EQU -40
L_OUT    EQU -48      ; uint64_t
L_G      EQU -52
L_H      EQU -56

.const
kinds_by_type DB K_INT, K_LONG, K_FLOAT, K_DOUBLE, K_REF
array_codes   DB 'ZCFDBSIJ'
n_icce DB 'java/lang/IncompatibleClassChangeError', 0
n_ame  DB 'java/lang/AbstractMethodError', 0
n_ie   DB 'java/lang/InstantiationError', 0
s_init DB '<init>', 0
IF JBV_PROFILE_FULL
s_exact DB 'invokeExact', 0
ENDIF
; op -> handler (0: unsupported)
op_handler LABEL BYTE
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 2, 3, 3, 0, 0, 4, 4, 4, 0
    DB 5, 5, 5, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 0, 0, 0, 0, 0, 5, 5, 5
    DB 5, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    DB 0, 0, 6, 6, 6, 6, 6, 0, 0, 7, 7, 7, 0, 7, 7, 7, 0, 7, 7, 7, 0, 7
    DB 7, 7, 0, 7, 7, 7, 0, 7, 7, 7, 0, 7, 0, 7, 0, 7, 0, 7, 0, 7, 0, 7
    DB 0, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 0, 0, 0, 7, 7, 7, 7, 7, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 0, 0, 0, 0
    DB 0, 0, 9, 9, 9, 9, 10, 10, 10, 10, 11, 12, 12, 12, 0, 14, 15, 15, 16, 16, 5, 13

.code
; eax = code[pc++] / the next big-endian u16
fetch1:
    mov eax, [ebp+L_PC]
    inc DWORD PTR [ebp+L_PC]
    add eax, [ebp+L_CODE]
    movzx eax, BYTE PTR [eax]
    ret
fetch2:
    mov eax, [ebp+L_PC]
    add DWORD PTR [ebp+L_PC], 2
    add eax, [ebp+L_CODE]
    movzx eax, WORD PTR [eax]
    xchg al, ah
    ret
; ecx = a code offset -> eax = the big-endian int32 there
be32:
    mov eax, [ebp+L_CODE]
    mov eax, [eax+ecx]
    bswap eax
    ret
; ecx = a kind -> ecx = its slots (1 or 2)
width_of:
    cmp cl, K_LONG
    je @F
    cmp cl, K_DOUBLE
    je @F
    mov ecx, 1
    ret
@@:
    mov ecx, 2
    ret
; eax:edx = the value, cl = its kind: pushed (edi = sp)
push_value:
    push esi
    mov esi, [ebp+P_STACK]
    mov [esi+edi*4], eax
    mov esi, [ebp+P_SREFS]
    cmp cl, K_LONG
    je pv_wide
    cmp cl, K_DOUBLE
    je pv_wide
    cmp cl, K_REF
    sete BYTE PTR [esi+edi]
    inc edi
    pop esi
    ret
pv_wide:
    mov BYTE PTR [esi+edi], 0
    mov BYTE PTR [esi+edi+1], 0
    mov esi, [ebp+P_STACK]
    mov [esi+edi*4+4], edx
    add edi, 2
    pop esi
    ret
; eax = a slot address, cl = the kind -> eax:edx = its bits
slot_bits:
    mov edx, [eax+4]
    mov eax, [eax]
    cmp cl, K_LONG
    je @F
    cmp cl, K_DOUBLE
    je @F
    xor edx, edx
@@:
    ret

@jbv_slow_op@36 PROC SYSCALL        ; ecx vm, edx class, [ebp+8] frame, op, state, stack, refs, locals, refs
    push ebp
    mov ebp, esp
    sub esp, 56
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov [ebp+L_CLASS], edx
    mov eax, [ebp+P_FRAME]
    mov ecx, [eax+FR_PC]
    mov [ebp+L_START], ecx
    mov eax, [eax+FR_METHOD]
    mov eax, [eax+M_CODE]
    mov [ebp+L_CODE], eax
    mov eax, [ebp+P_STATE]
    mov ecx, [eax]
    mov [ebp+L_PC], ecx
    mov edi, [eax+4]                    ; sp
    movzx eax, BYTE PTR [ebp+P_OP]
    xor ecx, ecx
    cmp eax, 197
    ja @F
    movzx ecx, BYTE PTR [op_handler+eax]
@@:
    jmp DWORD PTR [handlers+ecx*4]

so_lconst:
    movzx eax, BYTE PTR [ebp+P_OP]
    sub eax, 9
    xor edx, edx
    mov cl, K_LONG
    jmp so_push
so_fconst:
    movzx eax, BYTE PTR [ebp+P_OP]
    sub eax, 11
    jz @F
    mov eax, 3F800000h * 1              ; 1.0f, 2.0f
    cmp BYTE PTR [ebp+P_OP], 13
    jne @F
    mov eax, 40000000h
@@:
    xor edx, edx
    mov cl, K_FLOAT
    jmp so_push
so_dconst:
    xor eax, eax
    xor edx, edx
    cmp BYTE PTR [ebp+P_OP], 15
    jne @F
    mov edx, 3FF00000h
@@:
    mov cl, K_DOUBLE
    jmp so_push

so_ldc:
    cmp BYTE PTR [ebp+P_OP], 18
    jne @F
    call fetch1
    jmp so_ldc_index
@@:
    call fetch2
so_ldc_index:
    mov esi, eax                        ; the index
    imul edx, eax, CP_SIZEOF
    mov ecx, [ebp+L_CLASS]
    add edx, [ecx+C_POOL]
    mov al, [edx+CP_TAG]
    cmp al, 15
    je so_ldc_dynamic
    cmp al, 16
    je so_ldc_dynamic
    cmp BYTE PTR [ebp+P_OP], 20
    jne so_ldc_word
    mov cl, K_LONG
    cmp al, 5
    je @F
    mov cl, K_DOUBLE
@@:
    mov eax, [edx+CP_BITS]
    mov edx, [edx+CP_BITS_HI]
    jmp so_push
so_ldc_word:
    mov cl, K_INT
    cmp al, 3
    je @F
    mov cl, K_FLOAT
    cmp al, 4
    jne so_ldc_literal
@@:
    mov eax, [edx+CP_BITS]
    xor edx, edx
    jmp so_push
so_ldc_literal:                         ; String and Class
    lea eax, [ebp+L_A]
    push eax
    push esi
    mov edx, [ebp+L_CLASS]
    mov ecx, ebx
    call @jbv_literal@16
    test eax, eax
    jnz so_done
    mov eax, [ebp+L_A]
    mov cl, K_REF
    jmp so_push
so_ldc_dynamic:                         ; MethodType and MethodHandle
    lea eax, [ebp+L_A]
    push eax
    lea eax, [ebp+L_OUT]
    push eax
    push esi
    mov edx, [ebp+L_CLASS]
    mov ecx, ebx
    call @jbv_constant@20
    test eax, eax
    jnz so_done
    mov eax, [ebp+L_OUT]
    mov edx, [ebp+L_OUT+4]
    mov cl, [ebp+L_A]
    jmp so_push

so_locals:                              ; wide, two-slot and the remaining loads/stores
    movzx eax, BYTE PTR [ebp+P_OP]
    cmp eax, 196
    jne @F
    call fetch1
    mov [ebp+L_A], eax                  ; the sub-op
    call fetch2
    mov esi, eax
    jmp so_local_op
@@:
    mov [ebp+L_A], eax
    cmp eax, 26
    jb so_local_byte
    cmp eax, 45
    ja @F
    sub eax, 26                         ; xload_n
    mov esi, eax
    and esi, 3
    shr eax, 2
    add eax, 21
    mov [ebp+L_A], eax
    jmp so_local_op
@@:
    cmp eax, 59
    jb so_local_byte
    sub eax, 59                         ; xstore_n
    mov esi, eax
    and esi, 3
    shr eax, 2
    add eax, 54
    mov [ebp+L_A], eax
    jmp so_local_op
so_local_byte:
    call fetch1
    mov esi, eax
so_local_op:                            ; [L_A] the sub-op, esi the local
    mov eax, [ebp+L_A]
    cmp eax, 132
    jne @F
    call fetch2                         ; wide iinc
    movsx eax, ax
    mov ecx, [ebp+P_LOCALS]
    add [ecx+esi*4], eax
    jmp so_ok
@@:
    xor edx, edx                        ; the store flag
    sub eax, 21
    cmp eax, 54-21
    jb @F
    sub eax, 54-21
    inc edx
@@:
    cmp eax, 4                          ; (other wide sub-ops: references)
    jbe @F
    mov eax, 4
@@:
    movzx ecx, BYTE PTR [kinds_by_type+eax]
    test edx, edx
    jnz so_store_local
    mov eax, [ebp+P_LOCALS]
    lea eax, [eax+esi*4]
    call slot_bits
    jmp so_push
so_store_local:
    call width_of
    sub edi, ecx
    push edi
    mov eax, [ebp+P_LOCALS]
    lea eax, [eax+esi*4]
    mov edx, [ebp+P_LREFS]
    add edx, esi
@@:
    push ecx
    mov ecx, [ebp+P_STACK]
    mov ecx, [ecx+edi*4]
    mov [eax], ecx
    mov ecx, [ebp+P_SREFS]
    mov cl, [ecx+edi]
    mov [edx], cl
    pop ecx
    add eax, 4
    inc edx
    inc edi
    loop @B
    pop edi
    jmp so_ok

so_dup:                                 ; dup_x1, dup_x2, dup2, dup2_x1, dup2_x2
    movzx eax, BYTE PTR [ebp+P_OP]
    mov ecx, 1
    lea edx, [eax-89]                   ; shift
    cmp eax, 92
    jb @F
    inc ecx
    lea edx, [eax-92]
@@:
    mov [ebp+L_E], ecx                  ; copies
    mov [ebp+L_F], edx
    mov esi, [ebp+P_STACK]
    mov edx, [ebp+P_SREFS]
    mov eax, edi
    sub eax, ecx
    push DWORD PTR [esi+eax*4]          ; a, ar
    movzx eax, BYTE PTR [edx+eax]
    push eax
    push DWORD PTR [esi+edi*4-4]        ; b, br (two copies)
    movzx eax, BYTE PTR [edx+edi-1]
    push eax
    xor ecx, ecx                        ; i
so_dup_shift:
    cmp ecx, [ebp+L_F]
    jae so_dup_place
    mov eax, edi                        ; sp - 1 - copies - i -> sp - 1 - i
    dec eax
    sub eax, ecx
    push ecx
    mov ecx, eax
    sub ecx, [ebp+L_E]
    push DWORD PTR [esi+ecx*4]
    pop DWORD PTR [esi+eax*4]
    mov cl, [edx+ecx]
    mov [edx+eax], cl
    pop ecx
    inc ecx
    jmp so_dup_shift
so_dup_place:
    pop ecx                             ; br
    pop eax                             ; b
    mov [ebp+L_C], eax
    mov [ebp+L_D], ecx
    pop ecx                             ; ar
    pop eax                             ; a
    push edi
    sub edi, [ebp+L_E]
    sub edi, [ebp+L_F]
    mov [esi+edi*4], eax
    mov [edx+edi], cl
    pop edi
    cmp DWORD PTR [ebp+L_E], 2
    jne @F
    push edi
    dec edi
    sub edi, [ebp+L_F]
    push eax
    mov eax, [ebp+L_C]
    mov [esi+edi*4], eax
    mov al, [ebp+L_D]
    mov [edx+edi], al
    pop eax
    pop edi
@@:
    mov [esi+edi*4], eax
    mov [edx+edi], cl
    inc edi
    cmp DWORD PTR [ebp+L_E], 2
    jne so_ok
    mov eax, [ebp+L_C]
    mov [esi+edi*4], eax
    mov al, [ebp+L_D]
    mov [edx+edi], al
    inc edi
    jmp so_ok

so_numeric:                             ; long/float/double arithmetic, conversions, comparisons
    movzx ecx, BYTE PTR [ebp+P_OP]
    call @jbv_numeric_types@4
    mov [ebp+L_G], eax
    movzx ecx, al
    call width_of
    mov [ebp+L_A], ecx                  ; wa
    xor ecx, ecx
    mov cl, BYTE PTR [ebp+L_G+1]
    cmp cl, K_TOP
    je @F
    call width_of
    jmp so_num_width
@@:
    xor ecx, ecx
so_num_width:
    mov [ebp+L_B], ecx                  ; wb
    lea eax, [ebp+L_OUT]
    push eax
    xor eax, eax
    xor edx, edx
    test ecx, ecx
    jz @F
    mov eax, edi
    sub eax, ecx
    mov edx, [ebp+P_STACK]
    lea eax, [edx+eax*4]
    mov cl, BYTE PTR [ebp+L_G+1]
    call slot_bits
@@:
    push edx
    push eax
    mov eax, edi
    sub eax, [ebp+L_A]
    sub eax, [ebp+L_B]
    mov edx, [ebp+P_STACK]
    lea eax, [edx+eax*4]
    mov cl, BYTE PTR [ebp+L_G]
    call slot_bits
    push edx
    push eax
    movzx eax, BYTE PTR [ebp+P_OP]
    push eax
    call jbv_numeric
    add esp, 24
    test eax, eax
    jnz so_done
    sub edi, [ebp+L_A]
    sub edi, [ebp+L_B]
    mov eax, [ebp+L_OUT]
    mov edx, [ebp+L_OUT+4]
    mov cl, BYTE PTR [ebp+L_G+2]
    jmp so_push

so_switch:                              ; tableswitch, lookupswitch
    mov esi, [ebp+L_START]              ; at = the aligned operands
    add esi, 4
    and esi, NOT 3
    mov ecx, esi
    call be32
    mov [ebp+L_A], eax                  ; the default offset
    dec edi
    mov edx, [ebp+P_STACK]
    mov edx, [edx+edi*4]                ; the key
    cmp BYTE PTR [ebp+P_OP], 170
    jne so_lookup
    lea ecx, [esi+4]
    call be32
    mov [ebp+L_B], eax                  ; low
    lea ecx, [esi+8]
    call be32                           ; high
    cmp edx, [ebp+L_B]
    jl so_jump
    cmp edx, eax
    jg so_jump
    sub edx, [ebp+L_B]
    lea ecx, [esi+edx*4+12]
    call be32
    mov [ebp+L_A], eax
    jmp so_jump
so_lookup:
    lea ecx, [esi+4]
    call be32
    mov [ebp+L_C], eax                  ; hi = npairs
    mov DWORD PTR [ebp+L_B], 0          ; lo
so_probe:
    mov eax, [ebp+L_B]
    cmp eax, [ebp+L_C]
    jae so_jump
    mov eax, [ebp+L_C]
    sub eax, [ebp+L_B]
    shr eax, 1
    add eax, [ebp+L_B]                  ; mid
    mov [ebp+L_D], eax
    lea ecx, [esi+eax*8+8]
    call be32
    cmp edx, eax
    jl so_lower
    jg so_higher
    mov eax, [ebp+L_D]
    lea ecx, [esi+eax*8+12]
    call be32
    mov [ebp+L_A], eax
    jmp so_jump
so_lower:
    mov eax, [ebp+L_D]
    mov [ebp+L_C], eax
    jmp so_probe
so_higher:
    mov eax, [ebp+L_D]
    inc eax
    mov [ebp+L_B], eax
    jmp so_probe
so_jump:
    mov eax, [ebp+L_A]
    test eax, eax
    jg @F
    mov ecx, [ebx+VM_REMAINING]         ; a backward branch spends the budget
    or ecx, [ebx+VM_REMAINING+4]
    mov eax, S_LIMIT
    jz so_done
    sub DWORD PTR [ebx+VM_REMAINING], 1
    sbb DWORD PTR [ebx+VM_REMAINING+4], 0
    mov eax, [ebp+L_A]
@@:
    add eax, [ebp+L_START]
    mov [ebp+L_PC], eax
    jmp so_ok

; edx = an error name: thrown as a LinkageError status
so_throw_linkage:
    push S_LINKAGE
    push 0
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp so_done
so_link:                                ; eax = &link: the member at the u16 index
    push eax
    call fetch2
    push eax
    mov edx, [ebp+L_CLASS]
    mov ecx, ebx
    call @jbv_link_member@16
    ret

so_field:                               ; getstatic, putstatic, getfield, putfield
    lea eax, [ebp+L_A]
    call so_link
    test eax, eax
    jnz so_done
    mov esi, [ebp+L_A]                  ; the link
    mov eax, [esi+LK_MEMBER]
    mov [ebp+L_B], eax                  ; the field
    xor ecx, ecx
    cmp BYTE PTR [ebp+P_OP], 179
    setbe cl                            ; static
    mov [ebp+L_C], ecx
    test WORD PTR [eax+FIELD_FLAGS], ACC_STATIC
    setnz al
    cmp al, cl
    mov edx, OFFSET n_icce
    jne so_throw_linkage
    mov cl, [esi+LK_KIND]
    call width_of
    mov [ebp+L_D], ecx
    xor eax, eax                        ; the store flag
    cmp BYTE PTR [ebp+P_OP], 179
    je @F
    cmp BYTE PTR [ebp+P_OP], 181
    jne so_field_static
@@:
    inc eax
so_field_static:
    mov [ebp+L_E], eax
    cmp DWORD PTR [ebp+L_C], 0
    je so_field_instance
    mov edx, [esi+LK_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz so_done
    mov eax, [esi+LK_OWNER]
    cmp BYTE PTR [eax+C_INIT_STATE], 2
    jne @F
    mov BYTE PTR [esi+LK_READY], 1
@@:
    mov eax, [ebp+L_B]
    add eax, FIELD_VALUE
    mov [ebp+L_F], eax                  ; the location
    mov DWORD PTR [ebp+L_G], 0          ; no object
    jmp so_field_access
so_field_instance:
    mov eax, edi
    dec eax
    cmp DWORD PTR [ebp+L_E], 0
    je @F
    sub eax, [ebp+L_D]
@@:
    mov edx, [ebp+P_STACK]
    mov edx, [edx+eax*4]
    lea eax, [ebp+L_G]
    push eax
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz so_done
    mov eax, [ebp+L_B]
    mov eax, [eax+FIELD_SLOT]
    mov ecx, [ebp+L_G]
    lea eax, [ecx+eax*4+DATA0]
    mov [ebp+L_F], eax
so_field_access:
    cmp DWORD PTR [ebp+L_E], 0
    je so_field_load
    sub edi, [ebp+L_D]
    xor ecx, ecx
@@:
    cmp ecx, [ebp+L_D]
    jae so_field_stored
    push ecx
    mov eax, [ebp+P_STACK]
    lea eax, [eax+edi*4]
    mov eax, [eax+ecx*4]
    cmp BYTE PTR [esi+LK_KIND], K_INT
    jne so_field_put
    mov ecx, eax
    mov dl, [esi+LK_TYPE]
    call @jbv_narrow@8
so_field_put:
    pop ecx
    mov edx, [ebp+L_F]
    mov [edx+ecx*4], eax
    inc ecx
    jmp @B
so_field_stored:
    cmp DWORD PTR [ebp+L_C], 0
    jne so_ok
    cmp BYTE PTR [esi+LK_KIND], K_REF
    jne @F
    mov eax, [ebp+P_STACK]
    push DWORD PTR [eax+edi*4]
    mov edx, [ebp+L_G]
    mov ecx, ebx
    call @jbv_barrier_checked@12
@@:
    dec edi
    jmp so_ok
so_field_load:
    cmp DWORD PTR [ebp+L_C], 0
    jne @F
    dec edi
@@:
    mov eax, [ebp+L_F]
    mov cl, [esi+LK_KIND]
    call slot_bits
    mov cl, [esi+LK_KIND]
    jmp so_push

; ---- invokevirtual, invokespecial, invokestatic, invokeinterface
I_LINK   EQU L_A
I_CALLEE EQU L_B
I_OWNER  EQU L_C
I_ARGC   EQU L_D
I_RESULT EQU L_E
I_BASE   EQU L_F
I_RECV   EQU L_G
I_SEL    EQU L_H
so_invoke:
    lea eax, [ebp+I_LINK]
    call so_link
    test eax, eax
    jnz so_done
    mov esi, [ebp+I_LINK]
    IF JBV_PROFILE_FULL
    cmp DWORD PTR [esi+LK_MEMBER], 0
    jne so_invoke_member
    mov eax, [ebp+L_PC]                 ; MethodHandle.invokeExact/invoke: the index again
    sub eax, 2
    add eax, [ebp+L_CODE]
    movzx eax, WORD PTR [eax]
    xchg al, ah
    mov ecx, [ebp+L_CLASS]
    mov ecx, [ecx+C_POOL]
    imul eax, eax, CP_SIZEOF
    movzx eax, WORD PTR [ecx+eax+CP_B]
    imul eax, eax, CP_SIZEOF
    lea esi, [ecx+eax]                  ; the name and type
    movzx eax, WORD PTR [esi+CP_B]
    imul eax, eax, CP_SIZEOF
    lea edx, [ecx+eax+CP_TEXT]          ; the descriptor
    mov [ebp+I_SEL], edx
    movzx eax, WORD PTR [esi+CP_A]
    imul eax, eax, CP_SIZEOF
    lea eax, [ecx+eax+CP_TEXT]          ; the name
    mov [ebp+I_RECV], eax
    mov DWORD PTR [ebp+I_ARGC], 0
    push DWORD PTR [edx+4]
    push DWORD PTR [edx]
    lea ecx, [ebp+I_ARGC]
    lea edx, [ebp+I_RESULT]
    call @jbv_signature@16
    test eax, eax
    jnz so_done
    movzx eax, WORD PTR [ebp+I_ARGC]
    mov ecx, edi
    sub ecx, eax
    dec ecx
    mov [ebp+I_BASE], ecx
    mov eax, [ebp+I_RECV]
    push DWORD PTR [eax+4]
    push DWORD PTR [eax]
    mov ecx, OFFSET s_exact
    call @jbv_text_is@12
    lea ecx, [ebp+L_OUT]
    push ecx
    push eax
    mov ecx, [ebp+I_BASE]
    mov edx, [ebp+P_STACK]
    lea eax, [edx+ecx*4+4]
    push eax
    mov eax, [ebp+I_SEL]
    push DWORD PTR [eax+4]
    push DWORD PTR [eax]
    mov edx, [edx+ecx*4]
    mov ecx, ebx
    call @jbv_polymorphic@28
    test eax, eax
    jnz so_done
    jmp so_invoked
so_invoke_member:
    ENDIF
    mov eax, [esi+LK_MEMBER]
    mov [ebp+I_CALLEE], eax
    mov ecx, [esi+LK_OWNER]
    mov [ebp+I_OWNER], ecx
    test WORD PTR [eax+M_FLAGS], ACC_STATIC
    setnz cl
    cmp BYTE PTR [ebp+P_OP], 184
    sete ch
    cmp cl, ch
    mov edx, OFFSET n_icce
    jne so_throw_linkage
    movzx ecx, WORD PTR [eax+M_ARG_SLOTS]
    mov [ebp+I_ARGC], ecx
    movzx edx, BYTE PTR [eax+M_RESULT_KIND]
    mov [ebp+I_RESULT], edx
    cmp BYTE PTR [ebp+P_OP], 185
    jne @F
    add DWORD PTR [ebp+L_PC], 2
@@:
    mov edx, edi
    sub edx, ecx
    mov [ebp+I_BASE], edx
    cmp BYTE PTR [ebp+P_OP], 184
    je so_invoke_static
    mov eax, [ebp+P_STACK]
    mov edx, [eax+edx*4]
    lea eax, [ebp+I_RECV]
    push eax
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz so_done
    mov eax, [ebp+I_CALLEE]
    mov ecx, [ebp+I_OWNER]
    cmp BYTE PTR [ebp+P_OP], 183
    je so_special
    ; private or final: the core calls it directly
    cmp DWORD PTR [esi+LK_SPECIAL], 0
    jne so_virtual
    test WORD PTR [eax+M_FLAGS], ACC_STATIC or ACC_ABSTRACT
    jnz so_virtual
    test WORD PTR [eax+M_FLAGS], 12h
    jnz @F
    test WORD PTR [ecx+C_FLAGS], 10h
    jz so_virtual
@@:
    mov [esi+LK_SPECIAL], eax
    mov [esi+LK_SPECIAL_OWNER], ecx
so_virtual:
    test WORD PTR [eax+M_FLAGS], 12h
    jnz so_check_callee
    test WORD PTR [ecx+C_FLAGS], 10h
    jnz so_check_callee
    mov edx, [ebp+I_RECV]
    mov edx, [edx]                      ; the receiver's class
    cmp [esi+LK_SEEN], edx
    jne @F
    mov eax, [esi+LK_TARGET_OWNER]
    mov [ebp+I_OWNER], eax
    mov eax, [esi+LK_TARGET]
    mov [ebp+I_CALLEE], eax
    jmp so_call
@@:
    xor ecx, ecx                        ; the polymorphic entries
@@:
    cmp [esi+LK_PIC_SEEN+ecx*4], edx
    je so_pic_hit
    inc ecx
    cmp ecx, 3
    jb @B
    ; a miss: select and check once per class
    mov [ebp+I_SEL], edx
    cmp BYTE PTR [ebp+P_OP], 185
    jne @F
    push edx
    mov ecx, edx
    mov edx, [esi+LK_SYMBOLIC]
    call @jbv_assignable@8
    pop edx
    test eax, eax
    mov edx, OFFSET n_icce
    jz so_throw_linkage
@@:
    push DWORD PTR [ebp+I_CALLEE]
    mov edx, [esi+LK_OWNER]
    lea ecx, [ebp+I_SEL]
    call @jbv_virtual_method@12
    test eax, eax
    jnz @F
    mov edx, OFFSET n_icce
    cmp DWORD PTR [ebp+I_SEL], 0
    je so_throw_linkage
    mov edx, OFFSET n_ame
    jmp so_throw_linkage
@@:
    test WORD PTR [eax+M_FLAGS], ACC_STATIC
    mov edx, OFFSET n_icce
    jnz so_throw_linkage
    test WORD PTR [eax+M_FLAGS], ACC_ABSTRACT
    mov edx, OFFSET n_ame
    jnz so_throw_linkage
    mov [ebp+I_CALLEE], eax
    mov ecx, [ebp+I_SEL]
    mov [ebp+I_OWNER], ecx
    mov edx, [ebp+I_RECV]
    mov edx, [edx]
    cmp DWORD PTR [esi+LK_SEEN], 0
    jne @F
    mov [esi+LK_SEEN], edx
    mov [esi+LK_TARGET], eax
    mov [esi+LK_TARGET_OWNER], ecx
    jmp so_call
@@:
    push eax                            ; three more entries, replaced in turn
    push edx
    movzx eax, BYTE PTR [esi+LK_PIC_NEXT]
    inc BYTE PTR [esi+LK_PIC_NEXT]
    xor edx, edx
    push ecx
    mov ecx, 3
    div ecx
    pop ecx
    pop eax                             ; the receiver's class
    mov [esi+LK_PIC_SEEN+edx*4], eax
    mov [esi+LK_PIC_OWNER+edx*4], ecx
    pop eax
    mov [esi+LK_PIC_TARGET+edx*4], eax
    jmp so_call
so_pic_hit:
    mov eax, [esi+LK_PIC_OWNER+ecx*4]
    mov [ebp+I_OWNER], eax
    mov eax, [esi+LK_PIC_TARGET+ecx*4]
    mov [ebp+I_CALLEE], eax
    jmp so_call
so_special:                             ; invokespecial: an ACC_SUPER superclass method, resolved once
    cmp DWORD PTR [esi+LK_SPECIAL], 0
    jne so_special_ready
    mov [ebp+I_SEL], ecx                ; selected = owner, target = callee
    mov edx, [ebp+L_CLASS]
    push DWORD PTR [eax+M_NAME+TEXT_SIZE]
    push DWORD PTR [eax+M_NAME+TEXT_DATA]
    mov ecx, OFFSET s_init
    call @jbv_text_is@12
    test eax, eax
    jnz so_special_set
    mov edx, [ebp+L_CLASS]
    test WORD PTR [edx+C_FLAGS], ACC_SUPER
    jz so_special_set
    mov ecx, [esi+LK_SYMBOLIC]
    cmp edx, ecx
    je so_special_set
    test WORD PTR [ecx+C_FLAGS], ACC_INTERFACE
    jnz so_special_set
    cmp DWORD PTR [edx+C_SUPER], 0
    je so_special_set
    xchg ecx, edx
    call @jbv_assignable@8
    test eax, eax
    jz so_special_set
    mov eax, [ebp+L_CLASS]
    mov eax, [eax+C_SUPER]
    mov [ebp+I_SEL], eax
    mov eax, [ebp+I_CALLEE]
    push DWORD PTR [eax+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [eax+M_DESCRIPTOR+TEXT_DATA]
    push DWORD PTR [eax+M_NAME+TEXT_SIZE]
    push DWORD PTR [eax+M_NAME+TEXT_DATA]
    lea ecx, [ebp+I_SEL]
    call @jbv_lookup_method@20
    test eax, eax
    jnz @F
    mov edx, OFFSET n_icce
    cmp DWORD PTR [ebp+I_SEL], 0
    je so_throw_linkage
    mov edx, OFFSET n_ame
    jmp so_throw_linkage
@@:
    mov [ebp+I_CALLEE], eax
so_special_set:
    mov eax, [ebp+I_CALLEE]
    mov [esi+LK_SPECIAL], eax
    mov ecx, [ebp+I_SEL]
    mov [esi+LK_SPECIAL_OWNER], ecx
    cmp BYTE PTR [eax+M_INTRINSIC], 1
    sete BYTE PTR [esi+LK_TRIVIAL]
so_special_ready:
    mov eax, [esi+LK_SPECIAL_OWNER]
    mov [ebp+I_OWNER], eax
    mov eax, [esi+LK_SPECIAL]
    mov [ebp+I_CALLEE], eax
so_check_callee:
    mov eax, [ebp+I_CALLEE]
    test WORD PTR [eax+M_FLAGS], ACC_STATIC
    mov edx, OFFSET n_icce
    jnz so_throw_linkage
    test WORD PTR [eax+M_FLAGS], ACC_ABSTRACT
    mov edx, OFFSET n_ame
    jnz so_throw_linkage
    jmp so_call
so_invoke_static:
    mov edx, [ebp+I_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz so_done
    mov eax, [ebp+I_OWNER]
    cmp BYTE PTR [eax+C_INIT_STATE], 2
    jne so_call
    mov BYTE PTR [esi+LK_READY], 1
so_call:
    lea eax, [ebp+L_OUT]
    push eax
    push DWORD PTR [ebp+I_ARGC]
    mov ecx, [ebp+I_BASE]
    mov eax, [ebp+P_SREFS]
    add eax, ecx
    push eax
    mov eax, [ebp+P_STACK]
    lea eax, [eax+ecx*4]
    push eax
    push DWORD PTR [ebp+I_CALLEE]
    mov edx, [ebp+I_OWNER]
    mov ecx, ebx
    call @jbv_execute@28
    test eax, eax
    jnz so_done
so_invoked:
    mov edi, [ebp+I_BASE]
    mov ecx, [ebp+I_RESULT]
    test ecx, ecx
    jz so_ok
    dec ecx
    mov eax, [ebp+L_OUT]
    mov edx, [ebp+L_OUT+4]
    jmp so_push

so_indy:
    mov eax, S_INDY
    jmp so_done

so_new:                                 ; new, newarray, anewarray
    cmp BYTE PTR [ebp+P_OP], 188
    jne @F
    call fetch1
    movzx eax, BYTE PTR [array_codes+eax-4]
    lea ecx, [ebp+L_A]
    push ecx
    push eax
    xor edx, edx
    mov ecx, ebx
    call @jbv_array_class@16
    jmp so_new_type
@@:
    lea eax, [ebp+L_A]
    push eax
    call fetch2
    push eax
    mov edx, [ebp+L_CLASS]
    mov ecx, ebx
    call @jbv_class_constant@16
    test eax, eax
    jnz so_done
    cmp BYTE PTR [ebp+P_OP], 189
    jne so_new_type
    lea eax, [ebp+L_A]
    push eax
    push 'L'
    mov edx, [ebp+L_A]
    mov ecx, ebx
    call @jbv_array_class@16
so_new_type:
    test eax, eax
    jnz so_done
    mov edx, [ebp+L_A]
    cmp BYTE PTR [ebp+P_OP], 187
    jne so_new_array
    test WORD PTR [edx+C_FLAGS], ACC_INTERFACE or ACC_ABSTRACT
    mov edx, OFFSET n_ie
    jnz so_throw_linkage
    mov edx, [ebp+L_A]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz so_done
    lea eax, [ebp+L_B]
    push eax
    push 0
    mov edx, [ebp+L_A]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz so_done
    mov eax, [ebp+L_B]
    mov cl, K_REF
    jmp so_push
so_new_array:
    lea eax, [ebp+L_B]
    push eax
    mov eax, [ebp+P_STACK]
    push DWORD PTR [eax+edi*4-4]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz so_done
    dec edi
    mov eax, [ebp+L_B]
    mov cl, K_REF
    jmp so_push

so_multi:                               ; multianewarray
    lea eax, [ebp+L_A]
    push eax
    call fetch2
    push eax
    call fetch1
    mov esi, eax                        ; the dimensions
    mov edx, [ebp+L_CLASS]
    mov ecx, ebx
    call @jbv_class_constant@16
    test eax, eax
    jnz so_done
    mov edx, [ebp+P_STACK]
    lea edx, [edx+edi*4]
    mov ecx, esi
    neg ecx
    lea edx, [edx+ecx*4]                ; the sizes
    mov ecx, esi
    jecxz so_multi_make
    mov eax, S_NEGATIVE
@@:
    cmp DWORD PTR [edx+ecx*4-4], 0
    jl so_done
    loop @B
so_multi_make:
    lea eax, [ebp+L_B]
    push eax
    push esi
    push edx
    mov edx, [ebp+L_A]
    mov ecx, ebx
    call @jbv_multi_array@20
    test eax, eax
    jnz so_done
    sub edi, esi
    mov eax, [ebp+L_B]
    mov cl, K_REF
    jmp so_push

so_athrow:
    mov eax, [ebp+P_STACK]
    mov eax, [eax+edi*4-4]
    test eax, eax
    jnz @F
    mov eax, S_NULL
    jmp so_done
@@:
    mov [ebx+VM_EXCEPTION], eax
    mov eax, S_EXCEPTION
    mov [ebx+VM_EXCEPTION_STATUS], eax
    jmp so_done

so_cast:                                ; checkcast, instanceof
    lea eax, [ebp+L_A]
    push eax
    call fetch2
    push eax
    mov edx, [ebp+L_CLASS]
    mov ecx, ebx
    call @jbv_class_constant@16
    test eax, eax
    jnz so_done
    xor esi, esi                        ; matches
    mov eax, [ebp+P_STACK]
    mov edx, [eax+edi*4-4]
    test edx, edx
    jz so_cast_result
    lea eax, [ebp+L_B]
    push eax
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz so_done
    mov ecx, [ebp+L_B]
    mov ecx, [ecx]
    mov edx, [ebp+L_A]
    call @jbv_assignable@8
    mov esi, eax
so_cast_result:
    cmp BYTE PTR [ebp+P_OP], 192
    jne @F
    mov eax, [ebp+P_STACK]
    cmp DWORD PTR [eax+edi*4-4], 0
    je so_ok
    test esi, esi
    jnz so_ok
    mov eax, S_CAST
    jmp so_done
@@:
    mov eax, [ebp+P_STACK]
    mov [eax+edi*4-4], esi
    mov eax, [ebp+P_SREFS]
    mov BYTE PTR [eax+edi-1], 0
    jmp so_ok

so_monitor:                             ; monitorenter, monitorexit
    push 1
    cmp BYTE PTR [ebp+P_OP], 194
    je @F
    mov DWORD PTR [esp], -1
@@:
    mov eax, [ebp+P_STACK]
    push DWORD PTR [eax+edi*4-4]
    xor edx, edx
    mov ecx, ebx
    call @jbv_monitor@16
    test eax, eax
    jnz so_done
    dec edi
    jmp so_ok

so_unsupported:
    mov eax, S_UNSUPPORTED
    jmp so_done
so_push:
    call push_value
so_ok:
    xor eax, eax
so_done:                                ; state = pc, sp; a failure syncs the frame's sp
    mov ecx, [ebp+P_STATE]
    mov edx, [ebp+L_PC]
    mov [ecx], edx
    mov [ecx+4], edi
    test eax, eax
    jz @F
    mov ecx, [ebp+P_FRAME]
    mov [ecx+FR_SP], edi
@@:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 28
@jbv_slow_op@36 ENDP
.const
ALIGN 4
handlers DD so_unsupported, so_lconst, so_fconst, so_dconst, so_ldc, so_locals, so_dup, so_numeric
    DD so_switch, so_field, so_invoke, so_indy, so_new, so_multi, so_athrow, so_cast, so_monitor
END

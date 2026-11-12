; Method execution. The x86 core (interp.asm) runs the
; hot bytecodes; what it hands back is done here or in slow.asm, then exception
; handlers are searched.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_slow_op@36:PROC
EXTERN SYSCALL @jbv_raise@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_class_constant@16:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_narrow@8:PROC
EXTERN SYSCALL @jbv_kind@4:PROC
EXTERN SYSCALL @jbv_array_get@12:PROC
EXTERN SYSCALL @jbv_array_set@20:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_release_monitors@8:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_fp_enter@4:PROC
EXTERN SYSCALL @jbv_fp_restore@4:PROC
EXTERN SYSCALL @jbv_arguments@28:PROC
EXTERN SYSCALL @jbv_monitor@16:PROC
EXTERN SYSCALL @jbv_native_call@20:PROC
EXTERN SYSCALL @jbv_check_reference@16:PROC
EXTERN SYSCALL @jbv_return_type@8:PROC
EXTERN jbv_interpret_x86:PROC

S_UNSUPPORTED EQU 6
S_DIVIDE    EQU 9
S_LIMIT     EQU 10
S_NULL      EQU 12
S_BOUNDS    EQU 13
S_STORE     EQU 15
CORE_RETURN EQU 52455400h
K_REF       EQU 1
K_LONG      EQU 2
K_FLOAT     EQU 4
K_DOUBLE    EQU 5
ACC_STATIC  EQU 8
ACC_SYNCHRONIZED EQU 20h
ACC_NATIVE  EQU 100h
ACC_ABSTRACT EQU 400h
DATA0       EQU 4
HANDLE_MASK EQU 0FFFFFFh
F_LOCALS  EQU ACT_FRAME+FR_LOCALS

.const
n_soe DB 'java/lang/StackOverflowError', 0

.code
; ebx = vm, esi = act: the core's copies of the handle table and the young region
core_copies:
    mov eax, [ebx+VM_HANDLES]
    mov [esi+ACT_HANDLES], eax
    mov eax, [ebx+VM_NURSERY]
    mov [esi+ACT_NURSERY], eax
    mov eax, [ebx+VM_NURSERY_SIZE]
    mov [esi+ACT_NSIZE], eax
    ret

; ---- jbv_run: ebx = vm, esi = act, eax = a pending status (unwound first), edi = out
; -> eax status. The frame stays linked.
R_OUT   EQU -4
R_VALUE EQU -12       ; uint64_t
R_OP    EQU -16
R_STATE EQU -24       ; JbvOp {pc, sp}
R_EXC   EQU -28
R_TYPE  EQU -32
R_I     EQU -36
run:
    push ebp
    mov ebp, esp
    sub esp, 36
    push edi
    mov [ebp+R_OUT], edi
    xor ecx, ecx
    mov [ebp+R_VALUE], ecx
    mov [ebp+R_VALUE+4], ecx
    test eax, eax
    jnz rn_finish
rn_resume:
    call core_copies                    ; the hot bytecodes run in the core
    push esi
    call jbv_interpret_x86
    add esp, 4
    mov eax, [esi+ACT_STATUS]
    test eax, eax
    jz rn_op
    mov DWORD PTR [esi+ACT_STATUS], 0
    cmp eax, CORE_RETURN
    jne rn_finish
    mov eax, [esi+ACT_RESULT]
    mov [ebp+R_VALUE], eax
    mov eax, [esi+ACT_RESULT+4]
    mov [ebp+R_VALUE+4], eax
    xor eax, eax
    jmp rn_finish
rn_op:                                  ; the opcode it left: edx = pc past it, edi = sp, ecx = locals
    mov edx, [esi+ACT_PC]
    mov eax, [esi+ACT_CODE]
    movzx eax, BYTE PTR [eax+edx]
    inc edx
    mov [esi+ACT_PC], edx
    mov [ebp+R_OP], eax
    mov edi, [esi+ACT_SP]
    mov ecx, [esi+ACT_LOCALS]
    movzx eax, BYTE PTR [rn_kind+eax]
    jmp DWORD PTR [rn_ops+eax*4]
rn_store_sp:
    mov [esi+ACT_SP], edi
    jmp rn_resume
rn_nop:
    jmp rn_resume
rn_aload0:                              ; the superinstruction markers: their first opcode
    mov eax, [ecx]
    mov [ecx+edi*4], eax
    mov eax, [esi+ACT_REFS]
    mov BYTE PTR [eax+edi], 1
    inc edi
    jmp rn_store_sp
rn_iinc:
    mov eax, [esi+ACT_CODE]
    add eax, edx
    movzx edx, BYTE PTR [eax]
    movsx eax, BYTE PTR [eax+1]
    add [ecx+edx*4], eax
    add DWORD PTR [esi+ACT_PC], 2
    jmp rn_resume
rn_divide:                              ; idiv, irem
    mov eax, [ecx+edi*4-8]
    mov ebx, [ecx+edi*4-4]              ; (vm again below)
    test ebx, ebx
    jnz @F
    mov ebx, [esi+ACT_VM]
    mov eax, S_DIVIDE
    jmp rn_fail
@@:
    cmp ebx, -1                         ; MIN / -1: MIN, remainder 0
    jne @F
    cmp eax, 80000000h
    jne @F
    cmp BYTE PTR [ebp+R_OP], 108
    je rn_quotient
    xor eax, eax
    jmp rn_quotient
@@:
    cdq
    idiv ebx
    cmp BYTE PTR [ebp+R_OP], 108
    je rn_quotient
    mov eax, edx
rn_quotient:
    mov ebx, [esi+ACT_VM]
    mov ecx, [esi+ACT_LOCALS]
    dec edi
    mov [ecx+edi*4-4], eax
    jmp rn_store_sp
rn_if:                                  ; the conditional branches (handed back for the budget)
    mov eax, [ebp+R_OP]
    cmp eax, 159
    jae rn_if2
    dec edi                             ; ifeq..ifle, ifnull, ifnonnull: against 0
    mov edx, [ecx+edi*4]
    xor ecx, ecx
    cmp eax, 198
    jb @F
    sub eax, 198-153                    ; ifnull = ifeq, ifnonnull = ifne
@@:
    sub eax, 153
    jmp rn_compare
rn_if2:
    sub edi, 2
    mov edx, [ecx+edi*4]
    mov ecx, [ecx+edi*4+4]
    sub eax, 159
    cmp eax, 6                          ; if_acmpeq/ne = if_icmpeq/ne
    jb rn_compare
    sub eax, 6
rn_compare:                             ; edx ? ecx by eax: eq ne lt ge gt le
    mov [esi+ACT_SP], edi
    cmp edx, ecx
    jmp DWORD PTR [rn_conditions+eax*4]
rn_eq:
    je rn_branch
    jmp rn_skip
rn_ne:
    jne rn_branch
    jmp rn_skip
rn_lt:
    jl rn_branch
    jmp rn_skip
rn_ge:
    jge rn_branch
    jmp rn_skip
rn_gt:
    jg rn_branch
    jmp rn_skip
rn_le:
    jle rn_branch
rn_skip:
    add DWORD PTR [esi+ACT_PC], 2
    jmp rn_resume
rn_branch:
rn_goto:
    mov eax, [esi+ACT_PC]
    add eax, [esi+ACT_CODE]
    movzx eax, WORD PTR [eax]
    xchg al, ah
    movsx eax, ax
    jmp rn_jump
rn_goto_w:
    mov eax, [esi+ACT_PC]
    add eax, [esi+ACT_CODE]
    mov eax, [eax]
    bswap eax
rn_jump:                                ; eax = the offset; backward branches spend the budget
    test eax, eax
    jg @F
    mov ecx, [ebx+VM_REMAINING]
    or ecx, [ebx+VM_REMAINING+4]
    jnz rn_spend
    mov edi, [esi+ACT_SP]
    mov eax, S_LIMIT
    jmp rn_fail
rn_spend:
    sub DWORD PTR [ebx+VM_REMAINING], 1
    sbb DWORD PTR [ebx+VM_REMAINING+4], 0
@@:
    dec eax
    add [esi+ACT_PC], eax
    jmp rn_resume
rn_ireturn:                             ; narrowed to the declared type
    mov eax, [esi+ACT_FRAME+FR_METHOD]
    movzx edx, WORD PTR [eax+M_DESCRIPTOR+TEXT_SIZE]
    mov eax, [eax+M_DESCRIPTOR+TEXT_DATA]
    movzx edx, BYTE PTR [eax+edx-1]
    mov ecx, [ecx+edi*4-4]
    call @jbv_narrow@8
    xor edx, edx
    jmp rn_returned
rn_lreturn:                             ; lreturn, freturn, dreturn
    mov eax, [ecx+edi*4-8]
    mov edx, [ecx+edi*4-4]
    cmp BYTE PTR [ebp+R_OP], 174
    jne rn_returned
    mov eax, edx
    xor edx, edx
    jmp rn_returned
rn_areturn:
    mov eax, [ecx+edi*4-4]
    xor edx, edx
    jmp rn_returned
rn_return:
    xor eax, eax
    xor edx, edx
rn_returned:
    mov [ebp+R_VALUE], eax
    mov [ebp+R_VALUE+4], edx
    xor eax, eax
    jmp rn_finish
rn_arraylength:
    mov eax, [ecx+edi*4-4]
    test eax, eax
    jnz @F
    mov eax, S_NULL
    jmp rn_fail
@@:
    and eax, HANDLE_MASK
    mov edx, [ebx+VM_HANDLES]
    mov eax, [edx+eax*4]
    mov eax, [eax-4]
    mov [ecx+edi*4-4], eax
    mov eax, [esi+ACT_REFS]
    mov BYTE PTR [eax+edi-1], 0
    jmp rn_resume
rn_array:                               ; the generic array load/store (every element type)
    mov eax, [ebp+R_OP]
    xor edx, edx                        ; the store flag
    cmp eax, 79
    jb @F
    inc edx
    sub eax, 33
@@:
    mov [ebp+R_STATE], edx
    mov ecx, 1                          ; the width: laload, daload two
    cmp eax, 47
    je @F
    cmp eax, 49
    jne rn_array_width
@@:
    inc ecx
rn_array_width:
    mov [ebp+R_STATE+4], ecx
    lea eax, [ecx+2]                    ; the offset of the array ref from sp
    test edx, edx
    jnz @F
    mov eax, 2
@@:
    mov [ebp+R_I], eax
    neg eax
    add eax, edi
    mov ecx, [esi+ACT_LOCALS]
    mov edx, [ecx+eax*4]
    push DWORD PTR [ecx+eax*4+4]        ; the index
    lea eax, [ebp+R_EXC]
    push eax
    mov ecx, ebx
    call @jbv_object@12
    pop edx                             ; the index
    test eax, eax
    jnz rn_fail
    mov eax, [ebp+R_EXC]                ; the array: the index in bounds
    cmp edx, [eax-4]
    mov eax, S_BOUNDS
    jae rn_fail
    mov [ebp+R_TYPE], edx
    mov eax, [ebp+R_EXC]
    mov eax, [eax]
    movzx ecx, BYTE PTR [eax+C_ARRAY_KIND]
    mov [ebp+R_OP], ecx                 ; the element kind from here on
    call @jbv_kind@4
    movzx eax, al
    mov [ebp+R_I+0], eax                ; (the offset is not needed again: recomputed below)
    cmp DWORD PTR [ebp+R_STATE], 0
    je rn_array_load
    cmp BYTE PTR [ebp+R_OP], 'L'
    jne rn_array_put
    mov ecx, [esi+ACT_LOCALS]
    mov edx, [ecx+edi*4-4]
    test edx, edx
    jz rn_array_put
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz rn_fail
    mov ecx, [ecx]
    mov edx, [ebp+R_EXC]
    mov edx, [edx]
    mov edx, [edx+C_COMPONENT]
    call @jbv_assignable@8
    test eax, eax
    mov eax, S_STORE
    jz rn_fail
rn_array_put:
    mov ecx, [esi+ACT_LOCALS]
    mov eax, edi
    sub eax, [ebp+R_STATE+4]
    lea eax, [ecx+eax*4]
    xor edx, edx
    cmp DWORD PTR [ebp+R_STATE+4], 2
    jne @F
    mov edx, [eax+4]
@@:
    push edx
    push DWORD PTR [eax]
    push DWORD PTR [ebp+R_OP]
    mov edx, [ebp+R_TYPE]
    mov ecx, [ebp+R_EXC]
    call @jbv_array_set@20
    cmp BYTE PTR [ebp+R_OP], 'L'
    jne @F
    mov ecx, [esi+ACT_LOCALS]
    push DWORD PTR [ecx+edi*4-4]
    mov edx, [ebp+R_EXC]
    mov ecx, ebx
    call @jbv_barrier_checked@12
@@:
    sub edi, [ebp+R_STATE+4]
    sub edi, 2
    jmp rn_store_sp
rn_array_load:
    push DWORD PTR [ebp+R_OP]
    mov edx, [ebp+R_TYPE]
    mov ecx, [ebp+R_EXC]
    call @jbv_array_get@12
    sub edi, 2
    mov ecx, [esi+ACT_LOCALS]
    mov [ecx+edi*4], eax
    mov ecx, [esi+ACT_REFS]
    mov BYTE PTR [ecx+edi], 0
    inc edi
    mov eax, [ebp+R_I]                  ; the slot kind
    cmp al, K_LONG
    je @F
    cmp al, K_DOUBLE
    je @F
    cmp al, K_REF
    sete BYTE PTR [ecx+edi-1]
    jmp rn_store_sp
@@:
    mov eax, [esi+ACT_LOCALS]
    mov [eax+edi*4], edx
    mov BYTE PTR [ecx+edi], 0
    inc edi
    jmp rn_store_sp
rn_slow:                                ; slow_op, the frame synced
    call sync
    mov eax, [esi+ACT_PC]
    mov [ebp+R_STATE], eax
    mov eax, edi
    sub eax, [esi+F_LOCALS]
    mov [ebp+R_STATE+4], eax
    mov eax, [esi+ACT_REFS]
    mov ecx, [esi+F_LOCALS]
    push eax                            ; local_refs
    push DWORD PTR [esi+ACT_LOCALS]       ; locals
    add eax, ecx
    push eax                            ; stack_refs
    mov eax, [esi+ACT_LOCALS]
    lea eax, [eax+ecx*4]
    push eax                            ; stack
    lea eax, [ebp+R_STATE]
    push eax
    push DWORD PTR [ebp+R_OP]
    lea eax, [esi+ACT_FRAME]
    push eax
    mov edx, [esi+ACT_FRAME+FR_OWNER]
    mov ecx, ebx
    call @jbv_slow_op@36
    mov ecx, [ebp+R_STATE]
    mov [esi+ACT_PC], ecx
    mov ecx, [ebp+R_STATE+4]
    add ecx, [esi+F_LOCALS]
    mov [esi+ACT_SP], ecx
    test eax, eax
    jnz rn_finish
    jmp rn_resume
; the frame's copy of pc (at the opcode) and sp; edi = sp
sync:
    mov eax, [esi+ACT_PC]
    dec eax
    mov [esi+ACT_FRAME+FR_PC], eax
    mov eax, edi
    sub eax, [esi+F_LOCALS]
    mov [esi+ACT_FRAME+FR_SP], eax
    ret
rn_fail:                                ; eax = the status, edi = sp
    push eax
    call sync
    pop eax
rn_finish:                              ; a failure: a handler of this method, if one catches it
    test eax, eax
    jz rn_done
    mov [ebp+R_I], eax
    mov edx, eax
    mov ecx, ebx
    call @jbv_raise@8
    mov eax, [ebp+R_I]
    cmp DWORD PTR [ebx+VM_EXCEPTION], 0
    je rn_done
    lea eax, [ebp+R_EXC]
    push eax
    mov edx, [ebx+VM_EXCEPTION]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    mov eax, [ebp+R_I]
    jnz rn_done
    mov eax, [ebp+R_EXC]
    mov eax, [eax]
    mov [ebp+R_EXC], eax                ; its class (resolving a catch type may move it)
    xor edi, edi                        ; the handler
rn_handler:
    mov eax, [esi+ACT_FRAME+FR_METHOD]
    cmp di, [eax+M_HANDLERS]
    jae rn_unhandled
    mov eax, [eax+M_EXCEPTIONS]
    lea eax, [eax+edi*8]
    movzx ecx, WORD PTR [eax]           ; [start, end)
    xchg cl, ch
    cmp [esi+ACT_FRAME+FR_PC], ecx
    jb rn_next_handler
    movzx ecx, WORD PTR [eax+2]
    xchg cl, ch
    cmp [esi+ACT_FRAME+FR_PC], ecx
    jae rn_next_handler
    movzx ecx, WORD PTR [eax+6]         ; the catch type (0: any)
    xchg cl, ch
    test ecx, ecx
    jz rn_catch
    lea eax, [ebp+R_TYPE]
    push eax
    push ecx
    mov edx, [esi+ACT_FRAME+FR_OWNER]
    mov ecx, ebx
    call @jbv_class_constant@16
    test eax, eax
    jnz rn_done
    mov ecx, [ebp+R_EXC]
    mov edx, [ebp+R_TYPE]
    call @jbv_assignable@8
    test eax, eax
    jz rn_next_handler
rn_catch:                               ; the exception alone on the stack, at the handler
    mov eax, [esi+ACT_FRAME+FR_METHOD]
    mov eax, [eax+M_EXCEPTIONS]
    movzx eax, WORD PTR [eax+edi*8+4]
    xchg al, ah
    mov [esi+ACT_PC], eax
    mov ecx, [esi+F_LOCALS]
    mov eax, [esi+ACT_LOCALS]
    mov edx, [ebx+VM_EXCEPTION]
    mov [eax+ecx*4], edx
    mov eax, [esi+ACT_REFS]
    mov BYTE PTR [eax+ecx], 1
    inc ecx
    mov [esi+ACT_SP], ecx
    xor eax, eax
    mov [ebx+VM_EXCEPTION], eax
    mov [ebx+VM_EXCEPTION_STATUS], eax
    jmp rn_resume
rn_next_handler:
    inc edi
    jmp rn_handler
rn_unhandled:
    mov eax, [ebp+R_I]
rn_done:
    test eax, eax
    jnz rn_ret
    mov [ebx+VM_EXCEPTION], eax
    mov [ebx+VM_EXCEPTION_STATUS], eax
    mov ecx, [ebp+R_OUT]
    mov edx, [ebp+R_VALUE]
    mov [ecx], edx
    mov edx, [ebp+R_VALUE+4]
    mov [ecx+4], edx
rn_ret:
    pop edi
    mov esp, ebp
    pop ebp
    ret

; ---- activations the core made
@jbv_core_leave@4 PROC SYSCALL      ; ecx act: unlinked
    push ebx
    push esi
    mov esi, ecx
    mov ebx, [esi+ACT_VM]
    cmp BYTE PTR [esi+ACT_FRAME+FR_HAS_MONITORS], 0
    je @F
    lea edx, [esi+ACT_FRAME]
    mov ecx, ebx
    call @jbv_release_monitors@8
@@:
    mov eax, [esi+ACT_FRAME+FR_PREVIOUS]
    mov [ebx+VM_FRAMES], eax
    mov eax, [esi+ACT_SAVED]
    mov [ebx+VM_USED_SLOTS], eax
    dec DWORD PTR [ebx+VM_DEPTH]
    pop esi
    pop ebx
    ret
@jbv_core_leave@4 ENDP
; an activation the core made needs jbv_run (an opcode it leaves, or a failure in core.status): run
; to its end here and unlinked; the result in core.result
@jbv_core_finish@4 PROC SYSCALL     ; ecx act
    push ebx
    push esi
    push edi
    mov esi, ecx
    mov ebx, [esi+ACT_VM]
    xor eax, eax
    xchg eax, [esi+ACT_STATUS]
    mov BYTE PTR [esi+ACT_ASM], 0
    lea edi, [esi+ACT_RESULT]
    call run
    push eax
    mov ecx, esi
    call @jbv_core_leave@4
    call core_copies                    ; for the caller in the core
    pop eax
    pop edi
    pop esi
    pop ebx
    ret
@jbv_core_finish@4 ENDP

; ---- JbvStatus jbv_execute(vm, c, m, args, refs, count, result)
X_ACT    EQU -112
X_FP     EQU -144     ; JbvFPEnv
X_SAVED  EQU -148
X_BASE   EQU -152
X_OWNFP  EQU -156
X_ACTIVE EQU -160
X_VALUE  EQU -168     ; uint64_t
X_STATUS EQU -172
X_M      EQU 8
X_ARGS   EQU 12
X_REFS   EQU 16
X_COUNT  EQU 20
X_RESULT EQU 24
@jbv_execute@28 PROC SYSCALL        ; ecx vm, edx class, [ebp+8] m, args, refs, count, result
    push ebp
    mov ebp, esp
    sub esp, 172
    push ebx
    push esi
    push edi
    mov ebx, ecx
    lea esi, [ebp+X_ACT]
    mov edi, [ebp+X_M]
    mov [esi+ACT_FRAME+FR_OWNER], edx
    mov [esi+ACT_FRAME+FR_METHOD], edi
    xor eax, eax
    mov [esi+ACT_FRAME+FR_PC], eax
    mov [esi+ACT_FRAME+FR_SP], eax
    mov BYTE PTR [esi+ACT_FRAME+FR_HAS_MONITORS], al
    mov [ebp+X_VALUE], eax
    mov [ebp+X_VALUE+4], eax
    mov [ebp+X_ACTIVE], eax
    mov [ebp+X_STATUS], eax
    movzx ecx, BYTE PTR [ebx+VM_FP_READY]
    xor cl, 1
    mov [ebp+X_OWNFP], ecx
    mov eax, [ebx+VM_FRAMES]
    mov [esi+ACT_FRAME+FR_PREVIOUS], eax
    mov eax, [ebx+VM_USED_SLOTS]
    mov [ebp+X_SAVED], eax
    mov [ebp+X_BASE], eax
    ; bytecode calling bytecode: arguments in place on the caller's stack, the VM's FP
    ; state, no monitor, native or intrinsic
    test ecx, ecx
    jnz ex_general
    call ex_in_place
    jne ex_general
    test WORD PTR [edi+M_FLAGS], ACC_NATIVE or ACC_SYNCHRONIZED or ACC_ABSTRACT
    jnz ex_general
    cmp BYTE PTR [edi+M_INTRINSIC], 0
    jne ex_general
    movzx edx, WORD PTR [edi+M_MAX_LOCALS]
    movzx ecx, WORD PTR [edi+M_MAX_STACK]
    add edx, ecx                        ; needed
    mov ecx, [ebx+VM_DEPTH]
    cmp ecx, [ebx+VM_MAX_DEPTH]
    jae ex_general
    mov ecx, [ebx+VM_MAX_SLOTS]
    sub ecx, eax
    cmp edx, ecx
    ja ex_general
    mov ecx, [ebx+VM_REMAINING]
    or ecx, [ebx+VM_REMAINING+4]
    jz ex_general
    inc DWORD PTR [ebx+VM_DEPTH]
    sub DWORD PTR [ebx+VM_REMAINING], 1
    sbb DWORD PTR [ebx+VM_REMAINING+4], 0
    movzx ecx, WORD PTR [edi+M_MAX_LOCALS]
    mov [esi+F_LOCALS], ecx
    mov [ebp+X_BASE], eax
    call ex_place
    jmp ex_run
ex_general:
    mov eax, S_UNSUPPORTED
    test WORD PTR [edi+M_FLAGS], ACC_ABSTRACT
    jnz ex_return
    mov eax, [ebx+VM_DEPTH]
    cmp eax, [ebx+VM_MAX_DEPTH]
    jb @F
    push S_LIMIT
    push 0
    mov edx, OFFSET n_soe
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp ex_return
@@:
    cmp DWORD PTR [ebp+X_OWNFP], 0
    je @F
    lea ecx, [ebp+X_FP]
    call @jbv_fp_enter@4
    mov BYTE PTR [ebx+VM_FP_READY], 1
@@:
    inc DWORD PTR [ebx+VM_DEPTH]
    movzx ecx, WORD PTR [ebp+X_COUNT]   ; natives: the arguments only
    xor edx, edx
    test WORD PTR [edi+M_FLAGS], ACC_NATIVE
    jnz @F
    movzx ecx, WORD PTR [edi+M_MAX_LOCALS]
    movzx edx, WORD PTR [edi+M_MAX_STACK]
@@:
    mov [esi+F_LOCALS], ecx
    add edx, ecx                        ; needed
    mov eax, [ebp+X_SAVED]
    cmp DWORD PTR [ebp+X_REFS], 0       ; called from bytecode: the arguments stay where they are
    je @F
    push edx
    call ex_in_place
    pop edx
    je @F
    mov eax, [ebp+X_SAVED]
@@:
    mov [ebp+X_BASE], eax
    mov ecx, [ebx+VM_MAX_SLOTS]
    sub ecx, eax
    cmp edx, ecx
    jbe @F
    push S_LIMIT
    push 0
    mov edx, OFFSET n_soe
    mov ecx, ebx
    call @jbv_throw_named@16
    mov [ebp+X_STATUS], eax
    jmp ex_done
@@:
    call ex_place
    mov eax, [ebp+X_BASE]
    cmp eax, [ebp+X_SAVED]
    jne ex_linked
    push esi                            ; a fresh frame: the arguments copied in
    push edi
    mov esi, [ebp+X_ARGS]
    mov edi, [ebp+X_ACT+ACT_LOCALS]
    movzx ecx, WORD PTR [ebp+X_COUNT]
    rep movsd
    pop edi
    pop esi
    mov ecx, [ebp+X_REFS]
    test ecx, ecx
    jz ex_check_arguments
    push esi
    push edi
    mov esi, ecx
    mov edi, [ebp+X_ACT+ACT_REFS]
    movzx ecx, WORD PTR [ebp+X_COUNT]
    rep movsb
    pop edi
    pop esi
    jmp ex_linked
ex_check_arguments:
    push 0
    push DWORD PTR [esi+ACT_REFS]
    movzx eax, WORD PTR [ebp+X_COUNT]
    push eax
    push DWORD PTR [esi+ACT_LOCALS]
    push edi
    mov edx, [esi+ACT_FRAME+FR_OWNER]
    mov ecx, ebx
    call @jbv_arguments@28
    mov [ebp+X_STATUS], eax
    test eax, eax
    jnz ex_done
ex_linked:
    mov eax, S_LIMIT
    mov ecx, [ebx+VM_REMAINING]
    or ecx, [ebx+VM_REMAINING+4]
    jz ex_fail
    sub DWORD PTR [ebx+VM_REMAINING], 1
    sbb DWORD PTR [ebx+VM_REMAINING+4], 0
    test WORD PTR [edi+M_FLAGS], ACC_SYNCHRONIZED
    jz ex_entered
    push 1                              ; the receiver's monitor, or the class's
    xor edx, edx
    mov eax, [esi+ACT_LOCALS]
    push DWORD PTR [eax]
    test WORD PTR [edi+M_FLAGS], ACC_STATIC
    jz @F
    mov DWORD PTR [esp], 0
    mov edx, [esi+ACT_FRAME+FR_OWNER]
@@:
    mov ecx, ebx
    call @jbv_monitor@16
    test eax, eax
    jnz ex_fail
ex_entered:
    cmp BYTE PTR [edi+M_INTRINSIC], 1   ; Object.<init>: the caller checked null
    je ex_done
    test WORD PTR [edi+M_FLAGS], ACC_NATIVE
    jz ex_run
    lea eax, [ebp+X_VALUE]
    push eax
    movzx eax, WORD PTR [ebp+X_COUNT]
    push eax
    push DWORD PTR [esi+ACT_LOCALS]
    mov edx, edi
    mov ecx, ebx
    call @jbv_native_call@20
    mov [ebp+X_STATUS], eax
    test eax, eax
    jnz ex_done
    movzx eax, BYTE PTR [edi+M_RESULT_KIND]
    cmp eax, 1                          ; void: 0; int: narrowed to the declared type
    ja ex_done
    mov DWORD PTR [ebp+X_VALUE+4], 0
    test eax, eax
    jz @F
    movzx edx, WORD PTR [edi+M_DESCRIPTOR+TEXT_SIZE]
    mov eax, [edi+M_DESCRIPTOR+TEXT_DATA]
    movzx edx, BYTE PTR [eax+edx-1]
    mov ecx, [ebp+X_VALUE]
    call @jbv_narrow@8
@@:
    mov [ebp+X_VALUE], eax
    jmp ex_done
ex_run:
    mov BYTE PTR [esi+ACT_ASM], 0
    mov eax, [edi+M_CODE]
    mov [esi+ACT_CODE], eax
    mov DWORD PTR [esi+ACT_PC], 0
    mov eax, [esi+F_LOCALS]
    mov [esi+ACT_SP], eax
    mov eax, [esi+ACT_FRAME+FR_OWNER]
    mov eax, [eax+C_POOL]
    mov [esi+ACT_POOL], eax
    mov [esi+ACT_VM], ebx
    mov DWORD PTR [esi+ACT_STATUS], 0
    push edi
    xor eax, eax
    lea edi, [ebp+X_VALUE]
    call run
    pop edi
    mov [ebp+X_STATUS], eax
    jmp ex_leave
ex_fail:
    mov [ebp+X_STATUS], eax
ex_done:
    mov eax, [ebp+X_STATUS]
    test eax, eax
    jz ex_leave
    mov edx, eax
    mov ecx, ebx
    call @jbv_raise@8
ex_leave:
    mov eax, [ebp+X_STATUS]
    test eax, eax
    jnz ex_unlink
    mov [ebx+VM_EXCEPTION], eax
    mov [ebx+VM_EXCEPTION_STATUS], eax
    test WORD PTR [edi+M_FLAGS], ACC_NATIVE  ; host natives' references are checked
    jz ex_unlink
    cmp BYTE PTR [edi+M_INTRINSIC], 0
    jne ex_unlink
    cmp BYTE PTR [edi+M_RESULT_KIND], K_REF+1
    jne ex_unlink
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_DATA]
    call @jbv_return_type@8
    push edx
    push eax
    mov edx, [ebp+X_VALUE]
    mov ecx, ebx
    call @jbv_check_reference@16
    mov [ebp+X_STATUS], eax
ex_unlink:
    cmp DWORD PTR [ebp+X_ACTIVE], 0
    je @F
    cmp BYTE PTR [esi+ACT_FRAME+FR_HAS_MONITORS], 0
    je ex_unlinked
    lea edx, [esi+ACT_FRAME]
    mov ecx, ebx
    call @jbv_release_monitors@8
ex_unlinked:
    mov eax, [esi+ACT_FRAME+FR_PREVIOUS]
    mov [ebx+VM_FRAMES], eax
@@:
    mov eax, [ebp+X_SAVED]
    mov [ebx+VM_USED_SLOTS], eax
    dec DWORD PTR [ebx+VM_DEPTH]
    cmp DWORD PTR [ebp+X_OWNFP], 0
    je @F
    lea ecx, [ebp+X_FP]
    call @jbv_fp_restore@4
    mov BYTE PTR [ebx+VM_FP_READY], 0
@@:
    mov eax, [ebp+X_STATUS]
    test eax, eax
    jnz ex_return
    mov ecx, [ebp+X_RESULT]
    mov edx, [ebp+X_VALUE]
    mov [ecx], edx
    xor edx, edx
    movzx eax, BYTE PTR [edi+M_RESULT_KIND]
    cmp eax, K_LONG+1
    je @F
    cmp eax, K_DOUBLE+1
    jne ex_high
@@:
    mov edx, [ebp+X_VALUE+4]
ex_high:
    mov [ecx+4], edx
    xor eax, eax
ex_return:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 20
@jbv_execute@28 ENDP
; ZF = args and refs lie in the VM's slots below the caller's top; eax = their slot index
ex_in_place:
    mov eax, [ebp+X_ARGS]
    sub eax, [ebx+VM_SLOTS]
    jb ex_not_in_place
    shr eax, 2
    cmp eax, [ebp+X_SAVED]
    jae ex_not_in_place
    mov ecx, [ebx+VM_SLOT_REFS]
    add ecx, eax
    cmp ecx, [ebp+X_REFS]
    ret
ex_not_in_place:
    or esp, esp
    ret
; the frame at [X_BASE]: locals/refs, used_slots = base + edx, refs past count cleared, linked
ex_place:
    mov eax, [ebp+X_BASE]
    mov ecx, [ebx+VM_SLOTS]
    lea ecx, [ecx+eax*4]
    mov [esi+ACT_LOCALS], ecx
    mov ecx, [ebx+VM_SLOT_REFS]
    add ecx, eax
    mov [esi+ACT_REFS], ecx
    add edx, eax
    mov [ebx+VM_USED_SLOTS], edx
    mov [esi+ACT_FRAME+FR_BASE], eax
    push edi
    movzx edx, WORD PTR [ebp+X_COUNT]   ; uninitialized locals: no reference bits
    mov ecx, [esi+F_LOCALS]
    sub ecx, edx
    jbe @F
    lea edi, [eax+edx]
    add edi, [ebx+VM_SLOT_REFS]
    xor eax, eax
    rep stosb
@@:
    pop edi
    mov eax, [ebx+VM_FRAMES]
    mov [esi+ACT_FRAME+FR_PREVIOUS], eax
    lea eax, [esi+ACT_FRAME]
    mov [ebx+VM_FRAMES], eax
    mov DWORD PTR [ebp+X_ACTIVE], 1
    ret
.const
ALIGN 4
rn_ops DD rn_slow, rn_nop, rn_aload0, rn_iinc, rn_divide, rn_if, rn_goto, rn_goto_w
    DD rn_ireturn, rn_lreturn, rn_areturn, rn_return, rn_array, rn_arraylength
rn_conditions DD rn_eq, rn_ne, rn_lt, rn_ge, rn_gt, rn_le
rn_kind LABEL BYTE
    DB 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 12, 12, 12, 12, 12, 12, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 12, 12, 12, 12, 12, 12, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5
    DB 5, 5, 5, 5, 5, 5, 5, 6, 0, 0, 0, 0, 8, 9, 9, 9, 10, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13, 0
    DB 0, 0, 0, 0, 0, 0, 5, 5, 7, 0, 0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
END

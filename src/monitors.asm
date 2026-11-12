; Java monitors and virtual method selection. Monitors are reentrant, one table entry per acquisition
; {ref, class, frame}: by object, or by class for static synchronized and Class objects.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC

S_OOM       EQU 2
S_LIMIT     EQU 10
S_BAD_REF   EQU 17
S_MONITOR   EQU 18
B_CLASS     EQU 2
DATA0       EQU 4
MON_REF     EQU 0
MON_TYPE    EQU 4
MON_FRAME   EQU 8

.code
; esi = an entry, ebp = ref, edi = class -> ZF = it is that monitor (and in use)
same:
    mov eax, [esi+MON_REF]
    or eax, [esi+MON_TYPE]
    jz sm_no
    test edi, edi
    jz @F
    cmp [esi+MON_TYPE], edi
    ret
@@:
    cmp DWORD PTR [esi+MON_TYPE], 0
    jne sm_no
    cmp [esi+MON_REF], ebp
    ret
sm_no:
    or esp, esp
    ret
; action > 0 enter, 0 check held, < 0 exit (structured: this frame's acquisition first)
@jbv_monitor@16 PROC SYSCALL        ; ecx vm, edx class, [esp+4] ref, [esp+8] action
    push ebx
    push esi
    push edi
    push ebp
    mov ebx, ecx
    mov edi, edx
    mov ebp, [esp+20]
    test edi, edi
    jnz mo_class
    push 0
    push esp
    mov edx, ebp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz mo_ret
    mov eax, [ecx]
    cmp BYTE PTR [eax+C_BUILTIN], B_CLASS   ; a Class object locks its class
    jne mo_find
    mov edi, [ecx+DATA0]
    mov eax, S_BAD_REF
    test edi, edi
    jz mo_ret
mo_class:
    xor ebp, ebp
mo_find:
    cmp DWORD PTR [esp+24], 0
    jg mo_enter
    mov ecx, [ebx+VM_MONITOR_CAP]       ; the last acquisition of it
@@:
    dec ecx
    js mo_not_held
    imul esi, ecx, MON_SIZEOF
    add esi, [ebx+VM_MONITORS]
    call same
    jne @B
    xor eax, eax
    cmp DWORD PTR [esp+24], 0
    je mo_ret
    push esi                            ; prefer one taken in the current frame
    inc ecx
@@:
    dec ecx
    js @F
    imul esi, ecx, MON_SIZEOF
    add esi, [ebx+VM_MONITORS]
    call same
    jne @B
    mov eax, [ebx+VM_FRAMES]
    cmp [esi+MON_FRAME], eax
    jne @B
    mov [esp], esi
@@:
    pop esi
    xor eax, eax
    mov [esi+MON_REF], eax
    mov [esi+MON_TYPE], eax
    mov [esi+MON_FRAME], eax
    jmp mo_ret
mo_not_held:
    mov eax, S_MONITOR
    jmp mo_ret
mo_enter:                               ; a free entry, else a larger table
    xor ecx, ecx
@@:
    cmp ecx, [ebx+VM_MONITOR_CAP]
    jae mo_grow
    imul esi, ecx, MON_SIZEOF
    add esi, [ebx+VM_MONITORS]
    mov eax, [esi+MON_REF]
    or eax, [esi+MON_TYPE]
    jz mo_take
    inc ecx
    jmp @B
mo_grow:
    lea edx, [ecx*2]
    test ecx, ecx
    jnz @F
    mov edx, 8
@@:
    cmp edx, [ebx+CFG_MAX_SLOTS]
    jbe @F
    mov edx, [ebx+CFG_MAX_SLOTS]
@@:
    mov eax, S_LIMIT
    cmp edx, ecx
    jbe mo_ret
    push ecx
    push edx
    imul edx, edx, MON_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    pop edx
    pop ecx
    test eax, eax
    jz mo_oom
    push edx
    push ecx
    push edi
    mov esi, [ebx+VM_MONITORS]
    mov edi, eax
    imul ecx, ecx, 3
    rep movsd
    pop edi
    push eax
    mov edx, [ebx+VM_MONITORS]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
    mov [ebx+VM_MONITORS], eax
    pop ecx
    pop edx
    mov [ebx+VM_MONITOR_CAP], edx
    imul esi, ecx, MON_SIZEOF
    add esi, eax
mo_take:
    mov [esi+MON_REF], ebp
    mov [esi+MON_TYPE], edi
    mov eax, [ebx+VM_FRAMES]
    mov [esi+MON_FRAME], eax
    test eax, eax
    jz @F
    mov BYTE PTR [eax+FR_HAS_MONITORS], 1
@@:
    xor eax, eax
    jmp mo_ret
mo_oom:
    mov eax, S_OOM
mo_ret:
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_monitor@16 ENDP
@jbv_release_monitors@8 PROC SYSCALL ; ecx vm, edx frame: its acquisitions
    mov eax, [ecx+VM_MONITORS]
    mov ecx, [ecx+VM_MONITOR_CAP]
    jecxz rm_ret
@@:
    cmp [eax+MON_FRAME], edx
    jne rm_next
    push edx
    mov edx, [eax+MON_REF]
    or edx, [eax+MON_TYPE]
    pop edx
    jz rm_next
    mov DWORD PTR [eax+MON_REF], 0
    mov DWORD PTR [eax+MON_TYPE], 0
    mov DWORD PTR [eax+MON_FRAME], 0
rm_next:
    add eax, MON_SIZEOF
    loop @B
rm_ret:
    ret
@jbv_release_monitors@8 ENDP

; ---- access: the same runtime package (the same name up to the last '/')
; eax = class -> eax = its package prefix length (ecx used)
package_length:
    push esi
    movzx ecx, WORD PTR [eax+C_NAME+TEXT_SIZE]
    mov esi, [eax+C_NAME+TEXT_DATA]
pk_loop:
    test ecx, ecx
    jz pk_none
    dec ecx
    cmp BYTE PTR [esi+ecx], '/'
    jne pk_loop
    lea eax, [ecx+1]
    pop esi
    ret
pk_none:
    xor eax, eax
    pop esi
    ret
@jbv_same_package@8 PROC SYSCALL    ; ecx a, edx b
    push esi
    push edi
    mov esi, ecx
    mov edi, edx
    mov eax, esi
    call package_length
    push eax
    mov eax, edi
    call package_length
    pop ecx
    cmp eax, ecx
    jne sp_no
    mov esi, [esi+C_NAME+TEXT_DATA]
    mov edi, [edi+C_NAME+TEXT_DATA]
    cmp eax, eax
    repe cmpsb
    jne sp_no
    mov eax, 1
    jmp sp_ret
sp_no:
    xor eax, eax
sp_ret:
    pop edi
    pop esi
    ret
@jbv_same_package@8 ENDP
; child.method overrides base.original (JVMS 5.4.5, with package-private transitivity)
; [esp+4] child, method, base, original -> eax
overrides:
    push esi
    push edi
    push ebp
    mov eax, [esp+20]                   ; method
    test WORD PTR [eax+M_FLAGS], 2 or 8
    jnz ov_no
    mov eax, [esp+28]                   ; original
    test WORD PTR [eax+M_FLAGS], 2
    jnz ov_no
    test WORD PTR [eax+M_FLAGS], 1 or 4
    jnz ov_yes
    mov ecx, [esp+16]
    mov edx, [esp+24]
    call @jbv_same_package@8
    test eax, eax
    jnz ov_yes
    mov esi, [esp+16]                   ; through a package-private chain in between
    mov esi, [esi+C_SUPER]
ov_middle:
    test esi, esi
    jz ov_no
    cmp esi, [esp+24]
    je ov_no
    mov eax, [esp+28]
    push DWORD PTR [eax+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [eax+M_DESCRIPTOR+TEXT_DATA]
    push DWORD PTR [eax+M_NAME+TEXT_SIZE]
    push DWORD PTR [eax+M_NAME+TEXT_DATA]
    mov ecx, esi
    call @jbv_find_method@20
    test eax, eax
    jz ov_up
    mov edi, eax                        ; middle
    push edi
    push esi
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    call overrides
    add esp, 16
    test eax, eax
    jz ov_up
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    push edi
    push esi
    call overrides
    add esp, 16
    test eax, eax
    jnz ov_yes
ov_up:
    mov esi, [esi+C_SUPER]
    jmp ov_middle
ov_yes:
    mov eax, 1
    jmp @F
ov_no:
    xor eax, eax
@@:
    pop ebp
    pop edi
    pop esi
    ret
; the method selected for a receiver class: up from *owner, an override of the resolved one
@jbv_virtual_method@12 PROC SYSCALL ; ecx = &owner, edx resolved, [esp+4] method
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, [esp+16]                   ; the method
    mov esi, [ebx]
vm_class:
    test esi, esi
    jz vm_lookup
    push edx
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_DATA]
    push DWORD PTR [edi+M_NAME+TEXT_SIZE]
    push DWORD PTR [edi+M_NAME+TEXT_DATA]
    mov ecx, esi
    call @jbv_find_method@20
    pop edx
    test eax, eax
    jz vm_up
    cmp esi, edx
    je vm_found
    push eax
    push edx
    push edi
    push edx
    push eax
    push esi
    call overrides
    add esp, 16
    mov ecx, eax
    pop edx
    pop eax
    test ecx, ecx
    jnz vm_found
vm_up:
    mov esi, [esi+C_SUPER]
    jmp vm_class
vm_found:
    mov [ebx], esi
    jmp vm_ret
vm_lookup:
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_DATA]
    push DWORD PTR [edi+M_NAME+TEXT_SIZE]
    push DWORD PTR [edi+M_NAME+TEXT_DATA]
    mov ecx, ebx
    call @jbv_lookup_method@20
vm_ret:
    pop edi
    pop esi
    pop ebx
    ret 4
@jbv_virtual_method@12 ENDP
END

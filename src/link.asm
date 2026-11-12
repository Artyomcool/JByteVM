; Descriptors, class initialization and member linkage.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_kind@4:PROC
EXTERN SYSCALL @jbv_reference_type@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_check_reference@16:PROC
EXTERN SYSCALL @jbv_link@12:PROC
EXTERN SYSCALL @jbv_library_initialize@8:PROC
EXTERN SYSCALL @jbv_literal@16:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_exception_class@16:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_throw_detail@40:PROC
EXTERN SYSCALL @jbv_class_constant@16:PROC
EXTERN SYSCALL @jbv_lookup_field@20:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC
EXTERN SYSCALL @jbv_text_eq@16:PROC
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC

S_OOM       EQU 2
S_BAD_CLASS EQU 3
S_NOT_FOUND EQU 7
S_LINKAGE   EQU 8
S_LIMIT     EQU 10
S_CAST      EQU 16
ACC_PRIVATE EQU 2
ACC_STATIC  EQU 8
ACC_INTERFACE EQU 200h
ACC_ABSTRACT EQU 400h
K_REF       EQU 1

.const
s_clinit DB '<clinit>'
s_void   DB '()V'
n_error  DB 'java/lang/Error'
n_ncdfe  DB 'java/lang/NoClassDefFoundError', 0
n_soe    DB 'java/lang/StackOverflowError', 0
n_eiie   DB 'java/lang/ExceptionInInitializerError', 0
n_icce   DB 'java/lang/IncompatibleClassChangeError', 0
n_nsfe   DB 'java/lang/NoSuchFieldError', 0
n_nsme   DB 'java/lang/NoSuchMethodError', 0
IF JBV_PROFILE_FULL
n_handle DB 'java/lang/invoke/MethodHandle'
s_exact  DB 'invokeExact'
ENDIF

.code
; ---- descriptors
; int jbv_descriptor_type(JbvText d, uint32_t *pos, uint32_t *width): one field type at *pos
@jbv_descriptor_type@16 PROC SYSCALL ; ecx pos, edx width, [esp+4] d
    push ebx
    push esi
    push edi
    mov esi, [esp+16]
    movzx edi, WORD PTR [esp+20]
    mov ebx, [ecx]
    xor eax, eax                        ; the dimensions
dt_array:
    cmp ebx, edi
    jae dt_bad
    cmp BYTE PTR [esi+ebx], '['
    jne @F
    inc ebx
    inc eax
    jmp dt_array
@@:
    cmp eax, 255
    ja dt_bad
    mov ah, [esi+ebx]
    inc ebx
    mov DWORD PTR [edx], 1
    cmp ah, 'L'
    jne dt_primitive
    push ebx
dt_name:
    cmp ebx, edi
    jae dt_bad_name
    mov al, [esi+ebx]
    cmp al, ';'
    je dt_named
    cmp al, '['
    je dt_bad_name
    cmp al, '.'
    je dt_bad_name
    test al, al
    jz dt_bad_name
    inc ebx
    jmp dt_name
dt_named:
    pop eax
    cmp eax, ebx
    je dt_bad
    inc ebx
    jmp dt_ok
dt_bad_name:
    pop eax
    jmp dt_bad
dt_primitive:
    cmp ah, 'J'
    je dt_wide
    cmp ah, 'D'
    je dt_wide
    cmp ah, 'F'
    je dt_ok
    cmp ah, 'I'
    je dt_ok
    cmp ah, 'B'
    je dt_ok
    cmp ah, 'C'
    je dt_ok
    cmp ah, 'S'
    je dt_ok
    cmp ah, 'Z'
    jne dt_bad
    jmp dt_ok
dt_wide:
    test al, al                         ; an array of them is one slot
    jnz dt_ok
    mov DWORD PTR [edx], 2
dt_ok:
    mov [ecx], ebx
    mov eax, 1
    jmp dt_ret
dt_bad:
    xor eax, eax
dt_ret:
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_descriptor_type@16 ENDP
; eax = &JbvText: one type at [ebp-16] (pos), its width to [ebp-20] -> eax as above
D_POS   EQU -16
D_WIDTH EQU -20
dtype_at:
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    lea ecx, [ebp+D_POS]
    lea edx, [ebp+D_WIDTH]
    call @jbv_descriptor_type@16
    ret
; JbvStatus jbv_signature(JbvText d, uint16_t *args, int *returns)
@jbv_signature@16 PROC SYSCALL      ; ecx args, edx returns, [ebp+8] d
    push ebp
    mov ebp, esp
    sub esp, 28
    push ebx
    push esi
    push edi
    mov [ebp-24], ecx
    mov [ebp-28], edx
    mov esi, [ebp+8]
    movzx edi, WORD PTR [ebp+12]
    cmp edi, 3
    jb sg_bad
    cmp BYTE PTR [esi], '('
    jne sg_bad
    mov DWORD PTR [ebp+D_POS], 1
    xor ebx, ebx                        ; slots
sg_parameter:
    mov eax, [ebp+D_POS]
    cmp eax, edi
    jae sg_close
    cmp BYTE PTR [esi+eax], ')'
    je sg_close
    lea eax, [ebp+8]
    call dtype_at
    test eax, eax
    jz sg_bad
    add ebx, [ebp+D_WIDTH]
    cmp ebx, 255
    ja sg_bad
    jmp sg_parameter
sg_close:
    inc eax
    cmp eax, edi
    jae sg_bad
    mov [ebp+D_POS], eax
    mov ecx, [ebp-28]
    cmp BYTE PTR [esi+eax], 'V'
    jne @F
    mov DWORD PTR [ecx], 0
    inc DWORD PTR [ebp+D_POS]
    jmp sg_end
@@:
    push ecx
    movzx ecx, BYTE PTR [esi+eax]
    call @jbv_kind@4
    pop ecx
    movzx eax, al
    inc eax
    mov [ecx], eax
    lea eax, [ebp+8]
    call dtype_at
    test eax, eax
    jz sg_bad
sg_end:
    cmp [ebp+D_POS], edi
    jne sg_bad
    mov ecx, [ebp-24]
    mov [ecx], bx
    xor eax, eax
    jmp sg_ret
sg_bad:
    mov eax, S_BAD_CLASS
sg_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_signature@16 ENDP
; JbvText jbv_return_type(JbvText d): after ')', or {0, 0}
@jbv_return_type@8 PROC SYSCALL
    push ebp
    mov ebp, esp
    sub esp, 20
    mov DWORD PTR [ebp+D_POS], 1
rt_parameter:
    mov eax, [ebp+D_POS]
    movzx ecx, WORD PTR [ebp+12]
    cmp eax, ecx
    jae rt_close
    mov edx, [ebp+8]
    cmp BYTE PTR [edx+eax], ')'
    je rt_close
    lea eax, [ebp+8]
    call dtype_at
    test eax, eax
    jnz rt_parameter
    jmp rt_none
rt_close:
    inc eax
    movzx ecx, WORD PTR [ebp+12]
    cmp eax, ecx
    jae rt_none
    mov edx, ecx
    sub edx, eax
    add eax, [ebp+8]
    jmp rt_ret
rt_none:
    xor eax, eax
    xor edx, edx
rt_ret:
    mov esp, ebp
    pop ebp
    ret 8
@jbv_return_type@8 ENDP
@jbv_prepare_method@4 PROC SYSCALL  ; ecx method: argument slots, result kind, return char
    push ebx
    mov ebx, ecx
    push 0                              ; slots
    push 0                              ; result
    push DWORD PTR [ebx+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [ebx+M_DESCRIPTOR+TEXT_DATA]
    lea ecx, [esp+12]
    lea edx, [esp+8]
    call @jbv_signature@16
    pop eax
    pop ecx
    movzx ecx, cx
    test WORD PTR [ebx+M_FLAGS], ACC_STATIC
    jnz @F
    inc ecx                             ; the receiver
@@:
    mov [ebx+M_ARG_SLOTS], cx
    mov [ebx+M_RESULT_KIND], al
    movzx ecx, WORD PTR [ebx+M_DESCRIPTOR+TEXT_SIZE]
    mov al, 'V'
    jecxz @F
    mov edx, [ebx+M_DESCRIPTOR+TEXT_DATA]
    mov al, [edx+ecx-1]
@@:
    mov [ebx+M_RETURN_CHAR], al
    pop ebx
    ret
@jbv_prepare_method@4 ENDP

; JbvStatus jbv_arguments(vm, owner, method, args, count, refs, pin): with refs, the slots'
; reference bits; else references checked (receiver: an instance of owner), pinned (pin > 0)
; or unpinned (pin < 0)
G_VM    EQU -4
G_OWNER EQU -8
G_TYPE  EQU -28       ; JbvText
@jbv_arguments@28 PROC SYSCALL      ; ecx vm, edx owner, [ebp+8] method, args, count, refs, pin
    push ebp
    mov ebp, esp
    sub esp, 28
    push ebx
    push esi
    push edi
    mov [ebp+G_VM], ecx
    mov [ebp+G_OWNER], edx
    mov DWORD PTR [ebp+D_POS], 1
    xor ebx, ebx
    mov esi, [ebp+8]
ag_slot:
    movzx eax, WORD PTR [ebp+16]
    cmp ebx, eax
    jae ag_ok
    mov DWORD PTR [ebp+D_WIDTH], 1
    mov edi, 3                          ; bit 0 a reference, bit 1 the receiver
    test ebx, ebx
    jnz @F
    test WORD PTR [esi+M_FLAGS], ACC_STATIC
    jz ag_width
@@:
    push DWORD PTR [ebp+D_POS]
    lea eax, [esi+M_DESCRIPTOR]
    call dtype_at
    pop ecx
    test eax, eax
    jz ag_bad
    mov eax, [esi+M_DESCRIPTOR+TEXT_DATA]
    add eax, ecx
    mov [ebp+G_TYPE], eax
    mov eax, [ebp+D_POS]
    sub eax, ecx
    mov [ebp+G_TYPE+4], eax
    push eax
    push DWORD PTR [ebp+G_TYPE]
    call @jbv_reference_type@8
    neg eax
    sbb edi, edi
    neg edi
ag_width:
    movzx eax, WORD PTR [ebp+16]
    sub eax, ebx
    cmp [ebp+D_WIDTH], eax
    ja ag_bad
    mov ecx, [ebp+20]
    test ecx, ecx
    jz ag_norefs
    mov eax, edi
    and al, 1
    mov [ecx+ebx], al
    cmp DWORD PTR [ebp+D_WIDTH], 2
    jne ag_next_width
    mov BYTE PTR [ecx+ebx+1], 0
ag_next_width:
    add ebx, [ebp+D_WIDTH]
    jmp ag_slot
ag_norefs:
    test edi, 1
    jz ag_next_width
    mov eax, [ebp+12]
    mov edx, [eax+ebx*4]
    cmp DWORD PTR [ebp+24], 0
    jge @F
    push edx
    push DWORD PTR [ebp+G_VM]
    call jbv_release
    add esp, 8
    inc ebx
    jmp ag_slot
@@:
    test edi, 2
    jz ag_typed
    push 0
    push esp
    mov ecx, [ebp+G_VM]
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz ag_fail
    mov ecx, [ecx]
    mov edx, [ebp+G_OWNER]
    call @jbv_assignable@8
    test eax, eax
    mov eax, S_CAST
    jz ag_fail
    jmp ag_pin
ag_typed:
    push DWORD PTR [ebp+G_TYPE+4]
    push DWORD PTR [ebp+G_TYPE]
    mov ecx, [ebp+G_VM]
    call @jbv_check_reference@16
    test eax, eax
    jnz ag_fail
ag_pin:
    cmp DWORD PTR [ebp+24], 0
    jle ag_next
    mov eax, [ebp+12]
    push DWORD PTR [eax+ebx*4]
    push DWORD PTR [ebp+G_VM]
    call jbv_retain
    add esp, 8
    test eax, eax
    jnz ag_fail
ag_next:
    inc ebx
    jmp ag_slot
ag_ok:
    xor eax, eax
    jmp ag_ret
ag_bad:
    mov eax, S_BAD_CLASS
ag_fail:                                ; pinned ones are unpinned again
    cmp DWORD PTR [ebp+24], 0
    jle ag_ret
    push eax
    push -1
    push 0
    push ebx
    push DWORD PTR [ebp+12]
    push esi
    mov edx, [ebp+G_OWNER]
    mov ecx, [ebp+G_VM]
    call @jbv_arguments@28
    pop eax
ag_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 20
@jbv_arguments@28 ENDP

; ---- class initialization (JVMS 5.5)
; ebx = vm, eax = an interface: initialized if it (or a superinterface) declares a default method
init_defaults:
    push esi
    mov esi, eax
    push 0
id_face:
    mov ecx, [esp]
    cmp cx, [esi+C_INTERFACE_COUNT]
    jae id_methods
    mov eax, [esi+C_INTERFACES]
    mov eax, [eax+ecx*4]
    call init_defaults
    test eax, eax
    jnz id_ret
    inc DWORD PTR [esp]
    jmp id_face
id_methods:
    xor eax, eax
    movzx ecx, WORD PTR [esi+C_METHOD_COUNT]
    mov edx, [esi+C_METHODS]
@@:
    test ecx, ecx
    jz id_ret
    test WORD PTR [edx+M_FLAGS], ACC_STATIC or ACC_ABSTRACT or ACC_PRIVATE
    jz @F
    add edx, M_SIZEOF
    dec ecx
    jmp @B
@@:
    mov edx, esi
    mov ecx, ebx
    call @jbv_initialize@8
id_ret:
    pop ecx
    pop esi
    ret
@jbv_initialize@8 PROC SYSCALL      ; ecx vm, edx class
    push ebp
    mov ebp, esp
    sub esp, 8                          ; the ignored <clinit> result
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    mov al, [esi+C_INIT_STATE]
    dec al
    cmp al, 1
    jbe in_ok                           ; in progress or done
    cmp BYTE PTR [esi+C_INIT_STATE], 3
    jne @F
    push S_LINKAGE
    push 0
    mov edx, OFFSET n_ncdfe
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp in_ret
@@:
    push 0
    mov edx, esi
    mov ecx, ebx
    call @jbv_link@12
    test eax, eax
    jnz in_ret
    mov eax, [ebx+VM_DEPTH]
    cmp eax, [ebx+VM_MAX_DEPTH]
    jb @F
    push S_LIMIT
    push 0
    mov edx, OFFSET n_soe
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp in_ret
@@:
    inc DWORD PTR [ebx+VM_DEPTH]
    mov BYTE PTR [esi+C_INIT_STATE], 1
    mov edx, esi
    mov ecx, ebx
    call @jbv_library_initialize@8
    mov edi, eax                        ; the status from here on
    test edi, edi
    jnz in_super
    push 0                              ; static reference constants
in_field:
    mov ecx, [esp]
    cmp cx, [esi+C_FIELD_COUNT]
    jae in_fields
    imul edx, ecx, FIELD_SIZEOF
    add edx, [esi+C_FIELDS]
    test WORD PTR [edx+FIELD_FLAGS], ACC_STATIC
    jz in_next_field
    cmp WORD PTR [edx+FIELD_CONSTANT], 0
    je in_next_field
    push edx
    push DWORD PTR [edx+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edx+FIELD_DESCRIPTOR+TEXT_DATA]
    call @jbv_reference_type@8
    pop edx
    test eax, eax
    jz in_next_field
    lea eax, [edx+FIELD_VALUE]
    push eax
    movzx eax, WORD PTR [edx+FIELD_CONSTANT]
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_literal@16
    mov edi, eax
    test eax, eax
    jnz in_fields
in_next_field:
    inc DWORD PTR [esp]
    jmp in_field
in_fields:
    pop ecx
in_super:
    test edi, edi
    jnz in_clinit
    test WORD PTR [esi+C_FLAGS], ACC_INTERFACE
    jnz in_clinit
    mov edx, [esi+C_SUPER]
    test edx, edx
    jz @F
    mov ecx, ebx
    call @jbv_initialize@8
    mov edi, eax
    test eax, eax
    jnz in_clinit
@@:
    push 0                              ; the superinterfaces with default methods
in_face:
    mov ecx, [esp]
    cmp cx, [esi+C_INTERFACE_COUNT]
    jae in_faces
    mov eax, [esi+C_INTERFACES]
    mov eax, [eax+ecx*4]
    call init_defaults
    mov edi, eax
    test eax, eax
    jnz in_faces
    inc DWORD PTR [esp]
    jmp in_face
in_faces:
    pop ecx
in_clinit:
    test edi, edi
    jnz in_failed
    push 3
    push OFFSET s_void
    push 8
    push OFFSET s_clinit
    mov ecx, esi
    call @jbv_find_method@20
    test eax, eax
    jz in_done
    lea ecx, [ebp-8]
    push ecx
    push 0
    push 0
    push 0
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_execute@28
    mov edi, eax
in_failed:                              ; a thrown non-Error becomes ExceptionInInitializerError
    test edi, edi
    jz in_done
    cmp DWORD PTR [ebx+VM_EXCEPTION], 0
    je in_done
    push 0
    push esp
    mov edx, [ebx+VM_EXCEPTION]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz in_no_object
    push 0
    mov edx, esp
    push 15
    push OFFSET n_error
    mov ecx, ebx
    call @jbv_exception_class@16
    pop edx                             ; Error
    pop ecx                             ; the exception
    test eax, eax
    jnz in_done
    mov ecx, [ecx]
    call @jbv_assignable@8
    test eax, eax
    jnz in_done
    push edi
    push DWORD PTR [ebx+VM_EXCEPTION]
    mov edx, OFFSET n_eiie
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp in_done
in_no_object:
    pop ecx
in_done:
    mov al, 2
    test edi, edi
    jz @F
    mov al, 3
@@:
    mov [esi+C_INIT_STATE], al
    mov [esi+C_INIT_ERROR], edi
    dec DWORD PTR [ebx+VM_DEPTH]
    mov eax, edi
    jmp in_ret
in_ok:
    xor eax, eax
in_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
@jbv_initialize@8 ENDP

; ---- member linkage: a pool entry resolved once, its JbvLink kept in the entry's text
K_OWNER  EQU -4
K_SYMBOL EQU -8
K_NAME   EQU -16      ; JbvText
K_DESC   EQU -24      ; JbvText
; ebx = vm, eax = &a literal JbvText-ish (data, size), ecx = &JbvText -> eax = equal
text_eq_lit:
    push edx
    push eax
    push DWORD PTR [ecx+4]
    push DWORD PTR [ecx]
    call @jbv_text_eq@16
    ret
@jbv_link_member@16 PROC SYSCALL    ; ecx vm, edx class, [ebp+8] index, [ebp+12] out
    push ebp
    mov ebp, esp
    sub esp, 24
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    movzx eax, WORD PTR [ebp+8]
    imul esi, eax, CP_SIZEOF
    add esi, [edi+C_POOL]               ; the entry
    mov eax, [esi+CP_TEXT+TEXT_DATA]
    test eax, eax
    jnz lm_out
    movzx eax, WORD PTR [esi+CP_B]      ; the name and type
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    movzx ecx, WORD PTR [eax+CP_A]
    imul ecx, ecx, CP_SIZEOF
    add ecx, [edi+C_POOL]
    mov edx, [ecx+CP_TEXT]
    mov [ebp+K_NAME], edx
    mov edx, [ecx+CP_TEXT+4]
    mov [ebp+K_NAME+4], edx
    movzx ecx, WORD PTR [eax+CP_B]
    imul ecx, ecx, CP_SIZEOF
    add ecx, [edi+C_POOL]
    mov edx, [ecx+CP_TEXT]
    mov [ebp+K_DESC], edx
    mov edx, [ecx+CP_TEXT+4]
    mov [ebp+K_DESC+4], edx
    lea eax, [ebp+K_OWNER]
    push eax
    movzx eax, WORD PTR [esi+CP_A]
    push eax
    mov edx, edi
    mov ecx, ebx
    call @jbv_class_constant@16
    test eax, eax
    jnz lm_ret
    mov eax, [ebp+K_OWNER]
    mov [ebp+K_SYMBOL], eax
    push DWORD PTR [ebp+K_DESC+4]
    push DWORD PTR [ebp+K_DESC]
    push DWORD PTR [ebp+K_NAME+4]
    push DWORD PTR [ebp+K_NAME]
    lea ecx, [ebp+K_OWNER]
    cmp BYTE PTR [esi+CP_TAG], 9
    jne lm_method
    call @jbv_lookup_field@20
    mov edi, eax
    test eax, eax
    jnz lm_make
    mov edx, OFFSET n_nsfe
    push S_NOT_FOUND                    ; NoSuchFieldError owner.name descriptor (or name descriptor)
    push 1
    push DWORD PTR [ebp+K_DESC+4]
    push DWORD PTR [ebp+K_DESC]
    mov eax, [ebp+K_OWNER]
    test eax, eax
    jz @F
    push DWORD PTR [ebp+K_NAME+4]
    push DWORD PTR [ebp+K_NAME]
    push DWORD PTR [eax+C_NAME+TEXT_SIZE]
    push DWORD PTR [eax+C_NAME+TEXT_DATA]
    jmp lm_detail
@@:
    push DWORD PTR [ebp+K_DESC+4]
    push DWORD PTR [ebp+K_DESC]
    push DWORD PTR [ebp+K_NAME+4]
    push DWORD PTR [ebp+K_NAME]
lm_detail:
    mov ecx, ebx
    call @jbv_throw_detail@40
    jmp lm_ret
lm_method:
    add esp, 16                         ; (the lookup arguments are pushed again below)
    mov eax, [ebp+K_SYMBOL]
    IF JBV_PROFILE_FULL
    cmp BYTE PTR [esi+CP_TAG], 10       ; MethodHandle.invoke/invokeExact: signature polymorphic
    jne lm_kind
    cmp WORD PTR [eax+C_NAME+TEXT_SIZE], 29
    jne lm_kind
    push esi
    push edi
    mov esi, [eax+C_NAME+TEXT_DATA]
    mov edi, OFFSET n_handle
    mov ecx, 29
    repe cmpsb
    pop edi
    pop esi
    jne lm_kind
    mov edx, 11
    mov eax, OFFSET s_exact
    lea ecx, [ebp+K_NAME]
    call text_eq_lit
    test eax, eax
    jnz @F
    mov edx, 6
    mov eax, OFFSET s_exact
    lea ecx, [ebp+K_NAME]
    call text_eq_lit
    test eax, eax
    jz lm_kind_check
@@:
    xor edi, edi
    jmp lm_make
lm_kind_check:
    mov eax, [ebp+K_SYMBOL]
lm_kind:
    ENDIF
    test WORD PTR [eax+C_FLAGS], ACC_INTERFACE  ; Methodref to an interface or the reverse
    setnz al
    cmp BYTE PTR [esi+CP_TAG], 11
    sete ah
    cmp al, ah
    jne lm_icce
    push DWORD PTR [ebp+K_DESC+4]
    push DWORD PTR [ebp+K_DESC]
    push DWORD PTR [ebp+K_NAME+4]
    push DWORD PTR [ebp+K_NAME]
    lea ecx, [ebp+K_OWNER]
    call @jbv_lookup_method@20
    mov edi, eax
    test eax, eax
    jnz lm_make
    mov eax, [ebp+K_OWNER]
    test eax, eax
    jz lm_icce
    push S_NOT_FOUND
    push 1
    push DWORD PTR [ebp+K_DESC+4]
    push DWORD PTR [ebp+K_DESC]
    push DWORD PTR [ebp+K_NAME+4]
    push DWORD PTR [ebp+K_NAME]
    push DWORD PTR [eax+C_NAME+TEXT_SIZE]
    push DWORD PTR [eax+C_NAME+TEXT_DATA]
    mov edx, OFFSET n_nsme
    jmp lm_detail
lm_icce:
    push S_LINKAGE
    push 0
    mov edx, OFFSET n_icce
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp lm_ret
lm_make:
    mov edx, LK_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz lm_oom
    mov ecx, [ebp+K_OWNER]
    mov [eax+LK_OWNER], ecx
    mov ecx, [ebp+K_SYMBOL]
    mov [eax+LK_SYMBOLIC], ecx
    mov [eax+LK_MEMBER], edi
    cmp BYTE PTR [esi+CP_TAG], 9
    je lm_field
    test edi, edi
    jz lm_linked
    mov cx, [edi+M_ARG_SLOTS]
    mov [eax+LK_ARGC], cx
    mov cl, [edi+M_RESULT_KIND]
    mov [eax+LK_RESULT], cl
    jmp lm_linked
lm_field:
    push eax
    mov ecx, [edi+FIELD_DESCRIPTOR+TEXT_DATA]
    movzx ecx, BYTE PTR [ecx]
    mov [eax+LK_TYPE], cl
    call @jbv_kind@4
    mov edx, eax
    pop eax
    mov [eax+LK_KIND], dl
    xor ecx, ecx                        ; one-slot int/ref: 1 instance, 2 static
    cmp dl, K_REF
    ja @F
    inc ecx
    test WORD PTR [edi+FIELD_FLAGS], ACC_STATIC
    jz @F
    inc ecx
@@:
    mov [eax+LK_FAST], cl
    mov ecx, [edi+FIELD_SLOT]
    mov [eax+LK_SLOT], ecx
    lea ecx, [edi+FIELD_VALUE]
    mov [eax+LK_ADDRESS], ecx
lm_linked:
    mov [esi+CP_TEXT+TEXT_DATA], eax
lm_out:
    mov ecx, [ebp+12]
    mov [ecx], eax
    xor eax, eax
    jmp lm_ret
lm_oom:
    mov eax, S_OOM
lm_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_link_member@16 ENDP

@jbv_narrow@8 PROC SYSCALL          ; ecx value, dl type: an int as boolean/char/byte/short
    mov eax, ecx
    cmp dl, 'Z'
    jne @F
    and eax, 1
    ret
@@:
    cmp dl, 'C'
    jne @F
    movzx eax, ax
    ret
@@:
    cmp dl, 'B'
    jne @F
    movsx eax, al
    ret
@@:
    cmp dl, 'S'
    jne @F
    movsx eax, ax
@@:
    ret
@jbv_narrow@8 ENDP
END

; Direct method handles for x86 (dynamic.c is the reference and serves x64): MethodType
; and MethodHandle constants, handle invocation with argument conversion, signature
; polymorphic calls, and the runtime natives behind java.lang.invoke.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_class_constant@16:PROC
EXTERN SYSCALL @jbv_literal@16:PROC
EXTERN SYSCALL @jbv_string_mutf@16:PROC
EXTERN SYSCALL @jbv_text_bytes@12:PROC
EXTERN SYSCALL @jbv_text_eq@16:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_lookup_field@20:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC
EXTERN SYSCALL @jbv_virtual_method@12:PROC
EXTERN SYSCALL @jbv_same_package@8:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_mirror@12:PROC
EXTERN SYSCALL @jbv_mirror_type@8:PROC
EXTERN SYSCALL @jbv_type_class@16:PROC
EXTERN SYSCALL @jbv_descriptor_type@16:PROC
EXTERN SYSCALL @jbv_signature@16:PROC
EXTERN SYSCALL @jbv_return_type@8:PROC
EXTERN SYSCALL @jbv_reference_type@8:PROC
EXTERN SYSCALL @jbv_kind@4:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_from_object@20:PROC
EXTERN SYSCALL @jbv_box@20:PROC
EXTERN SYSCALL @jbv_unbox@20:PROC
EXTERN SYSCALL @jbv_array_set@20:PROC
EXTERN SYSCALL @jbv_capture_trace@8:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC

S_BAD_ARG   EQU 1
S_OOM       EQU 2
S_UNSUPPORTED EQU 6
S_NOT_FOUND EQU 7
S_LINKAGE   EQU 8
S_NULL      EQU 12
S_BOUNDS    EQU 13
S_CAST      EQU 16
S_EXCEPTION EQU 22
K_INT       EQU 0
K_REF       EQU 1
K_LONG      EQU 2
K_FLOAT     EQU 4
K_DOUBLE    EQU 5
ACC_STATIC  EQU 8
ACC_FINAL   EQU 10h
ACC_ABSTRACT EQU 400h
DATA0       EQU 4
D_POS       EQU -52   ; the descriptor cursor of every frame here (dtype)
D_WIDTH     EQU -56

.const
n_handle  DB 29, 'java/lang/invoke/MethodHandle'
n_type    DB 27, 'java/lang/invoke/MethodType'
n_object  DB 'java/lang/Object'
codes     DB 'ZBCSIJFDV'
wrappers  DB 17, 'java/lang/Boolean', 14, 'java/lang/Byte', 19, 'java/lang/Character', 15, 'java/lang/Short'
          DB 17, 'java/lang/Integer', 14, 'java/lang/Long', 15, 'java/lang/Float', 16, 'java/lang/Double', 14, 'java/lang/Void'
e_nsfe    DB 'java/lang/NoSuchFieldError', 0
e_nsme    DB 'java/lang/NoSuchMethodError', 0
e_icce    DB 'java/lang/IncompatibleClassChangeError', 0
e_ame     DB 'java/lang/AbstractMethodError', 0
e_wmte    DB 'java/lang/invoke/WrongMethodTypeException', 0
e_nsfx    DB 'java/lang/NoSuchFieldException', 0
e_nsmx    DB 'java/lang/NoSuchMethodException', 0
e_iae     DB 'java/lang/IllegalAccessException', 0
e_iarg    DB 'java/lang/IllegalArgumentException', 0
ct_kinds  DB K_INT, K_FLOAT, K_LONG, K_DOUBLE

.code
; eax = &JbvText: one type at [ebp+D_POS], its width to [ebp+D_WIDTH] -> eax = ok
dtype:
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    lea ecx, [ebp+D_POS]
    lea edx, [ebp+D_WIDTH]
    call @jbv_descriptor_type@16
    ret
; ebx = vm, edx = an error name, eax = the status -> eax (thrown)
throw:
    push eax
    push 0
    mov ecx, ebx
    call @jbv_throw_named@16
    ret
; ebx = vm, ecx = ref -> (released)
release:
    push ecx
    push ebx
    call jbv_release
    add esp, 8
    ret
; ebx = vm, eax = a counted class name, edx = &ref -> eax status, edx = the new instance
new_object:
    push edx
    push 0
    mov edx, esp
    movzx ecx, BYTE PTR [eax]
    push ecx
    inc eax
    push eax
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop edx
    pop ecx
    test eax, eax
    jnz no_ret
    push ecx
    push ecx
    push 0
    mov ecx, ebx
    call @jbv_new@16
    pop ecx
    test eax, eax
    jnz no_ret
    push 0
    push esp
    mov edx, [ecx]
    mov ecx, ebx
    call @jbv_object@12
    pop edx
no_ret:
    ret
; ebx = vm, eax = &a descriptor JbvText, edx = &out -> eax status: a MethodType of it
method_type:
    push edi
    mov edi, edx
    push 0                              ; the String
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    lea edx, [esp+8]
    mov ecx, ebx
    call @jbv_string_mutf@16
    test eax, eax
    jnz mt_ret
    push DWORD PTR [esp]
    push ebx
    call jbv_retain
    add esp, 8
    mov eax, OFFSET n_type
    mov edx, edi
    call new_object
    test eax, eax
    jnz mt_release
    mov ecx, [esp]
    mov [edx+DATA0], ecx
    push ecx
    mov ecx, ebx
    call @jbv_barrier_checked@12
    xor eax, eax
mt_release:
    mov ecx, [esp]
    push eax
    call release
    pop eax
mt_ret:
    pop ecx
    pop edi
    ret
; eax = a class, edi = the buffer: its descriptor appended
class_descriptor:
    mov cl, [eax+C_PRIMITIVE]
    test cl, cl
    jz @F
    mov [edi], cl
    inc edi
    ret
@@:
    push esi
    cmp BYTE PTR [eax+C_ARRAY_KIND], 0
    jne @F
    mov BYTE PTR [edi], 'L'
    inc edi
@@:
    movzx ecx, WORD PTR [eax+C_NAME+TEXT_SIZE]
    mov esi, [eax+C_NAME+TEXT_DATA]
    rep movsb
    cmp BYTE PTR [eax+C_ARRAY_KIND], 0
    jne @F
    mov BYTE PTR [edi], ';'
    inc edi
@@:
    pop esi
    ret

; ebx = vm; [ebp+8] caller, symbolic, name (JbvText), descriptor (JbvText), kind, out
; -> eax status: a direct MethodHandle {member, owner, kind | varargs, type, caller}
MP_CALLER EQU 8
MP_SYMBOL EQU 12
MP_NAME   EQU 16
MP_DESC   EQU 24
MP_KIND   EQU 32
MP_OUT    EQU 36
MK_OWNER EQU -4
MK_MEMBER EQU -8
MK_FLAGS EQU -12
MK_BUFFER EQU -16
MK_TYPE  EQU -20
MK_CALLER EQU -24
MK_TEXT  EQU -32      ; the invocation descriptor
make_handle:
    push ebp
    mov ebp, esp
    sub esp, 32
    push esi
    push edi
    mov eax, [ebp+MP_SYMBOL]
    mov [ebp+MK_OWNER], eax
    xor eax, eax
    mov [ebp+MK_TYPE], eax
    mov [ebp+MK_CALLER], eax
    push DWORD PTR [ebp+MP_DESC+4]
    push DWORD PTR [ebp+MP_DESC]
    push DWORD PTR [ebp+MP_NAME+4]
    push DWORD PTR [ebp+MP_NAME]
    lea ecx, [ebp+MK_OWNER]
    cmp DWORD PTR [ebp+MP_KIND], 4
    ja mk_method
    call @jbv_lookup_field@20
    mov edx, OFFSET e_nsfe
    test eax, eax
    jz mk_missing
    mov [ebp+MK_MEMBER], eax
    movzx ecx, WORD PTR [eax+FIELD_FLAGS]
    mov [ebp+MK_FLAGS], ecx
    mov eax, [ebp+MP_KIND]               ; static: kinds 2 and 4
    cmp eax, 2
    je @F
    cmp eax, 4
@@:
    sete al
    jmp mk_static
mk_method:
    call @jbv_lookup_method@20
    mov edx, OFFSET e_nsme
    test eax, eax
    jz mk_missing
    mov [ebp+MK_MEMBER], eax
    movzx ecx, WORD PTR [eax+M_FLAGS]
    mov [ebp+MK_FLAGS], ecx
    cmp DWORD PTR [ebp+MP_KIND], 6
    sete al
mk_static:
    test ecx, ACC_STATIC
    setnz ah
    cmp al, ah
    je @F
    mov edx, OFFSET e_icce
    mov eax, S_LINKAGE
    call throw
    jmp mk_ret
mk_missing:
    mov eax, S_NOT_FOUND
    call throw
    jmp mk_ret
@@:
    mov eax, [ebp+MP_SYMBOL]             ; the buffer: descriptor + two class names + 12
    movzx edx, WORD PTR [eax+C_NAME+TEXT_SIZE]
    add edx, edx
    movzx eax, WORD PTR [ebp+MP_DESC+4]
    lea edx, [edx+eax+12]
    mov eax, S_BAD_ARG
    cmp edx, 0FFFFh
    ja mk_ret
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jnz @F
    mov eax, S_OOM
    jmp mk_ret
@@:
    mov [ebp+MK_BUFFER], eax
    mov edi, eax
    mov BYTE PTR [edi], '('
    inc edi
    mov eax, [ebp+MP_KIND]               ; a receiver first: kinds 1 3 5 7 9
    test al, 1
    jz mk_parameters
    mov eax, [ebp+MP_SYMBOL]
    mov ecx, [ebp+MP_CALLER]             ; protected from another package: the caller's type
    test ecx, ecx
    jz mk_receiver
    test DWORD PTR [ebp+MK_FLAGS], 4
    jz mk_receiver
    mov edx, [ebp+MK_OWNER]
    push eax
    call @jbv_same_package@8
    test eax, eax
    pop eax
    jnz mk_receiver
    mov eax, [ebp+MP_CALLER]
mk_receiver:
    call class_descriptor
mk_parameters:
    mov esi, [ebp+MP_DESC]
    movzx ecx, WORD PTR [ebp+MP_DESC+4]
    cmp DWORD PTR [ebp+MP_KIND], 5
    jb mk_field
    inc esi                             ; the method's parameters, ')'
    dec ecx
@@:
    test ecx, ecx
    jz mk_close
    cmp BYTE PTR [esi], ')'
    je mk_close
    movsb
    dec ecx
    jmp @B
mk_close:
    mov BYTE PTR [edi], ')'
    inc edi
    cmp DWORD PTR [ebp+MP_KIND], 8       ; a constructor returns its class
    jne @F
    mov eax, [ebp+MP_SYMBOL]
    call class_descriptor
    jmp mk_described
@@:
    jecxz mk_described
    inc esi
    dec ecx
    rep movsb
    jmp mk_described
mk_field:                               ; getters (T) and setters (T)V
    mov eax, [ebp+MP_KIND]
    cmp eax, 3
    jb @F
    push esi
    push ecx
    rep movsb
    pop ecx
    pop esi
@@:
    mov BYTE PTR [edi], ')'
    inc edi
    cmp eax, 3
    jb @F
    mov BYTE PTR [edi], 'V'
    inc edi
    jmp mk_described
@@:
    rep movsb
mk_described:
    mov eax, [ebp+MK_BUFFER]
    mov [ebp+MK_TEXT], eax
    sub edi, eax
    mov [ebp+MK_TEXT+4], edi
    lea eax, [ebp+MK_TEXT]
    lea edx, [ebp+MK_TYPE]
    call method_type
    push eax
    mov edx, [ebp+MK_BUFFER]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
    test eax, eax
    jnz mk_ret
    push DWORD PTR [ebp+MK_TYPE]
    push ebx
    call jbv_retain
    add esp, 8
    xor eax, eax
    mov edx, [ebp+MP_CALLER]
    test edx, edx
    jz @F
    lea eax, [ebp+MK_CALLER]
    push eax
    mov ecx, ebx
    call @jbv_mirror@12
    test eax, eax
    jnz mk_release
@@:
    mov eax, OFFSET n_handle
    mov edx, [ebp+MP_OUT]
    call new_object
    test eax, eax
    jnz mk_release
    mov ecx, [ebp+MK_MEMBER]
    mov [edx+DATA0], ecx
    mov DWORD PTR [edx+DATA0+4], 0
    mov ecx, [ebp+MK_OWNER]
    mov [edx+DATA0+8], ecx
    mov DWORD PTR [edx+DATA0+12], 0
    mov ecx, [ebp+MP_KIND]
    cmp ecx, 5                          ; varargs methods
    jb @F
    test DWORD PTR [ebp+MK_FLAGS], 80h
    jz @F
    or ecx, 80h
@@:
    mov [edx+DATA0+16], ecx
    mov ecx, [ebp+MK_TYPE]
    mov [edx+DATA0+20], ecx
    mov ecx, [ebp+MK_CALLER]
    mov [edx+DATA0+24], ecx
mk_release:
    mov ecx, [ebp+MK_TYPE]
    push eax
    call release
    pop eax
mk_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret 32
; ebx = vm, eax = a handle object, edx = &JbvText -> eax status: its type's descriptor (a new block)
handle_descriptor:
    push edx
    push 0
    push esp
    mov edx, [eax+DATA0+20]
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    pop edx
    test eax, eax
    jnz @F
    push edx
    mov edx, [ecx+DATA0]
    mov ecx, ebx
    call @jbv_text_bytes@12
@@:
    ret

; ---- invoking a handle: ebx = vm; [ebp+8] handle, arguments (Object[]), out, collect
V_REF    EQU 8
V_ARRAY  EQU 12
V_OUT    EQU 16
V_COLLECT EQU 20
H_HANDLE EQU -4
H_LIST   EQU -8
H_OWNER  EQU -12
H_KIND   EQU -16
H_METHOD EQU -20
H_FIELD  EQU -24
H_D      EQU -32      ; JbvText
H_SLOTS  EQU -36
H_REFS   EQU -40
H_VARARGS EQU -44
H_RECEIVED EQU -48
H_PARAMS EQU -60
H_USED   EQU -64
H_ARGC   EQU -68
H_LENGTH EQU -72
H_I      EQU -76
H_BITS   EQU -84      ; uint64_t
H_TYPE   EQU -92      ; JbvText
H_ATYPE  EQU -96
H_TAIL   EQU -100
H_J      EQU -104
H_RECV   EQU -108
H_STATUS EQU -112
H_ARG    EQU -116
H_REMAIN EQU -120
invoke_handle:
    push ebp
    mov ebp, esp
    sub esp, 120
    push esi
    push edi
    lea edi, [ebp-120]                  ; all zero
    mov ecx, 120/4
    xor eax, eax
    rep stosd
    lea eax, [ebp+H_HANDLE]
    push eax
    mov edx, [ebp+V_REF]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ih_ret
    lea eax, [ebp+H_LIST]
    push eax
    mov edx, [ebp+V_ARRAY]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ih_ret
    mov eax, [ebp+H_HANDLE]             ; a MethodHandle, and an Object[]
    mov eax, [eax]
    mov ecx, [ebp+H_LIST]
    mov ecx, [ecx]
    cmp BYTE PTR [ecx+C_ARRAY_KIND], 'L'
    jne ih_cast
    cmp WORD PTR [eax+C_NAME+TEXT_SIZE], 29
    jne ih_cast
    mov esi, [eax+C_NAME+TEXT_DATA]
    mov edi, OFFSET n_handle+1
    mov ecx, 29
    repe cmpsb
    je @F
ih_cast:
    mov eax, S_CAST
    jmp ih_ret
@@:
    mov eax, [ebp+H_LIST]               ; the handle and the array move once anything allocates
    mov eax, [eax-4]
    mov [ebp+H_LENGTH], eax
    mov esi, [ebp+H_HANDLE]
    mov eax, [esi+DATA0+16]
    movzx eax, al
    mov [ebp+H_KIND], eax
    mov eax, [esi+DATA0+8]
    mov [ebp+H_OWNER], eax
    mov eax, [esi+DATA0]
    mov ecx, [ebp+H_KIND]
    and ecx, 127
    cmp ecx, 4
    ja @F
    mov [ebp+H_FIELD], eax
    jmp ih_described
@@:
    mov [ebp+H_METHOD], eax
ih_described:
    mov eax, esi
    lea edx, [ebp+H_D]
    call handle_descriptor
    test eax, eax
    jnz ih_ret
    mov DWORD PTR [ebp+D_POS], 1        ; the parameters: count and slots
ih_count:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+H_D]
    cmp BYTE PTR [ecx+eax], ')'
    je ih_counted
    lea eax, [ebp+H_D]
    call dtype
    test eax, eax
    mov eax, S_BAD_ARG
    jz ih_done
    inc DWORD PTR [ebp+H_PARAMS]
    mov eax, [ebp+D_WIDTH]
    add [ebp+H_USED], eax
    jmp ih_count
ih_counted:
    mov edx, [ebp+H_USED]
    lea edx, [edx*4+8]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [ebp+H_SLOTS], eax
    mov edx, [ebp+H_USED]
    add edx, 2
    mov ecx, ebx
    call @jbv_alloc@8
    mov [ebp+H_REFS], eax
    test eax, eax
    jz ih_oom
    cmp DWORD PTR [ebp+H_SLOTS], 0
    je ih_oom
    xor eax, eax
    mov [ebp+H_USED], eax
    mov DWORD PTR [ebp+D_POS], 1
    mov eax, [ebp+H_KIND]               ; newInvokeSpecial: the new instance first
    and eax, 127
    cmp eax, 8
    jne ih_parameter
    mov edx, [ebp+H_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz ih_done
    lea eax, [ebp+H_RECEIVED]
    push eax
    push 0
    mov edx, [ebp+H_OWNER]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz ih_done
    push DWORD PTR [ebp+H_RECEIVED]
    push ebx
    call jbv_retain
    add esp, 8
    mov eax, [ebp+H_RECEIVED]
    mov ecx, [ebp+H_SLOTS]
    mov [ecx], eax
    mov ecx, [ebp+H_REFS]
    mov BYTE PTR [ecx], 1
    mov DWORD PTR [ebp+H_USED], 1
ih_parameter:
    mov eax, [ebp+H_I]
    cmp eax, [ebp+H_PARAMS]
    jae ih_converted
    mov eax, [ebp+D_POS]                ; the parameter's type
    mov ecx, [ebp+H_D]
    add ecx, eax
    mov [ebp+H_TYPE], ecx
    push eax
    lea eax, [ebp+H_D]
    call dtype
    pop eax
    mov ecx, [ebp+D_POS]
    sub ecx, eax
    mov [ebp+H_TYPE+4], ecx
    cmp DWORD PTR [ebp+V_COLLECT], 0    ; the varargs tail collected into its array
    je ih_single
    test BYTE PTR [ebp+H_KIND], 80h
    jz ih_single
    mov eax, [ebp+H_I]
    inc eax
    cmp eax, [ebp+H_PARAMS]
    jne ih_single
    lea eax, [ebp+H_ATYPE]
    push DWORD PTR [ebp+H_TYPE+4]
    push DWORD PTR [ebp+H_TYPE]
    mov edx, eax
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz ih_done
    lea eax, [ebp+H_VARARGS]
    push eax
    mov eax, [ebp+H_LENGTH]
    sub eax, [ebp+H_ARGC]
    mov [ebp+H_REMAIN], eax
    push eax
    mov edx, [ebp+H_ATYPE]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz ih_done
    push DWORD PTR [ebp+H_VARARGS]
    push ebx
    call jbv_retain
    add esp, 8
    mov DWORD PTR [ebp+H_J], 0
ih_tail:
    mov eax, [ebp+H_REMAIN]
    cmp [ebp+H_J], eax
    jae ih_collected
    push 0
    push esp
    mov edx, [ebp+V_ARRAY]
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov ecx, [ebp+H_ARGC]
    inc DWORD PTR [ebp+H_ARGC]
    mov edx, [eax+ecx*4+DATA0]
    lea eax, [ebp+H_BITS]
    push eax
    movzx eax, WORD PTR [ebp+H_TYPE+4]  ; the component: the type without its '['
    dec eax
    push eax
    mov eax, [ebp+H_TYPE]
    inc eax
    push eax
    mov ecx, ebx
    call @jbv_from_object@20
    test eax, eax
    jnz ih_done
    lea eax, [ebp+H_TAIL]
    push eax
    mov edx, [ebp+H_VARARGS]
    mov ecx, ebx
    call @jbv_object@12
    push DWORD PTR [ebp+H_BITS+4]
    push DWORD PTR [ebp+H_BITS]
    mov eax, [ebp+H_ATYPE]
    movzx eax, BYTE PTR [eax+C_ARRAY_KIND]
    push eax
    mov edx, [ebp+H_J]
    mov ecx, [ebp+H_TAIL]
    call @jbv_array_set@20
    mov eax, [ebp+H_ATYPE]
    cmp BYTE PTR [eax+C_ARRAY_KIND], 'L'
    jne @F
    push DWORD PTR [ebp+H_BITS]
    mov edx, [ebp+H_TAIL]
    mov ecx, ebx
    call @jbv_barrier_checked@12
@@:
    inc DWORD PTR [ebp+H_J]
    jmp ih_tail
ih_collected:
    mov eax, [ebp+H_VARARGS]
    mov [ebp+H_ARG], eax
    jmp ih_convert
ih_single:
    mov eax, [ebp+H_ARGC]
    cmp eax, [ebp+H_LENGTH]
    jae ih_wrong
    push 0
    push esp
    mov edx, [ebp+V_ARRAY]
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov ecx, [ebp+H_ARGC]
    inc DWORD PTR [ebp+H_ARGC]
    mov eax, [eax+ecx*4+DATA0]
    mov [ebp+H_ARG], eax
ih_convert:                             ; the argument as the parameter's type, into the slots
    lea eax, [ebp+H_BITS]
    push eax
    push DWORD PTR [ebp+H_TYPE+4]
    push DWORD PTR [ebp+H_TYPE]
    mov edx, [ebp+H_ARG]
    mov ecx, ebx
    call @jbv_from_object@20
    test eax, eax
    jnz ih_done
    push DWORD PTR [ebp+H_TYPE+4]
    push DWORD PTR [ebp+H_TYPE]
    call @jbv_reference_type@8
    mov ecx, [ebp+H_REFS]
    mov edx, [ebp+H_USED]
    mov [ecx+edx], al
    mov ecx, [ebp+H_SLOTS]
    mov eax, [ebp+H_BITS]
    mov [ecx+edx*4], eax
    cmp DWORD PTR [ebp+D_WIDTH], 2
    jne @F
    mov eax, [ebp+H_BITS+4]
    mov [ecx+edx*4+4], eax
@@:
    mov eax, [ebp+D_WIDTH]
    add [ebp+H_USED], eax
    inc DWORD PTR [ebp+H_I]
    jmp ih_parameter
ih_converted:
    mov eax, [ebp+H_ARGC]
    cmp eax, [ebp+H_LENGTH]
    jne ih_wrong
    and DWORD PTR [ebp+H_KIND], 127
    mov eax, [ebp+H_KIND]
    test al, 1                          ; on a receiver
    jz ih_target
    lea eax, [ebp+H_RECV]
    push eax
    mov edx, [ebp+H_SLOTS]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ih_done
    mov eax, [ebp+H_KIND]
    cmp eax, 5                          ; virtual and interface: the receiver's method
    je @F
    cmp eax, 9
    jne ih_target
@@:
    mov eax, [ebp+H_RECV]
    mov eax, [eax]
    mov [ebp+H_TYPE], eax
    push DWORD PTR [ebp+H_METHOD]
    mov edx, [ebp+H_OWNER]
    lea ecx, [ebp+H_TYPE]
    call @jbv_virtual_method@12
    mov [ebp+H_METHOD], eax
    mov eax, [ebp+H_TYPE]
    mov [ebp+H_OWNER], eax
ih_target:
    mov esi, [ebp+H_FIELD]
    test esi, esi
    jz ih_method
    mov ecx, [esi+FIELD_DESCRIPTOR+TEXT_DATA]
    movzx ecx, BYTE PTR [ecx]
    call @jbv_kind@4
    movzx edi, al                       ; the field's kind
    test WORD PTR [esi+FIELD_FLAGS], ACC_STATIC
    jz @F
    mov edx, [ebp+H_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz ih_done
    lea edx, [esi+FIELD_VALUE]
    jmp ih_location
@@:
    lea eax, [ebp+H_RECV]
    push eax
    mov edx, [ebp+H_SLOTS]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ih_done
    mov eax, [esi+FIELD_SLOT]
    mov edx, [ebp+H_RECV]
    lea edx, [edx+eax*4+DATA0]
ih_location:                            ; edx = the field's slots
    mov eax, [ebp+H_KIND]
    cmp eax, 2
    ja ih_put
    mov eax, [edx]                      ; getters
    mov [ebp+H_BITS], eax
    xor eax, eax
    cmp edi, K_LONG
    je @F
    cmp edi, K_DOUBLE
    jne ih_got
@@:
    mov eax, [edx+4]
ih_got:
    mov [ebp+H_BITS+4], eax
    jmp ih_result
ih_put:                                 ; setters: the value after the receiver (instance)
    mov ecx, [ebp+H_SLOTS]
    cmp eax, 3
    jne @F
    add ecx, 4
@@:
    mov eax, [ecx]
    mov [edx], eax
    cmp edi, K_LONG
    je @F
    cmp edi, K_DOUBLE
    jne ih_stored
@@:
    mov eax, [ecx+4]
    mov [edx+4], eax
ih_stored:
    mov ecx, [ebp+H_RECV]
    test ecx, ecx
    jz ih_result
    push DWORD PTR [edx]
    mov edx, ecx
    mov ecx, ebx
    call @jbv_barrier_checked@12
    jmp ih_result
ih_method:
    mov esi, [ebp+H_METHOD]
    test esi, esi
    jz @F
    test WORD PTR [esi+M_FLAGS], ACC_ABSTRACT
    jz ih_call
@@:
    mov edx, OFFSET e_ame
    mov eax, S_LINKAGE
    call throw
    jmp ih_done
ih_call:
    test WORD PTR [esi+M_FLAGS], ACC_STATIC
    jz @F
    mov edx, [ebp+H_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz ih_done
@@:
    lea eax, [ebp+H_BITS]
    push eax
    push DWORD PTR [ebp+H_USED]
    push DWORD PTR [ebp+H_REFS]
    push DWORD PTR [ebp+H_SLOTS]
    push esi
    mov edx, [ebp+H_OWNER]
    mov ecx, ebx
    call @jbv_execute@28
    test eax, eax
    jnz ih_done
    cmp DWORD PTR [ebp+H_KIND], 8       ; a constructor's result is the new instance
    jne ih_result
    mov eax, [ebp+H_RECEIVED]
    mov [ebp+H_BITS], eax
    mov DWORD PTR [ebp+H_BITS+4], 0
ih_result:                              ; void: 0, references as they are, primitives boxed
    push DWORD PTR [ebp+H_D+4]
    push DWORD PTR [ebp+H_D]
    call @jbv_return_type@8
    mov ecx, [ebp+V_OUT]
    mov DWORD PTR [ecx], 0
    cmp BYTE PTR [eax], 'V'
    je ih_ok
    push eax
    push edx
    push eax
    call @jbv_reference_type@8
    pop edx                             ; the return type's chars
    test eax, eax
    jz @F
    mov ecx, [ebp+V_OUT]
    mov eax, [ebp+H_BITS]
    mov [ecx], eax
    jmp ih_ok
@@:
    push DWORD PTR [ebp+V_OUT]
    push DWORD PTR [ebp+H_BITS+4]
    push DWORD PTR [ebp+H_BITS]
    movzx edx, BYTE PTR [edx]
    mov ecx, ebx
    call @jbv_box@20
    jmp ih_done
ih_ok:
    xor eax, eax
    jmp ih_done
ih_wrong:
    mov edx, OFFSET e_wmte
    mov eax, S_EXCEPTION
    call throw
    jmp ih_done
ih_oom:
    mov eax, S_OOM
ih_done:
    mov [ebp+H_STATUS], eax
    mov ecx, [ebp+H_VARARGS]
    call release
    mov ecx, [ebp+H_RECEIVED]
    call release
    mov edx, [ebp+H_D]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+H_SLOTS]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+H_REFS]
    mov ecx, ebx
    call @jbv_free@8
    mov eax, [ebp+H_STATUS]
ih_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret 16

; JbvStatus jbv_polymorphic(vm, handle, d, args, exact, out): MethodHandle.invokeExact/invoke
; from bytecode, the arguments boxed into an Object[]
P_D      EQU 8        ; JbvText
P_ARGS   EQU 16
P_EXACT  EQU 20
P_OUT    EQU 24
P_HANDLE EQU -4
P_TARGET EQU -12      ; JbvText
P_ARRAY  EQU -16
P_COUNT  EQU -20
P_USED   EQU -24
P_VALUE  EQU -28
P_OBJECT EQU -32
P_CODE   EQU -36
P_REF    EQU -40
P_ATYPE  EQU -44
@jbv_polymorphic@28 PROC SYSCALL    ; ecx vm, edx handle, [ebp+8] d, args, exact, out
    push ebp
    mov ebp, esp
    sub esp, 56
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov [ebp+P_REF], edx
    xor eax, eax
    mov [ebp+P_ARRAY], eax
    mov [ebp+P_COUNT], eax
    mov [ebp+P_USED], eax
    push 16
    push OFFSET n_object
    mov ecx, ebx
    call @jbv_find_class@12
    mov [ebp+P_OBJECT], eax
    lea eax, [ebp+P_HANDLE]
    push eax
    mov edx, [ebp+P_REF]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz pm_ret
    cmp DWORD PTR [ebp+P_EXACT], 0      ; invokeExact: the descriptors must match
    je pm_count
    mov eax, [ebp+P_HANDLE]
    lea edx, [ebp+P_TARGET]
    call handle_descriptor
    test eax, eax
    jnz pm_ret
    push DWORD PTR [ebp+P_TARGET+4]
    push DWORD PTR [ebp+P_TARGET]
    push DWORD PTR [ebp+P_D+4]
    push DWORD PTR [ebp+P_D]
    call @jbv_text_eq@16
    mov esi, eax
    mov edx, [ebp+P_TARGET]
    mov ecx, ebx
    call @jbv_free@8
    test esi, esi
    jnz pm_count
    mov edx, OFFSET e_wmte
    mov eax, S_EXCEPTION
    call throw
    jmp pm_ret
pm_count:
    mov DWORD PTR [ebp+D_POS], 1
@@:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+P_D]
    cmp BYTE PTR [ecx+eax], ')'
    je @F
    lea eax, [ebp+P_D]
    call dtype
    inc DWORD PTR [ebp+P_COUNT]
    jmp @B
@@:
    lea eax, [ebp+P_ATYPE]
    push eax
    push 'L'
    mov edx, [ebp+P_OBJECT]
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz pm_ret
    lea eax, [ebp+P_ARRAY]
    push eax
    push DWORD PTR [ebp+P_COUNT]
    mov edx, [ebp+P_ATYPE]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz pm_ret
    push DWORD PTR [ebp+P_ARRAY]
    push ebx
    call jbv_retain
    add esp, 8
    mov DWORD PTR [ebp+D_POS], 1
    xor edi, edi                        ; index
pm_box:
    cmp edi, [ebp+P_COUNT]
    jae pm_call
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+P_D]
    movzx eax, BYTE PTR [ecx+eax]
    mov [ebp+P_CODE], eax
    lea eax, [ebp+P_D]
    call dtype
    mov esi, [ebp+P_USED]
    shl esi, 2
    add esi, [ebp+P_ARGS]
    mov eax, [ebp+P_CODE]
    cmp al, 'L'
    je pm_reference
    cmp al, '['
    je pm_reference
    lea eax, [ebp+P_VALUE]
    push eax
    xor edx, edx
    cmp DWORD PTR [ebp+D_WIDTH], 2
    jne @F
    mov edx, [esi+4]
@@:
    push edx
    push DWORD PTR [esi]
    movzx edx, BYTE PTR [ebp+P_CODE]
    mov ecx, ebx
    call @jbv_box@20
    test eax, eax
    jnz pm_done
    jmp pm_store
pm_reference:
    mov eax, [esi]
    mov [ebp+P_VALUE], eax
pm_store:                               ; boxing may have moved the array
    push 0
    push esp
    mov edx, [ebp+P_ARRAY]
    mov ecx, ebx
    call @jbv_object@12
    pop edx
    mov eax, [ebp+P_VALUE]
    mov [edx+edi*4+DATA0], eax
    push eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    mov eax, [ebp+D_WIDTH]
    add [ebp+P_USED], eax
    inc edi
    jmp pm_box
pm_call:
    xor eax, eax                        ; invoke (not exact) collects varargs
    cmp DWORD PTR [ebp+P_EXACT], 0
    sete al
    push eax
    lea eax, [ebp+P_VALUE]
    push eax
    push DWORD PTR [ebp+P_ARRAY]
    push DWORD PTR [ebp+P_REF]
    call invoke_handle
    test eax, eax
    jnz pm_done
    push DWORD PTR [ebp+P_D+4]
    push DWORD PTR [ebp+P_D]
    call @jbv_return_type@8
    mov ecx, [ebp+P_OUT]
    cmp BYTE PTR [eax], 'V'
    jne @F
    xor eax, eax
    mov [ecx], eax
    mov [ecx+4], eax
    jmp pm_done
@@:
    push edx                            ; the result is held only here: converting may collect
    push eax
    push DWORD PTR [ebp+P_VALUE]
    push ebx
    call jbv_retain
    add esp, 8
    pop eax
    pop edx
    push DWORD PTR [ebp+P_OUT]
    push edx
    push eax
    mov edx, [ebp+P_VALUE]
    mov ecx, ebx
    call @jbv_from_object@20
    push eax
    mov ecx, [ebp+P_VALUE]
    call release
    pop eax
pm_done:
    push eax
    mov ecx, [ebp+P_ARRAY]
    call release
    pop eax
pm_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 20
@jbv_polymorphic@28 ENDP

; JbvStatus jbv_constant(vm, owner, index, out, kind): a loadable constant (ldc); MethodType
; and MethodHandle are made once and kept in the entry
@jbv_constant@20 PROC SYSCALL       ; ecx vm, edx owner, [esp+4] index, out, kind
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    movzx eax, WORD PTR [esp+16]
    imul esi, eax, CP_SIZEOF
    add esi, [edi+C_POOL]
    mov ecx, [esp+24]
    mov BYTE PTR [ecx], K_REF
    mov ecx, [esp+20]
    mov al, [esi+CP_TAG]
    cmp al, 3
    jb ct_cached
    cmp al, 6
    ja ct_literal
    mov edx, [esi+CP_BITS]              ; numbers
    mov [ecx], edx
    mov edx, [esi+CP_BITS_HI]
    mov [ecx+4], edx
    sub al, 3
    movzx eax, al
    mov al, [ct_kinds+eax]
    mov ecx, [esp+24]
    mov [ecx], al
    xor eax, eax
    jmp ct_ret
ct_literal:
    cmp al, 8
    ja ct_cached
    mov DWORD PTR [ecx+4], 0            ; String and Class
    push ecx
    movzx eax, WORD PTR [esp+20]
    push eax
    mov edx, edi
    mov ecx, ebx
    call @jbv_literal@16
    jmp ct_ret
ct_cached:
    mov DWORD PTR [ecx+4], 0
    mov eax, [esi+CP_BITS]
    test eax, eax
    jz @F
    mov [ecx], eax
    xor eax, eax
    jmp ct_ret
@@:
    push 0                              ; the ref made
    cmp BYTE PTR [esi+CP_TAG], 16
    jne ct_handle
    movzx eax, WORD PTR [esi+CP_A]
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    add eax, CP_TEXT
    mov edx, esp
    call method_type
    jmp ct_made
ct_handle:
    mov eax, S_UNSUPPORTED
    cmp BYTE PTR [esi+CP_TAG], 15
    jne ct_made
    movzx eax, WORD PTR [esi+CP_B]      ; the member ref
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    push eax
    push 0                              ; its class
    push esp
    movzx ecx, WORD PTR [eax+CP_A]
    push ecx
    mov edx, edi
    mov ecx, ebx
    call @jbv_class_constant@16
    pop ecx                             ; the class
    pop edx                             ; the member ref
    test eax, eax
    jnz ct_made
    mov eax, esp
    push eax                            ; out: the ref slot
    movzx eax, WORD PTR [esi+CP_A]      ; the reference kind
    push eax
    movzx eax, WORD PTR [edx+CP_B]      ; the name and type
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    movzx edx, WORD PTR [eax+CP_B]
    imul edx, edx, CP_SIZEOF
    add edx, [edi+C_POOL]
    push DWORD PTR [edx+CP_TEXT+4]      ; descriptor
    push DWORD PTR [edx+CP_TEXT]
    movzx edx, WORD PTR [eax+CP_A]
    imul edx, edx, CP_SIZEOF
    add edx, [edi+C_POOL]
    push DWORD PTR [edx+CP_TEXT+4]      ; name
    push DWORD PTR [edx+CP_TEXT]
    push ecx                            ; symbolic
    push edi                            ; caller
    call make_handle
ct_made:
    pop ecx
    test eax, eax
    jnz ct_ret
    mov [esi+CP_BITS], ecx
    mov edx, [esp+20]
    mov [edx], ecx
ct_ret:
    pop edi
    pop esi
    pop ebx
    ret 12
@jbv_constant@20 ENDP

; JbvStatus jbv_dynamic_native(vm, op, a, out): the java.lang.invoke runtime natives of
; jbv/runtime/Support (callerClass, methodTypeClass, findHandle, invokeHandle, staticFinal,
; wrapperClass, explicitCast, enumValue, captureStackTrace)
N_NAME   EQU -8       ; JbvText (freed)
N_DESC   EQU -16      ; JbvText (freed)
N_TYPE   EQU -20
N_CALLER EQU -24
N_REF    EQU -28
N_ARGS   EQU -32
N_RESULT EQU -36
N_BITS   EQU -44      ; uint64_t
N_DECL   EQU -48
N_FIELD  EQU -60
N_TEXT   EQU -68      ; JbvText
@jbv_dynamic_native@16 PROC SYSCALL ; ecx vm, edx op, [ebp+8] a, [ebp+12] out
    push ebp
    mov ebp, esp
    sub esp, 68
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, [ebp+8]
    mov edi, edx
    xor eax, eax
    mov [ebp+N_NAME], eax
    mov [ebp+N_DESC], eax
    mov [ebp+N_REF], eax
    mov eax, S_UNSUPPORTED
    cmp edi, 8
    ja dn_done
    jmp DWORD PTR [dn_ops+edi*4]

dn_caller:                              ; the class of a calling frame, a[0] frames up
    mov eax, [ebx+VM_FRAMES]
    mov eax, [eax+FR_PREVIOUS]
    mov ecx, [esi]
@@:
    test eax, eax
    jz dn_bad
    test ecx, ecx
    jle @F
    mov eax, [eax+FR_PREVIOUS]
    dec ecx
    jmp @B
@@:
    lea ecx, [ebp+N_REF]
    push ecx
    mov edx, [eax+FR_OWNER]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp dn_done

dn_type:                                ; a class of a method descriptor: return (-1), parameter a[1],
    lea eax, [ebp+N_DESC]               ; or all of them resolved (-2)
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz dn_done
    push DWORD PTR [ebp+N_DESC+4]
    push DWORD PTR [ebp+N_DESC]
    lea ecx, [ebp+N_ARGS]
    lea edx, [ebp+N_RESULT]
    call @jbv_signature@16
    test eax, eax
    jnz dn_bad
    mov DWORD PTR [ebp+D_POS], 1
    mov eax, [esi+4]
    cmp eax, -2
    jne dn_one
@@:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+N_DESC]
    cmp BYTE PTR [ecx+eax], ')'
    je @F
    call dn_part
    call dn_class
    test eax, eax
    jnz dn_done
    jmp @B
@@:
    call dn_return
    call dn_class
    jmp dn_done
dn_one:
    cmp eax, -1
    jne @F
    call dn_return
    jmp dn_mirror
@@:
    test eax, eax
    js dn_bounds
    mov edi, eax                        ; skip a[1] parameters
@@:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+N_DESC]
    cmp BYTE PTR [ecx+eax], ')'
    je dn_bounds
    test edi, edi
    jz @F
    lea eax, [ebp+N_DESC]
    call dtype
    dec edi
    jmp @B
@@:
    call dn_part
dn_mirror:
    call dn_class
    test eax, eax
    jnz dn_done
    lea eax, [ebp+N_REF]
    push eax
    mov edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp dn_done
; the next parameter type of N_DESC into N_TEXT
dn_part:
    mov eax, [ebp+D_POS]
    push eax
    lea eax, [ebp+N_DESC]
    call dtype
    pop eax
    mov ecx, [ebp+D_POS]
    sub ecx, eax
    mov [ebp+N_TEXT+4], ecx
    add eax, [ebp+N_DESC]
    mov [ebp+N_TEXT], eax
    ret
dn_return:
    push DWORD PTR [ebp+N_DESC+4]
    push DWORD PTR [ebp+N_DESC]
    call @jbv_return_type@8
    mov [ebp+N_TEXT], eax
    mov [ebp+N_TEXT+4], edx
    ret
; N_TEXT -> eax status, N_TYPE its class
dn_class:
    push DWORD PTR [ebp+N_TEXT+4]
    push DWORD PTR [ebp+N_TEXT]
    lea edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    ret

dn_find:                                ; a direct handle: Lookup.findXxx(caller, class, name, type, kind)
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+N_CALLER], eax
    mov edx, [esi+4]
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+N_TYPE], eax
    test eax, eax
    jz dn_null
    lea eax, [ebp+N_NAME]
    push eax
    mov edx, [esi+8]
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz dn_done
    lea eax, [ebp+N_DESC]
    push eax
    mov edx, [esi+12]
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz dn_done
    lea eax, [ebp+N_REF]
    push eax
    push DWORD PTR [esi+16]
    push DWORD PTR [ebp+N_DESC+4]
    push DWORD PTR [ebp+N_DESC]
    push DWORD PTR [ebp+N_NAME+4]
    push DWORD PTR [ebp+N_NAME]
    push DWORD PTR [ebp+N_TYPE]
    push DWORD PTR [ebp+N_CALLER]
    call make_handle
    cmp eax, S_NOT_FOUND                ; as the reflective exceptions
    jne @F
    mov edx, OFFSET e_nsmx
    cmp DWORD PTR [esi+16], 4
    jg dn_throw
    mov edx, OFFSET e_nsfx
    jmp dn_throw
@@:
    cmp eax, S_LINKAGE
    jne dn_done
    mov edx, OFFSET e_iae
dn_throw:
    mov eax, S_EXCEPTION
    call throw
    jmp dn_done

dn_invoke:                              ; MethodHandle.invokeWithArguments
    push 1
    lea eax, [ebp+N_REF]
    push eax
    push DWORD PTR [esi+4]
    push DWORD PTR [esi]
    call invoke_handle
    jmp dn_done

dn_static:                              ; a static final field: staticFinal(caller, class, name, type), enumValue(class, name)
    xor eax, eax
    cmp edi, 4
    jne @F
    mov eax, 4
@@:
    mov edx, [esi+eax]
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+N_TYPE], eax
    test eax, eax
    jz dn_null
    xor eax, eax
    cmp edi, 4
    jne @F
    mov eax, 4
@@:
    mov edx, [esi+eax+4]
    lea eax, [ebp+N_NAME]
    push eax
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz dn_done
    mov eax, [ebp+N_TYPE]               ; up the superclasses
dn_declaring:
    mov [ebp+N_DECL], eax
    test eax, eax
    jz dn_no_field
    movzx ecx, WORD PTR [eax+C_FIELD_COUNT]
    mov edx, [eax+C_FIELDS]
dn_field:
    test ecx, ecx
    jz dn_super
    push ecx
    push edx
    push DWORD PTR [ebp+N_NAME+4]
    push DWORD PTR [ebp+N_NAME]
    push DWORD PTR [edx+FIELD_NAME+TEXT_SIZE]
    push DWORD PTR [edx+FIELD_NAME+TEXT_DATA]
    call @jbv_text_eq@16
    pop edx
    pop ecx
    test eax, eax
    jnz dn_found
    add edx, FIELD_SIZEOF
    dec ecx
    jmp dn_field
dn_super:
    mov eax, [ebp+N_DECL]
    mov eax, [eax+C_SUPER]
    jmp dn_declaring
dn_found:
    mov [ebp+N_FIELD], edx
    movzx eax, WORD PTR [edx+FIELD_FLAGS]
    and eax, ACC_STATIC or ACC_FINAL
    cmp eax, ACC_STATIC or ACC_FINAL
    jne dn_no_field
    cmp edi, 7
    jne @F
    mov eax, S_BAD_ARG                  ; enumValue: an enum constant
    test WORD PTR [edx+FIELD_FLAGS], 4000h
    jz dn_done
    jmp dn_initialize
@@:
    mov edx, [esi+12]                   ; staticFinal: of the expected type
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+N_CALLER], eax
    mov edx, [ebp+N_FIELD]
    push DWORD PTR [edx+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edx+FIELD_DESCRIPTOR+TEXT_DATA]
    lea edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz dn_done
    mov eax, [ebp+N_TYPE]
    cmp eax, [ebp+N_CALLER]
    je dn_initialize
    mov edx, OFFSET e_nsfe
    jmp dn_throw
dn_no_field:
    mov edx, OFFSET e_nsfe
    cmp edi, 7
    jne dn_throw
    mov edx, OFFSET e_iarg
    jmp dn_throw
dn_initialize:
    mov edx, [ebp+N_DECL]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz dn_done
    mov esi, [ebp+N_FIELD]
    push DWORD PTR [esi+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [esi+FIELD_DESCRIPTOR+TEXT_DATA]
    call @jbv_reference_type@8
    test eax, eax
    jz @F
    mov eax, [esi+FIELD_VALUE]
    mov [ebp+N_REF], eax
    xor eax, eax
    jmp dn_done
@@:
    mov eax, [esi+FIELD_DESCRIPTOR+TEXT_DATA]
    movzx ecx, BYTE PTR [eax]
    push ecx
    call @jbv_kind@4
    pop edx                             ; the code
    xor ecx, ecx
    cmp al, K_LONG
    je @F
    cmp al, K_DOUBLE
    jne dn_box_field
@@:
    mov ecx, [esi+FIELD_VALUE+4]
dn_box_field:
    lea eax, [ebp+N_REF]
    push eax
    push ecx
    push DWORD PTR [esi+FIELD_VALUE]
    mov ecx, ebx
    call @jbv_box@20
    jmp dn_done

dn_wrapper:                             ; the wrapper class of a primitive class
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_mirror_type@8
    test eax, eax
    jz dn_null
    mov al, [eax+C_PRIMITIVE]
    test al, al
    jz dn_bad
    push edi
    mov edi, OFFSET codes
    mov ecx, 9
    repne scasb
    mov eax, edi
    pop edi
    jne dn_bad
    sub eax, OFFSET codes+1
    mov ecx, OFFSET wrappers
@@:
    movzx edx, BYTE PTR [ecx]
    test eax, eax
    jz @F
    lea ecx, [ecx+edx+1]
    dec eax
    jmp @B
@@:
    push edx
    inc ecx
    push ecx
    lea edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz dn_done
    lea eax, [ebp+N_REF]
    push eax
    mov edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp dn_done

dn_cast:                                ; Class.cast for handles: primitives converted explicitly
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+N_TYPE], eax
    test eax, eax
    jz dn_null
    movzx ecx, BYTE PTR [eax+C_PRIMITIVE]
    test ecx, ecx
    jz dn_cast_reference
    cmp cl, 'V'
    je dn_bad
    mov edi, ecx
    lea eax, [ebp+N_BITS]
    push eax
    push 1
    push ecx
    mov edx, [esi+4]
    mov ecx, ebx
    call @jbv_unbox@20
    test eax, eax
    jnz dn_done
    lea eax, [ebp+N_REF]
    push eax
    push DWORD PTR [ebp+N_BITS+4]
    push DWORD PTR [ebp+N_BITS]
    mov edx, edi
    mov ecx, ebx
    call @jbv_box@20
    jmp dn_done
dn_cast_reference:
    xor eax, eax
    mov edx, [esi+4]
    mov [ebp+N_REF], edx
    test edx, edx
    jz dn_done
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz dn_done
    mov ecx, [ecx]
    mov edx, [ebp+N_TYPE]
    call @jbv_assignable@8
    test eax, eax
    mov eax, 0
    jnz dn_done
    mov eax, S_CAST
    jmp dn_done

dn_trace:
    lea edx, [ebp+N_REF]
    mov ecx, ebx
    call @jbv_capture_trace@8
    jmp dn_done
dn_bounds:
    mov eax, S_BOUNDS
    jmp dn_done
dn_null:
    mov eax, S_NULL
    jmp dn_done
dn_bad:
    mov eax, S_BAD_ARG
dn_done:
    push eax
    mov edx, [ebp+N_NAME]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+N_DESC]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
    test eax, eax
    jnz @F
    mov ecx, [ebp+12]
    mov edx, [ebp+N_REF]
    mov [ecx], edx
    mov DWORD PTR [ecx+4], 0
@@:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_dynamic_native@16 ENDP
.const
ALIGN 4
dn_ops DD dn_caller, dn_type, dn_find, dn_invoke, dn_static, dn_wrapper, dn_cast, dn_static, dn_trace
.code
END

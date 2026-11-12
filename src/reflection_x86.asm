; java.lang.reflect for x86 (reflection.c is the reference and serves x64): Class queries,
; member lists and lookup, Field/Method/Constructor objects {target, owner mirror, kind},
; invocation, field access and java.lang.reflect.Array. No access checks: every member is
; accessible; receivers and arguments are checked.
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
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_mirror@12:PROC
EXTERN SYSCALL @jbv_mirror_type@8:PROC
EXTERN SYSCALL @jbv_text_is@12:PROC
EXTERN SYSCALL @jbv_text_eq@16:PROC
EXTERN SYSCALL @jbv_text_bytes@12:PROC
EXTERN SYSCALL @jbv_string_mutf@16:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_type_class@16:PROC
EXTERN SYSCALL @jbv_return_type@8:PROC
EXTERN SYSCALL @jbv_descriptor_type@16:PROC
EXTERN SYSCALL @jbv_reference_type@8:PROC
EXTERN SYSCALL @jbv_kind@4:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_unbox@20:PROC
EXTERN SYSCALL @jbv_box@20:PROC
EXTERN SYSCALL @jbv_from_object@20:PROC
EXTERN SYSCALL @jbv_annotations@16:PROC
EXTERN SYSCALL @jbv_annotation_value@24:PROC
EXTERN SYSCALL @jbv_skip_annotations@4:PROC
EXTERN SYSCALL @jbv_virtual_method@12:PROC
EXTERN SYSCALL @jbv_multi_array@20:PROC
EXTERN SYSCALL @jbv_array_get@12:PROC
EXTERN SYSCALL @jbv_array_set@20:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC

S_BAD_ARG   EQU 1
S_OOM       EQU 2
S_BAD_CLASS EQU 3
S_NOT_FOUND EQU 7
S_LINKAGE   EQU 8
S_LIMIT     EQU 10
S_NULL      EQU 12
S_BOUNDS    EQU 13
S_NEGATIVE  EQU 14
S_CAST      EQU 16
S_EXCEPTION EQU 22
ACC_PUBLIC  EQU 1
ACC_STATIC  EQU 8
ACC_FINAL   EQU 10h
ACC_INTERFACE EQU 200h
ACC_ABSTRACT EQU 400h
DATA0       EQU 4
D_POS       EQU -52   ; the descriptor cursor of the frames using dtype
D_WIDTH     EQU -56
; Member {owner, target, kind}
MB_OWNER    EQU 0
MB_TARGET   EQU 4
MB_KIND     EQU 8
MB_SIZE     EQU 12
; Members {data, size, capacity}
ML_DATA     EQU 0
ML_SIZE     EQU 4
ML_CAP      EQU 8

.const
n_field     DB 23, 'java/lang/reflect/Field'
n_method    DB 24, 'java/lang/reflect/Method'
n_ctor      DB 29, 'java/lang/reflect/Constructor'
n_class     DB 15, 'java/lang/Class'
n_string    DB 16, 'java/lang/String'
n_cloneable DB 19, 'java/lang/Cloneable'
n_serial    DB 20, 'java/io/Serializable'
n_annots    DB 34, '[Ljava/lang/annotation/Annotation;'
n_generics  DB 20, 'jbv/runtime/Generics'
s_of_class  DB 'ofClass'
s_of_desc   DB '(Ljava/lang/Class;I)Ljava/lang/Object;'
s_enum      DB 'java/lang/Enum', 0
s_clinit    DB '<clinit>', 0
s_init      DB '<init>', 0
k_signature DB 'Signature', 0
k_inner     DB 'InnerClasses', 0
k_annots    DB 'RuntimeVisibleAnnotations', 0
k_param_annots DB 'RuntimeVisibleParameterAnnotations', 0
k_default   DB 'AnnotationDefault', 0
k_params    DB 'MethodParameters', 0
k_exceptions DB 'Exceptions', 0
k_record    DB 'Record', 0
e_cnfe      DB 'java/lang/ClassNotFoundException', 0
e_nsfx      DB 'java/lang/NoSuchFieldException', 0
e_nsmx      DB 'java/lang/NoSuchMethodException', 0
e_iae       DB 'java/lang/IllegalAccessException', 0
e_ie        DB 'java/lang/InstantiationException', 0
e_ame       DB 'java/lang/AbstractMethodError', 0
e_ite       DB 'java/lang/reflect/InvocationTargetException', 0
ALIGN 4
member_names DD n_field, n_method, n_ctor

.code
; ---- small helpers (ebx = vm)
; eax = &JbvText: one type at [ebp+D_POS], its width to [ebp+D_WIDTH] -> eax = ok
dtype:
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    lea ecx, [ebp+D_POS]
    lea edx, [ebp+D_WIDTH]
    call @jbv_descriptor_type@16
    ret
; edx = an error name -> eax = EXCEPTION (thrown)
error:
    push S_EXCEPTION
    push 0
    mov ecx, ebx
    call @jbv_throw_named@16
    ret
; ecx = ref: released
release:
    push ecx
    push ebx
    call jbv_release
    add esp, 8
    ret
; ecx = ref: retained
retain:
    push ecx
    push ebx
    call jbv_retain
    add esp, 8
    ret
; eax = a counted name, edx = &out -> eax status
resolve_counted:
    movzx ecx, BYTE PTR [eax]
    push ecx
    inc eax
    push eax
    mov ecx, ebx
    call @jbv_resolve_class@16
    ret
; eax = a counted component class name, ecx = the length, edx = &ref -> eax status: a new array
array:
    push edx
    push ecx
    push 0
    mov edx, esp
    call resolve_counted
    pop edx                             ; the component
    test eax, eax
    jnz ar_drop
    push 0
    push esp
    push 'L'
    mov ecx, ebx
    call @jbv_array_class@16
    pop edx                             ; the array class
    pop ecx                             ; the length
    test eax, eax
    jnz ar_drop1
    push ecx
    mov ecx, ebx
    call @jbv_new@16
    ret
ar_drop:
    pop ecx
ar_drop1:
    pop ecx
    ret
; eax = an array ref, ecx = the index, edx = the reference stored (producers allocate:
; the array is fetched again)
store:
    push edx
    push ecx
    push 0
    push esp
    mov edx, eax
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    pop ecx
    pop edx
    mov [eax+ecx*4+DATA0], edx
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    ret
; edx = &Member -> eax = &its name / descriptor JbvText; its attributes; its flags
member_name:
    mov eax, [edx+MB_TARGET]
    cmp BYTE PTR [edx+MB_KIND], 0
    je @F
    add eax, M_NAME
    ret
@@:
    add eax, FIELD_NAME
    ret
member_descriptor:
    mov eax, [edx+MB_TARGET]
    cmp BYTE PTR [edx+MB_KIND], 0
    je @F
    add eax, M_DESCRIPTOR
    ret
@@:
    add eax, FIELD_DESCRIPTOR
    ret
member_attributes:
    mov eax, [edx+MB_TARGET]
    cmp BYTE PTR [edx+MB_KIND], 0
    je @F
    mov eax, [eax+M_ATTRIBUTES]
    ret
@@:
    mov eax, [eax+FIELD_ATTRIBUTES]
    ret
member_flags:
    mov eax, [edx+MB_TARGET]
    cmp BYTE PTR [edx+MB_KIND], 0
    je @F
    movzx eax, WORD PTR [eax+M_FLAGS]
    and eax, 1DFFh
    ret
@@:
    movzx eax, WORD PTR [eax+FIELD_FLAGS]
    ret
; eax = &JbvText, ecx = a C string -> eax = equal
text_is:
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    call @jbv_text_is@12
    ret
; eax = &JbvText a, edx = &JbvText b -> eax = equal
text_eq:
    push DWORD PTR [edx+TEXT_SIZE]
    push DWORD PTR [edx+TEXT_DATA]
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    call @jbv_text_eq@16
    ret

; const uint8_t *jbv_attribute(owner, p, key): an attribute's body by name, or 0
@jbv_attribute@12 PROC SYSCALL      ; ecx owner, edx p, [esp+4] key
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    xor eax, eax
    test esi, esi
    jz at_ret
    movzx edi, WORD PTR [esi]
    xchg edi, eax
    xchg al, ah
    xchg edi, eax
    add esi, 2
at_next:
    xor eax, eax
    test edi, edi
    jz at_ret
    dec edi
    movzx eax, WORD PTR [esi]
    xchg al, ah
    imul eax, eax, CP_SIZEOF
    add eax, [ebx+C_POOL]
    add eax, CP_TEXT
    mov ecx, [esp+16]
    call text_is
    test eax, eax
    jnz at_found
    mov eax, [esi+2]
    bswap eax
    lea esi, [esi+eax+6]
    jmp at_next
at_found:
    lea eax, [esi+6]
at_ret:
    pop edi
    pop esi
    pop ebx
    ret 4
@jbv_attribute@12 ENDP

; eax = a member object ref, edx = &Member, ecx = &object -> eax status
unpack:
    push esi
    push edi
    mov esi, edx
    mov edi, ecx
    push edi
    mov edx, eax
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz up_ret
    mov eax, [edi]
    mov edx, [eax+DATA0+8]
    push eax
    mov ecx, ebx
    call @jbv_mirror_type@8
    pop edx
    mov [esi+MB_OWNER], eax
    mov ecx, [edx+DATA0]
    mov [esi+MB_TARGET], ecx
    mov cl, [edx+DATA0+16]
    mov [esi+MB_KIND], cl
    test eax, eax
    jz up_bad
    xor eax, eax
    cmp DWORD PTR [esi+MB_TARGET], 0
    jne up_ret
up_bad:
    mov eax, S_BAD_ARG
up_ret:
    pop edi
    pop esi
    ret
; edx = &Member, ecx = &out -> eax status: its Field/Method/Constructor object
wrap:
    push esi
    push edi
    push 0                              ; the owner's mirror
    push 0                              ; the class
    mov esi, edx
    mov edi, ecx
    lea eax, [esp+4]
    push eax
    mov edx, [esi+MB_OWNER]
    mov ecx, ebx
    call @jbv_mirror@12
    test eax, eax
    jnz wr_ret
    movzx eax, BYTE PTR [esi+MB_KIND]
    mov eax, [member_names+eax*4]
    mov edx, esp
    call resolve_counted
    test eax, eax
    jnz wr_ret
    push edi
    push 0
    mov edx, [esp+8]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz wr_ret
    push 0
    push esp
    mov edx, [edi]
    mov ecx, ebx
    call @jbv_object@12
    pop edx
    mov eax, [esi+MB_TARGET]
    mov [edx+DATA0], eax
    mov DWORD PTR [edx+DATA0+4], 0
    mov eax, [esp+4]
    mov [edx+DATA0+8], eax
    movzx ecx, BYTE PTR [esi+MB_KIND]
    mov [edx+DATA0+16], ecx
    push eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    xor eax, eax
wr_ret:
    add esp, 8
    pop edi
    pop esi
    ret
; esi = &Members, edx = &Member -> eax status: added unless present; a method of the same
; signature is replaced by the more specific one (class over interface, subclass over super)
add_member:
    push edi
    push ebp
    mov ebp, edx
    xor edi, edi
am_scan:
    cmp edi, [esi+ML_SIZE]
    jae am_append
    imul edx, edi, MB_SIZE
    add edx, [esi+ML_DATA]              ; old
    mov eax, [ebp+MB_TARGET]
    cmp eax, [edx+MB_TARGET]
    je am_ok
    cmp BYTE PTR [ebp+MB_KIND], 1
    jne am_next
    push edx
    call member_name
    push eax
    mov edx, ebp
    call member_name
    pop edx
    call text_eq
    pop edx
    test eax, eax
    jz am_next
    push edx
    call member_descriptor
    push eax
    mov edx, ebp
    call member_descriptor
    pop edx
    call text_eq
    pop edx
    test eax, eax
    jz am_next
    mov eax, [edx+MB_OWNER]             ; the same method: keep the more specific
    mov ecx, [ebp+MB_OWNER]
    test WORD PTR [eax+C_FLAGS], ACC_INTERFACE
    jz @F
    test WORD PTR [ecx+C_FLAGS], ACC_INTERFACE
    jz am_replace
@@:
    test WORD PTR [ecx+C_FLAGS], ACC_INTERFACE
    jz @F
    test WORD PTR [eax+C_FLAGS], ACC_INTERFACE
    jz am_ok
@@:
    push edx
    mov edx, eax
    call @jbv_assignable@8
    pop edx
    test eax, eax
    jz am_ok
am_replace:
    mov eax, [ebp+MB_OWNER]
    mov [edx+MB_OWNER], eax
    mov eax, [ebp+MB_TARGET]
    mov [edx+MB_TARGET], eax
    mov al, [ebp+MB_KIND]
    mov [edx+MB_KIND], al
    jmp am_ok
am_next:
    inc edi
    jmp am_scan
am_append:
    mov eax, [esi+ML_SIZE]
    cmp eax, [esi+ML_CAP]
    jne am_put
    lea edx, [eax*2]                    ; grow: twice, at least 8
    test eax, eax
    jnz @F
    mov edx, 8
@@:
    push edx
    imul edx, edx, MB_SIZE
    mov ecx, ebx
    call @jbv_alloc@8
    pop edx
    test eax, eax
    jnz @F
    mov eax, S_OOM
    jmp am_ret
@@:
    mov [esi+ML_CAP], edx
    push esi
    push edi
    mov edi, eax
    mov ecx, [esi+ML_SIZE]
    imul ecx, ecx, MB_SIZE/4
    mov esi, [esi+ML_DATA]
    push esi
    rep movsd
    pop edx
    pop edi
    pop esi
    push eax
    mov ecx, ebx
    call @jbv_free@8
    pop eax
    mov [esi+ML_DATA], eax
am_put:
    mov eax, [esi+ML_SIZE]
    imul eax, eax, MB_SIZE
    add eax, [esi+ML_DATA]
    mov ecx, [ebp+MB_OWNER]
    mov [eax+MB_OWNER], ecx
    mov ecx, [ebp+MB_TARGET]
    mov [eax+MB_TARGET], ecx
    mov cl, [ebp+MB_KIND]
    mov [eax+MB_KIND], cl
    inc DWORD PTR [esi+ML_SIZE]
am_ok:
    xor eax, eax
am_ret:
    pop ebp
    pop edi
    ret
; esi = &Members; [esp+4] class, kind, inherited, root, depth -> eax status
G_CLASS EQU 8
G_KIND  EQU 12
G_INHER EQU 16
G_ROOT  EQU 20
G_DEPTH EQU 24
members:
    push ebp
    mov ebp, esp
    sub esp, 12                         ; a Member
    push edi
    mov eax, [ebp+G_DEPTH]
    cmp eax, [ebx+VM_MAX_DEPTH]
    mov eax, S_LIMIT
    ja mm_ret
    mov edi, [ebp+G_CLASS]
    cmp BYTE PTR [edi+C_ARRAY_KIND], 0  ; arrays inherit Object's methods
    je @F
    cmp DWORD PTR [ebp+G_INHER], 0
    je @F
    cmp DWORD PTR [ebp+G_KIND], 1
    jne @F
    push DWORD PTR [edi+C_SUPER]
    call mm_up
    jmp mm_ret
@@:
    xor eax, eax
    cmp BYTE PTR [edi+C_PRIMITIVE], 0
    jne mm_ret
    cmp BYTE PTR [edi+C_ARRAY_KIND], 0
    jne mm_ret
    mov [ebp-12+MB_OWNER], edi
    mov eax, [ebp+G_KIND]
    mov [ebp-12+MB_KIND], al
    push 0                              ; i
mm_member:
    mov ecx, [esp]
    cmp DWORD PTR [ebp+G_KIND], 0
    je @F
    cmp cx, [edi+C_METHOD_COUNT]
    jae mm_listed
    imul eax, ecx, M_SIZEOF
    add eax, [edi+C_METHODS]
    jmp mm_target
@@:
    cmp cx, [edi+C_FIELD_COUNT]
    jae mm_listed
    imul eax, ecx, FIELD_SIZEOF
    add eax, [edi+C_FIELDS]
mm_target:
    mov [ebp-12+MB_TARGET], eax
    cmp DWORD PTR [ebp+G_KIND], 0
    je mm_filters
    lea edx, [ebp-12]                   ; methods: no <clinit>; constructors only for kind 2
    call member_name
    mov ecx, OFFSET s_clinit
    call text_is
    test eax, eax
    jnz mm_skip
    lea edx, [ebp-12]
    call member_name
    mov ecx, OFFSET s_init
    call text_is
    cmp DWORD PTR [ebp+G_KIND], 2
    sete cl
    test eax, eax
    setnz al
    cmp al, cl
    jne mm_skip
mm_filters:
    lea edx, [ebp-12]
    call member_flags
    cmp DWORD PTR [ebp+G_INHER], 0
    je @F
    test eax, ACC_PUBLIC
    jz mm_skip
@@:
    cmp DWORD PTR [ebp+G_ROOT], 0       ; inherited interface statics are not members
    jne @F
    cmp DWORD PTR [ebp+G_KIND], 0
    je @F
    test WORD PTR [edi+C_FLAGS], ACC_INTERFACE
    jz @F
    test eax, ACC_STATIC
    jnz mm_skip
@@:
    lea edx, [ebp-12]
    call add_member
    test eax, eax
    jnz mm_fail
mm_skip:
    inc DWORD PTR [esp]
    jmp mm_member
mm_fail:
    pop ecx
    jmp mm_ret
mm_listed:
    pop ecx
    xor eax, eax
    cmp DWORD PTR [ebp+G_INHER], 0
    je mm_ret
    cmp DWORD PTR [ebp+G_KIND], 2
    je mm_ret
    push 0                              ; fields: the interfaces before the superclass
mm_face:
    mov ecx, [esp]
    cmp cx, [edi+C_INTERFACE_COUNT]
    jae mm_faces
    mov eax, [edi+C_INTERFACES]
    push DWORD PTR [eax+ecx*4]
    call mm_up
    test eax, eax
    jnz mm_fail
    inc DWORD PTR [esp]
    jmp mm_face
mm_faces:
    pop ecx
    xor eax, eax
    cmp DWORD PTR [edi+C_SUPER], 0
    je mm_ret
    test WORD PTR [edi+C_FLAGS], ACC_INTERFACE
    jnz mm_ret
    push DWORD PTR [edi+C_SUPER]
    call mm_up
mm_ret:
    pop edi
    mov esp, ebp
    pop ebp
    ret 20
; [esp+4] = a class: its inherited members, one level deeper (the argument popped)
mm_up:
    pop eax                             ; the return address
    pop ecx                             ; the class
    push eax
    mov eax, [ebp+G_DEPTH]
    inc eax
    push eax
    push 0
    push 1
    push DWORD PTR [ebp+G_KIND]
    push ecx
    call members
    ret
; eax = &descriptor JbvText, edx = the Class[] ref (or 0) -> eax status, ecx = matches
; (frame: D_POS, D_WIDTH and -60.. used)
PM_D     EQU -64      ; JbvText
PM_N     EQU -68
PM_I     EQU -72
PM_PARAMS EQU -76
PM_TYPE  EQU -80
parameters_match:
    push ebp
    mov ebp, esp
    sub esp, 80
    mov ecx, [eax]
    mov [ebp+PM_D], ecx
    mov ecx, [eax+4]
    mov [ebp+PM_D+4], ecx
    mov [ebp+PM_PARAMS], edx
    xor eax, eax
    mov [ebp+PM_N], eax
    mov [ebp+PM_I], eax
    mov DWORD PTR [ebp+D_POS], 1
    test edx, edx
    jz pm_parameter
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov eax, [eax-4]
    mov [ebp+PM_N], eax
pm_parameter:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+PM_D]
    cmp BYTE PTR [ecx+eax], ')'
    je pm_end
    mov eax, [ebp+PM_I]
    cmp eax, [ebp+PM_N]
    je pm_no
    push 0                              ; the element (type_class may move the array)
    push esp
    mov edx, [ebp+PM_PARAMS]
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov ecx, [ebp+PM_I]
    inc DWORD PTR [ebp+PM_I]
    push DWORD PTR [eax+ecx*4+DATA0]
    mov eax, [ebp+D_POS]
    push eax
    lea eax, [ebp+PM_D]
    call dtype
    pop eax
    mov ecx, [ebp+D_POS]
    sub ecx, eax
    add eax, [ebp+PM_D]
    push ecx
    push eax
    lea edx, [ebp+PM_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    pop edx                             ; the element
    test eax, eax
    jnz pm_ret
    mov ecx, ebx
    call @jbv_mirror_type@8
    cmp eax, [ebp+PM_TYPE]
    jne pm_no
    jmp pm_parameter
pm_end:
    xor ecx, ecx
    mov eax, [ebp+PM_I]
    cmp eax, [ebp+PM_N]
    sete cl
    xor eax, eax
    jmp pm_ret
pm_no:
    xor eax, eax
    xor ecx, ecx
pm_ret:
    mov esp, ebp
    pop ebp
    ret
; eax = a Class mirror ref, edx = what, ecx = out -> eax status: jbv.runtime.Generics.ofClass
generics:
    push esi
    push edi
    push ecx                            ; out
    push edx                            ; args[1]
    push eax                            ; args[0]
    push 0                              ; refs {1, 0} and the class
    push 1
    mov eax, OFFSET n_generics
    lea edx, [esp+4]
    call resolve_counted
    test eax, eax
    jnz ge_ret
    mov esi, [esp+4]
    mov edx, esi
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz ge_ret
    push 38
    push OFFSET s_of_desc
    push 7
    push OFFSET s_of_class
    mov ecx, esi
    call @jbv_find_method@20
    test eax, eax
    jnz @F
    mov eax, S_LINKAGE
    jmp ge_ret
@@:
    mov BYTE PTR [esp+4], 0             ; refs = {1, 0}
    mov ecx, [esp+16]
    push ecx                            ; out
    push 2
    lea ecx, [esp+8]
    push ecx                            ; refs
    lea ecx, [esp+20]
    push ecx                            ; args
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_execute@28
ge_ret:
    add esp, 20
    pop edi
    pop esi
    ret

; JbvStatus jbv_reflect_class(vm, op, a, out): the Class natives (op: see Class's method table)
RC_C      EQU -4
RC_REF    EQU -8
RC_TEXT   EQU -16     ; JbvText (freed)
RC_LIST   EQU -28     ; Members
RC_FOUND  EQU -32
RC_PARAMS EQU -36
RC_ITEM   EQU -40
RC_I      EQU -44
RC_KIND   EQU -48
RC_OLD    EQU -60
RC_NEXT   EQU -64
RC_OP     EQU -68
@jbv_reflect_class@16 PROC SYSCALL  ; ecx vm, edx op, [ebp+8] a, [ebp+12] out
    push ebp
    mov ebp, esp
    sub esp, 68
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov [ebp+RC_OP], edx
    mov esi, [ebp+8]
    lea edi, [ebp-68]
    push edi
    mov ecx, 64/4
    xor eax, eax
    lea edi, [ebp-64]
    rep stosd
    pop edi
    mov ecx, [ebp+12]
    mov [ecx], eax
    mov [ecx+4], eax
    cmp edx, 2
    je rc_for_name
    cmp edx, 3
    je rc_for_name
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+RC_C], eax
    test eax, eax
    jnz @F
    mov eax, S_NULL
    jmp rc_ret
@@:
    mov edi, eax                        ; the class
    mov eax, [ebp+RC_OP]
    cmp eax, 21
    je rc_signature
    cmp eax, 22
    jae rc_generics
    test eax, eax
    jz rc_modifiers
    cmp eax, 20
    je rc_annotations
    cmp eax, 19
    je rc_zero
    cmp eax, 16
    jae rc_flag
    cmp eax, 1
    je rc_interfaces
    jmp rc_members

rc_for_name:                            ; Class.forName: binary names, '/' is not one
    lea eax, [ebp+RC_TEXT]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz rc_ret
    movzx ecx, WORD PTR [ebp+RC_TEXT+4]
    mov edx, [ebp+RC_TEXT]
    jecxz rc_named
@@:
    mov al, [edx]
    cmp al, '/'
    je rc_not_found
    cmp al, '.'
    jne rc_char
    mov BYTE PTR [edx], '/'
rc_char:
    inc edx
    loop @B
rc_named:
    push DWORD PTR [ebp+RC_TEXT+4]
    push DWORD PTR [ebp+RC_TEXT]
    lea edx, [ebp+RC_C]
    mov ecx, ebx
    call @jbv_resolve_class@16
    jmp @F
rc_not_found:
    mov eax, S_NOT_FOUND
@@:
    push eax
    mov edx, [ebp+RC_TEXT]
    mov ecx, ebx
    call @jbv_free@8
    mov DWORD PTR [ebp+RC_TEXT], 0
    pop eax
    cmp eax, S_NOT_FOUND
    je rc_cnfe
    cmp eax, S_BAD_CLASS
    je rc_cnfe
    test eax, eax
    jnz rc_ret
    mov edx, [ebp+RC_C]
    cmp BYTE PTR [edx+C_PRIMITIVE], 0
    jne rc_cnfe
    cmp DWORD PTR [ebp+RC_OP], 2        ; forName(name) initializes; forName(name, init, loader) as asked
    je @F
    cmp DWORD PTR [esi+4], 0
    je rc_mirror
@@:
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz rc_ret
rc_mirror:
    lea eax, [ebp+RC_REF]
    push eax
    mov edx, [ebp+RC_C]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp rc_end
rc_cnfe:
    mov edx, OFFSET e_cnfe
    call error
    jmp rc_ret

rc_signature:                           ; the generic Signature attribute, or null
    xor eax, eax
    cmp BYTE PTR [edi+C_ARRAY_KIND], 0
    jne rc_ret
    cmp BYTE PTR [edi+C_PRIMITIVE], 0
    jne rc_ret
    push OFFSET k_signature
    mov edx, [edi+C_ATTRIBUTES]
    mov ecx, edi
    call @jbv_attribute@12
    test eax, eax
    jz rc_ret
    movzx eax, WORD PTR [eax]
    xchg al, ah
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    lea edx, [ebp+RC_REF]
    mov ecx, ebx
    call @jbv_string_mutf@16
    jmp rc_end

rc_generics:                            ; in Java: jbv.runtime.Generics.ofClass(Class, op - 22)
    mov ecx, [ebp+12]
    lea edx, [eax-22]
    mov eax, [esi]
    call generics
    test eax, eax
    jnz rc_ret
    mov ecx, [ebp+RC_OP]                ; isMemberClass/isAnonymousClass/isRecord: a Boolean
    cmp ecx, 30
    jb rc_ret
    cmp ecx, 32
    ja rc_ret
    mov ecx, [ebp+12]
    push ecx
    push 0
    push 'Z'
    mov edx, [ecx]
    mov ecx, ebx
    call @jbv_unbox@20
    jmp rc_ret

rc_modifiers:                           ; getModifiers: an inner class's own flags
    cmp BYTE PTR [edi+C_ARRAY_KIND], 0
    je @F
    mov eax, edi
rc_base:
    mov ecx, [eax+C_COMPONENT]
    test ecx, ecx
    jz rc_based
    mov eax, ecx
    jmp rc_base
rc_based:
    movzx eax, WORD PTR [eax+C_FLAGS]
    and eax, ACC_PUBLIC
    or eax, ACC_FINAL or ACC_ABSTRACT
    jmp rc_int
@@:
    movzx eax, WORD PTR [edi+C_FLAGS]
    and eax, NOT 20h
    mov [ebp+RC_ITEM], eax
    push OFFSET k_inner
    mov edx, [edi+C_ATTRIBUTES]
    mov ecx, edi
    call @jbv_attribute@12
    test eax, eax
    jz rc_inner_done
    mov esi, eax
    movzx ecx, WORD PTR [esi]
    xchg cl, ch
    add esi, 2
rc_inner:
    test ecx, ecx
    jz rc_inner_done
    push ecx
    movzx eax, WORD PTR [esi]           ; inner_class_info: its Class's name
    xchg al, ah
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    movzx eax, WORD PTR [eax+CP_A]
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    add eax, CP_TEXT
    lea edx, [edi+C_NAME]
    call text_eq
    pop ecx
    test eax, eax
    jz @F
    movzx eax, WORD PTR [esi+6]
    xchg al, ah
    mov [ebp+RC_ITEM], eax
    jmp rc_inner_done
@@:
    add esi, 8
    dec ecx
    jmp rc_inner
rc_inner_done:
    mov eax, [ebp+RC_ITEM]
rc_int:
    mov ecx, [ebp+12]
    mov [ecx], eax
rc_zero:
    xor eax, eax
    jmp rc_ret

rc_annotations:
    push OFFSET k_annots
    mov edx, [edi+C_ATTRIBUTES]
    mov ecx, edi
    call @jbv_attribute@12
    lea ecx, [ebp+RC_REF]
    push ecx
    push eax
    mov edx, edi
    mov ecx, ebx
    call @jbv_annotations@16
    jmp rc_end

rc_flag:                                ; isAnnotation, isSynthetic, isEnum
    movzx ecx, WORD PTR [edi+C_FLAGS]
    xor edx, edx
    cmp eax, 16
    jne @F
    test ecx, 2000h
    setnz dl
    jmp rc_flagged
@@:
    cmp eax, 17
    jne @F
    test ecx, 1000h
    setnz dl
    jmp rc_flagged
@@:
    test ecx, 4000h
    jz rc_flagged
    mov eax, [edi+C_SUPER]
    test eax, eax
    jz rc_flagged
    add eax, C_NAME
    mov ecx, OFFSET s_enum
    call text_is
    test eax, eax
    setnz dl
rc_flagged:
    mov eax, edx
    jmp rc_int

rc_interfaces:                          ; getInterfaces: arrays are Cloneable and Serializable
    movzx ecx, WORD PTR [edi+C_INTERFACE_COUNT]
    cmp BYTE PTR [edi+C_ARRAY_KIND], 0
    je @F
    mov ecx, 2
@@:
    mov [ebp+RC_KIND], ecx              ; the count
    mov eax, OFFSET n_class
    lea edx, [ebp+RC_REF]
    call array
    test eax, eax
    jnz rc_ret
    mov ecx, [ebp+RC_REF]
    call retain
    xor esi, esi
rc_face:
    xor eax, eax
    cmp esi, [ebp+RC_KIND]
    jae rc_faces
    cmp BYTE PTR [edi+C_ARRAY_KIND], 0
    je @F
    mov eax, OFFSET n_cloneable
    test esi, esi
    jz rc_face_named
    mov eax, OFFSET n_serial
rc_face_named:
    lea edx, [ebp+RC_OLD]
    call resolve_counted
    test eax, eax
    jnz rc_faces
    mov edx, [ebp+RC_OLD]
    jmp rc_face_mirror
@@:
    mov edx, [edi+C_INTERFACES]
    mov edx, [edx+esi*4]
rc_face_mirror:
    lea eax, [ebp+RC_ITEM]
    push eax
    mov ecx, ebx
    call @jbv_mirror@12
    test eax, eax
    jnz rc_faces
    mov eax, [ebp+RC_REF]
    mov ecx, esi
    mov edx, [ebp+RC_ITEM]
    call store
    inc esi
    jmp rc_face
rc_faces:
    push eax
    mov ecx, [ebp+RC_REF]
    call release
    pop eax
    jmp rc_end

rc_members:                             ; ops 4..15: methods, fields, constructors; all or one
    mov eax, [ebp+RC_OP]
    xor ecx, ecx                        ; kind: methods 1 (4..7), fields 0 (8..11), constructors 2
    cmp eax, 12
    jb @F
    mov ecx, 2
@@:
    cmp eax, 8
    jae @F
    mov ecx, 1
@@:
    mov [ebp+RC_KIND], ecx
    test eax, 2
    jz rc_listed
    cmp ecx, 2                          ; lookup: the name (not for constructors), the parameter types
    je @F
    lea eax, [ebp+RC_TEXT]
    push eax
    mov edx, [esi+4]
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz rc_ret
@@:
    mov ecx, [ebp+RC_KIND]
    test ecx, ecx
    jz rc_listed
    mov eax, 4
    cmp ecx, 2
    je @F
    mov eax, 8
@@:
    mov edx, [esi+eax]
    mov [ebp+RC_PARAMS], edx
    test edx, edx
    jz rc_listed
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz rc_done
rc_listed:
    push esi
    push 0                              ; depth
    push 1                              ; root
    mov eax, [ebp+RC_OP]
    and eax, 1                          ; inherited (public)
    push eax
    push DWORD PTR [ebp+RC_KIND]
    push edi
    lea esi, [ebp+RC_LIST]
    call members
    pop esi
    test eax, eax
    jnz rc_done
    test DWORD PTR [ebp+RC_OP], 2
    jz rc_all
    xor edi, edi                        ; one: by name and parameter types
rc_candidate:
    cmp edi, [ebp+RC_LIST+ML_SIZE]
    jae rc_chosen
    imul esi, edi, MB_SIZE
    add esi, [ebp+RC_LIST+ML_DATA]
    cmp DWORD PTR [ebp+RC_KIND], 2
    je @F
    mov edx, esi
    call member_name
    lea edx, [ebp+RC_TEXT]
    call text_eq
    test eax, eax
    jz rc_next
@@:
    cmp DWORD PTR [ebp+RC_KIND], 0
    je rc_take
    mov edx, esi
    call member_descriptor
    mov edx, [ebp+RC_PARAMS]
    call parameters_match
    test eax, eax
    jnz rc_done
    test ecx, ecx
    jz rc_next
    cmp DWORD PTR [ebp+RC_KIND], 1      ; methods: the most specific return type
    jne rc_take
    mov edx, [ebp+RC_FOUND]
    test edx, edx
    jz rc_take
    call member_descriptor
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    call @jbv_return_type@8
    push edx
    push eax
    lea edx, [ebp+RC_OLD]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz rc_done
    mov edx, esi
    call member_descriptor
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    call @jbv_return_type@8
    push edx
    push eax
    lea edx, [ebp+RC_NEXT]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz rc_done
    mov ecx, [ebp+RC_NEXT]
    mov edx, [ebp+RC_OLD]
    cmp ecx, edx
    je rc_next
    call @jbv_assignable@8
    test eax, eax
    jz rc_next
rc_take:
    mov [ebp+RC_FOUND], esi
    cmp DWORD PTR [ebp+RC_KIND], 0
    je rc_chosen
rc_next:
    inc edi
    jmp rc_candidate
rc_chosen:
    mov edx, [ebp+RC_FOUND]
    test edx, edx
    jz @F
    lea ecx, [ebp+RC_REF]
    call wrap
    jmp rc_done
@@:
    mov edx, OFFSET e_nsmx
    cmp DWORD PTR [ebp+RC_KIND], 0
    jne @F
    mov edx, OFFSET e_nsfx
@@:
    call error
    jmp rc_done
rc_all:
    mov eax, [ebp+RC_KIND]
    mov eax, [member_names+eax*4]
    mov ecx, [ebp+RC_LIST+ML_SIZE]
    lea edx, [ebp+RC_REF]
    call array
    test eax, eax
    jnz rc_done
    mov ecx, [ebp+RC_REF]
    call retain
    xor edi, edi
rc_wrap:
    xor eax, eax
    cmp edi, [ebp+RC_LIST+ML_SIZE]
    jae rc_wrapped
    imul edx, edi, MB_SIZE
    add edx, [ebp+RC_LIST+ML_DATA]
    lea ecx, [ebp+RC_ITEM]
    call wrap
    test eax, eax
    jnz rc_wrapped
    mov eax, [ebp+RC_REF]
    mov ecx, edi
    mov edx, [ebp+RC_ITEM]
    call store
    inc edi
    jmp rc_wrap
rc_wrapped:
    push eax
    mov ecx, [ebp+RC_REF]
    call release
    pop eax
rc_done:
    push eax
    mov edx, [ebp+RC_LIST+ML_DATA]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+RC_TEXT]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
rc_end:
    test eax, eax
    jnz rc_ret
    mov ecx, [ebp+12]
    mov edx, [ebp+RC_REF]
    mov [ecx], edx
    mov DWORD PTR [ecx+4], 0
rc_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_reflect_class@16 ENDP

; ---- members: edx = &Member (ebx = vm)
; eax = the receiver, ecx = query -> eax status: static members take none (a query: must not
; get one); instance members an instance of the owner
access:
    push esi
    mov esi, edx
    push eax
    push ecx
    call member_flags
    pop ecx
    pop edx                             ; the receiver
    cmp BYTE PTR [esi+MB_KIND], 2
    je @F
    test eax, ACC_STATIC
    jz ac_instance
@@:
    xor eax, eax
    test ecx, ecx
    jz ac_ret
    test edx, edx
    jz ac_ret
    mov eax, S_BAD_ARG
    jmp ac_ret
ac_instance:
    test edx, edx
    jnz @F
    mov eax, S_NULL
    test ecx, ecx
    jz ac_ret
    mov eax, S_BAD_ARG
    jmp ac_ret
@@:
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz ac_ret
    mov ecx, [ecx]
    mov edx, [esi+MB_OWNER]
    call @jbv_assignable@8
    test eax, eax
    mov eax, 0
    jnz ac_ret
    mov eax, S_BAD_ARG
ac_ret:
    pop esi
    ret
; eax = an Object, edx = &type JbvText, ecx = &bits -> eax status (mismatches: BAD_ARG)
convert:
    push ecx
    push DWORD PTR [edx+TEXT_SIZE]
    push DWORD PTR [edx+TEXT_DATA]
    mov edx, eax
    mov ecx, ebx
    call @jbv_from_object@20
    cmp eax, S_CAST
    je @F
    cmp eax, S_NULL
    jne cv_ret
@@:
    mov eax, S_BAD_ARG
cv_ret:
    ret
; edx = &Member, attribute key at eax -> eax = the attribute's body, or 0
member_attribute:
    push esi
    mov esi, edx
    push eax
    call member_attributes
    mov edx, eax
    mov ecx, [esi+MB_OWNER]
    call @jbv_attribute@12
    pop esi
    ret
; ecx = a cp index of owner (edx = the owner) -> eax = &its JbvText
pool_text:
    imul eax, ecx, CP_SIZEOF
    add eax, [edx+C_POOL]
    add eax, CP_TEXT
    ret

; Field/Method/Constructor info: edx = &Member, eax = op, ecx = &ref -> eax status
I_M      EQU -4
I_REF    EQU -8
I_OP     EQU -12
I_P      EQU -16
I_COUNT  EQU -20
I_ITEM   EQU -24
I_C      EQU -28
I_I      EQU -32
I_D      EQU -40      ; JbvText
info:
    push ebp
    mov ebp, esp
    sub esp, 56
    push esi
    push edi
    mov [ebp+I_M], edx
    mov [ebp+I_OP], eax
    mov [ebp+I_REF], ecx
    mov DWORD PTR [ecx], 0
    call member_descriptor
    mov ecx, [eax]
    mov [ebp+I_D], ecx
    mov ecx, [eax+4]
    mov [ebp+I_D+4], ecx
    mov esi, [ebp+I_M]
    mov eax, [ebp+I_OP]
    cmp eax, 4
    jne if_name
    mov eax, OFFSET k_default           ; an annotation element's default
    mov edx, esi
    call member_attribute
    mov [ebp+I_P], eax
    test eax, eax
    jz if_ret
    push DWORD PTR [ebp+I_D+4]
    push DWORD PTR [ebp+I_D]
    call @jbv_return_type@8
    push DWORD PTR [ebp+I_REF]
    push edx
    push eax
    lea eax, [ebp+I_P]
    push eax
    mov edx, [esi+MB_OWNER]
    mov ecx, ebx
    call @jbv_annotation_value@24
    jmp if_ret
if_name:
    test eax, eax
    jnz if_type
    mov edx, esi
    call member_name
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    mov edx, [ebp+I_REF]
    mov ecx, ebx
    call @jbv_string_mutf@16
    jmp if_ret
if_type:                                ; the field's type, the method's return type
    cmp eax, 1
    jne if_signature
    mov eax, [ebp+I_D]
    mov edx, [ebp+I_D+4]
    cmp BYTE PTR [esi+MB_KIND], 0
    je @F
    push edx
    push eax
    call @jbv_return_type@8
@@:
    push edx
    push eax
    lea edx, [ebp+I_C]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz if_ret
    push DWORD PTR [ebp+I_REF]
    mov edx, [ebp+I_C]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp if_ret
if_signature:
    cmp eax, 5
    jne if_parameters
    mov eax, OFFSET k_signature
    mov edx, esi
    call member_attribute
    test eax, eax
    jz if_ret
    movzx ecx, WORD PTR [eax]
    xchg cl, ch
    mov edx, [esi+MB_OWNER]
    call pool_text
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    mov edx, [ebp+I_REF]
    mov ecx, ebx
    call @jbv_string_mutf@16
    jmp if_ret
if_parameters:                          ; MethodParameters: names (null if absent) or access flags
    cmp eax, 6
    jb if_classes
    mov eax, OFFSET k_params
    mov edx, esi
    call member_attribute
    test eax, eax
    jz if_ret
    mov [ebp+I_P], eax
    movzx ecx, BYTE PTR [eax]
    mov [ebp+I_COUNT], ecx
    cmp DWORD PTR [ebp+I_OP], 7
    jne if_names
    lea eax, [ebp+I_C]
    push eax
    push 'I'
    xor edx, edx
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz if_ret
    push DWORD PTR [ebp+I_REF]
    push DWORD PTR [ebp+I_COUNT]
    mov edx, [ebp+I_C]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz if_ret
    push 0
    push esp
    mov edx, [ebp+I_REF]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_object@12
    pop edx
    mov esi, [ebp+I_P]
    xor ecx, ecx
@@:
    cmp ecx, [ebp+I_COUNT]
    jae if_ok
    movzx eax, WORD PTR [esi+ecx*4+3]
    xchg al, ah
    mov [edx+ecx*4+DATA0], eax
    inc ecx
    jmp @B
if_names:
    mov eax, OFFSET n_string
    mov ecx, [ebp+I_COUNT]
    mov edx, [ebp+I_REF]
    call array
    test eax, eax
    jnz if_ret
    mov eax, [ebp+I_REF]
    mov ecx, [eax]
    call retain
    xor edi, edi
if_name_next:
    xor eax, eax
    cmp edi, [ebp+I_COUNT]
    jae if_names_done
    mov eax, [ebp+I_P]
    movzx ecx, WORD PTR [eax+edi*4+1]
    xchg cl, ch
    test ecx, ecx
    jz if_name_skip
    mov edx, [esi+MB_OWNER]
    call pool_text
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    lea edx, [ebp+I_ITEM]
    mov ecx, ebx
    call @jbv_string_mutf@16
    test eax, eax
    jnz if_names_done
    mov eax, [ebp+I_REF]
    mov eax, [eax]
    mov ecx, edi
    mov edx, [ebp+I_ITEM]
    call store
if_name_skip:
    inc edi
    jmp if_name_next
if_names_done:
    jmp if_release
if_classes:                             ; exception types (3) or parameter types (2)
    mov DWORD PTR [ebp+I_P], 0
    mov DWORD PTR [ebp+I_COUNT], 0
    mov DWORD PTR [ebp+D_POS], 1
    cmp eax, 3
    jne if_count
    mov eax, OFFSET k_exceptions
    mov edx, esi
    call member_attribute
    mov [ebp+I_P], eax
    test eax, eax
    jz if_counted
    movzx eax, WORD PTR [eax]
    xchg al, ah
    mov [ebp+I_COUNT], eax
    jmp if_counted
if_count:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+I_D]
    cmp BYTE PTR [ecx+eax], ')'
    je if_counted
    lea eax, [ebp+I_D]
    call dtype
    inc DWORD PTR [ebp+I_COUNT]
    jmp if_count
if_counted:
    mov eax, OFFSET n_class
    mov ecx, [ebp+I_COUNT]
    mov edx, [ebp+I_REF]
    call array
    test eax, eax
    jnz if_ret
    mov eax, [ebp+I_REF]
    mov ecx, [eax]
    call retain
    mov DWORD PTR [ebp+D_POS], 1
    xor edi, edi
if_class:
    xor eax, eax
    cmp edi, [ebp+I_COUNT]
    jae if_release
    mov eax, [ebp+I_P]
    test eax, eax
    jz @F
    movzx ecx, WORD PTR [eax+edi*2+2]   ; a Class entry: its name
    xchg cl, ch
    mov edx, [esi+MB_OWNER]
    imul ecx, ecx, CP_SIZEOF
    add ecx, [edx+C_POOL]
    movzx ecx, WORD PTR [ecx+CP_A]
    call pool_text
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    lea edx, [ebp+I_C]
    mov ecx, ebx
    call @jbv_resolve_class@16
    jmp if_classed
@@:
    mov eax, [ebp+D_POS]
    push eax
    lea eax, [ebp+I_D]
    call dtype
    pop eax
    mov ecx, [ebp+D_POS]
    sub ecx, eax
    add eax, [ebp+I_D]
    push ecx
    push eax
    lea edx, [ebp+I_C]
    mov ecx, ebx
    call @jbv_type_class@16
if_classed:
    test eax, eax
    jnz if_release
    lea eax, [ebp+I_ITEM]
    push eax
    mov edx, [ebp+I_C]
    mov ecx, ebx
    call @jbv_mirror@12
    test eax, eax
    jnz if_release
    mov eax, [ebp+I_REF]
    mov eax, [eax]
    mov ecx, edi
    mov edx, [ebp+I_ITEM]
    call store
    inc edi
    jmp if_class
if_release:
    push eax
    mov eax, [ebp+I_REF]
    mov ecx, [eax]
    call release
    pop eax
    jmp if_ret
if_ok:
    xor eax, eax
if_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret

; Method.invoke / Constructor.newInstance: edx = &Member; [ebp+8] receiver, arguments, out
; -> eax status; a failure of the target is wrapped in InvocationTargetException
V_RECV   EQU 8
V_ARGS   EQU 12
V_OUT    EQU 16
V_M      EQU -4
V_METHOD EQU -8
V_OWNER  EQU -12
V_SLOTS  EQU -16
V_REFS   EQU -20
V_CREATED EQU -24
V_USED   EQU -28
V_I      EQU -32
V_N      EQU -36
V_BITS   EQU -44      ; uint64_t
V_D      EQU -64      ; JbvText
V_T      EQU -72      ; JbvText
V_RESULT EQU -80      ; JbvText
reflect_invoke:
    push ebp
    mov ebp, esp
    sub esp, 80
    push esi
    push edi
    lea edi, [ebp-80]
    push edx
    mov ecx, 80/4
    xor eax, eax
    rep stosd
    pop esi
    mov [ebp+V_M], esi
    mov eax, [esi+MB_TARGET]
    mov [ebp+V_METHOD], eax
    mov ecx, [esi+MB_OWNER]
    mov [ebp+V_OWNER], ecx
    mov ecx, [eax+M_DESCRIPTOR]
    mov [ebp+V_D], ecx
    mov ecx, [eax+M_DESCRIPTOR+4]
    mov [ebp+V_D+4], ecx
    push DWORD PTR [ebp+V_D+4]
    push DWORD PTR [ebp+V_D]
    call @jbv_return_type@8
    mov [ebp+V_RESULT], eax
    mov [ebp+V_RESULT+4], edx
    mov eax, [ebp+V_RECV]
    xor ecx, ecx
    mov edx, esi
    call access
    test eax, eax
    jnz iv_ret
    mov edx, [ebp+V_ARGS]
    test edx, edx
    jz @F
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz iv_ret
    mov eax, [ecx-4]
    mov [ebp+V_N], eax
@@:
    cmp BYTE PTR [esi+MB_KIND], 2       ; constructors: not of enums, abstract classes, interfaces
    jne iv_slots
    mov eax, [ebp+V_OWNER]
    test WORD PTR [eax+C_FLAGS], 4000h
    jz @F
    mov eax, S_BAD_ARG
    jmp iv_ret
@@:
    test WORD PTR [eax+C_FLAGS], ACC_ABSTRACT or ACC_INTERFACE
    jz iv_slots
    mov edx, OFFSET e_ie
    call error
    jmp iv_ret
iv_slots:
    mov eax, [ebp+V_METHOD]
    movzx edx, WORD PTR [eax+M_ARG_SLOTS]
    inc edx
    push edx
    shl edx, 2
    mov ecx, ebx
    call @jbv_alloc@8
    mov [ebp+V_SLOTS], eax
    pop edx
    mov ecx, ebx
    call @jbv_alloc@8
    mov [ebp+V_REFS], eax
    test eax, eax
    jz iv_oom
    cmp DWORD PTR [ebp+V_SLOTS], 0
    je iv_oom
    mov eax, [ebp+V_METHOD]
    test WORD PTR [eax+M_FLAGS], ACC_STATIC
    jnz @F
    mov eax, [ebp+V_SLOTS]              ; the receiver first
    mov ecx, [ebp+V_RECV]
    mov [eax], ecx
    mov eax, [ebp+V_REFS]
    mov BYTE PTR [eax], 1
    mov DWORD PTR [ebp+V_USED], 1
@@:
    mov DWORD PTR [ebp+D_POS], 1
iv_argument:
    mov eax, [ebp+D_POS]
    mov ecx, [ebp+V_D]
    cmp BYTE PTR [ecx+eax], ')'
    je iv_arguments
    mov ecx, [ebp+V_I]
    cmp ecx, [ebp+V_N]
    je iv_bad
    push eax
    lea eax, [ebp+V_D]
    call dtype
    pop eax
    mov ecx, [ebp+D_POS]
    sub ecx, eax
    mov [ebp+V_T+4], ecx
    add eax, [ebp+V_D]
    mov [ebp+V_T], eax
    push 0                              ; the argument (convert may move the array)
    push esp
    mov edx, [ebp+V_ARGS]
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov ecx, [ebp+V_I]
    inc DWORD PTR [ebp+V_I]
    mov eax, [eax+ecx*4+DATA0]
    lea edx, [ebp+V_T]
    lea ecx, [ebp+V_BITS]
    call convert
    test eax, eax
    jnz iv_done
    push DWORD PTR [ebp+V_T+4]
    push DWORD PTR [ebp+V_T]
    call @jbv_reference_type@8
    mov ecx, [ebp+V_REFS]
    mov edx, [ebp+V_USED]
    mov [ecx+edx], al
    mov ecx, [ebp+V_SLOTS]
    mov eax, [ebp+V_BITS]
    mov [ecx+edx*4], eax
    cmp DWORD PTR [ebp+D_WIDTH], 2
    jne @F
    mov eax, [ebp+V_BITS+4]
    mov [ecx+edx*4+4], eax
@@:
    mov eax, [ebp+D_WIDTH]
    add [ebp+V_USED], eax
    jmp iv_argument
iv_arguments:
    mov eax, [ebp+V_I]
    cmp eax, [ebp+V_N]
    jne iv_bad
    ; initialization errors are not target exceptions: not wrapped
    mov eax, [ebp+V_METHOD]
    cmp BYTE PTR [esi+MB_KIND], 2
    je @F
    test WORD PTR [eax+M_FLAGS], ACC_STATIC
    jz iv_virtual
@@:
    mov edx, [ebp+V_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz iv_done
    cmp BYTE PTR [esi+MB_KIND], 2
    jne iv_call
    lea eax, [ebp+V_CREATED]            ; a constructor: on a new instance
    push eax
    push 0
    mov edx, [ebp+V_OWNER]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz iv_done
    mov ecx, [ebp+V_CREATED]
    call retain
    mov eax, [ebp+V_SLOTS]
    mov ecx, [ebp+V_CREATED]
    mov [eax], ecx
    jmp iv_call
iv_virtual:                             ; the receiver's override
    push 0
    push esp
    mov edx, [ebp+V_RECV]
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov eax, [eax]
    mov [ebp+V_T], eax
    push DWORD PTR [ebp+V_METHOD]
    mov edx, [ebp+V_OWNER]
    lea ecx, [ebp+V_T]
    call @jbv_virtual_method@12
    mov [ebp+V_METHOD], eax
    mov eax, [ebp+V_T]
    mov [ebp+V_OWNER], eax
iv_call:
    mov eax, [ebp+V_METHOD]
    test eax, eax
    jz @F
    test WORD PTR [eax+M_FLAGS], ACC_ABSTRACT
    jz iv_execute
@@:
    mov edx, OFFSET e_ame
    call error
    jmp iv_failed
iv_execute:
    lea ecx, [ebp+V_BITS]
    push ecx
    push DWORD PTR [ebp+V_USED]
    push DWORD PTR [ebp+V_REFS]
    push DWORD PTR [ebp+V_SLOTS]
    push eax
    mov edx, [ebp+V_OWNER]
    mov ecx, ebx
    call @jbv_execute@28
    test eax, eax
    jz iv_result
iv_failed:
    cmp DWORD PTR [ebx+VM_EXCEPTION], 0
    je iv_done
    push S_EXCEPTION
    push DWORD PTR [ebx+VM_EXCEPTION]
    mov edx, OFFSET e_ite
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp iv_done
iv_result:                              ; the new instance, null for void, references, boxed primitives
    mov ecx, [ebp+V_OUT]
    cmp BYTE PTR [esi+MB_KIND], 2
    jne @F
    mov edx, [ebp+V_CREATED]
    mov [ecx], edx
    jmp iv_done
@@:
    mov DWORD PTR [ecx], 0
    mov edx, [ebp+V_RESULT]
    cmp BYTE PTR [edx], 'V'
    je iv_done
    push DWORD PTR [ebp+V_RESULT+4]
    push edx
    call @jbv_reference_type@8
    test eax, eax
    jz @F
    mov ecx, [ebp+V_OUT]
    mov eax, [ebp+V_BITS]
    mov [ecx], eax
    xor eax, eax
    jmp iv_done
@@:
    push DWORD PTR [ebp+V_OUT]
    push DWORD PTR [ebp+V_BITS+4]
    push DWORD PTR [ebp+V_BITS]
    mov edx, [ebp+V_RESULT]
    movzx edx, BYTE PTR [edx]
    mov ecx, ebx
    call @jbv_box@20
    jmp iv_done
iv_bad:
    mov eax, S_BAD_ARG
    jmp iv_done
iv_oom:
    mov eax, S_OOM
iv_done:
    push eax
    mov ecx, [ebp+V_CREATED]
    call release
    mov edx, [ebp+V_SLOTS]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+V_REFS]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
iv_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret 12

; Field get/set: edx = &Member, eax = the Field object, ecx = a, [esp+4] out -> eax status
; (a[3]: 0 get, 1 set; other values the typed primitive accessors)
F_OVERRIDE EQU -4
F_BITS   EQU -12      ; uint64_t
F_OBJ    EQU -16
F_SET    EQU -20
field:
    push ebp
    mov ebp, esp
    sub esp, 20
    push esi
    push edi
    mov esi, edx                        ; the Member
    mov edi, ecx                        ; a
    mov eax, [eax+DATA0+12]             ; setAccessible (access may move the object)
    mov [ebp+F_OVERRIDE], eax
    xor eax, eax
    mov [ebp+F_OBJ], eax
    mov [ebp+F_BITS], eax
    mov [ebp+F_BITS+4], eax
    mov ecx, [edi+12]                   ; set: a[3] <= 1 and not 0
    cmp ecx, 1
    jg @F
    test ecx, ecx
    setnz al
@@:
    mov [ebp+F_SET], eax
    mov eax, [edi+4]
    xor ecx, ecx
    mov edx, esi
    call access
    test eax, eax
    jnz fd_ret
    mov edx, [esi+MB_TARGET]
    mov eax, [edi+12]
    cmp eax, 1
    jbe @F
    push DWORD PTR [edx+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edx+FIELD_DESCRIPTOR+TEXT_DATA]
    call @jbv_reference_type@8
    test eax, eax
    mov eax, S_BAD_ARG
    jnz fd_ret
@@:
    cmp DWORD PTR [ebp+F_SET], 0        ; a final field: only an overridden instance non-record one
    je fd_static
    mov edx, [esi+MB_TARGET]
    test WORD PTR [edx+FIELD_FLAGS], ACC_FINAL
    jz fd_static
    cmp DWORD PTR [ebp+F_OVERRIDE], 0
    je fd_final
    test WORD PTR [edx+FIELD_FLAGS], ACC_STATIC
    jnz fd_final
    push OFFSET k_record
    mov ecx, [esi+MB_OWNER]
    mov edx, [ecx+C_ATTRIBUTES]
    call @jbv_attribute@12
    test eax, eax
    jz fd_static
fd_final:
    mov edx, OFFSET e_iae
    call error
    jmp fd_ret
fd_static:
    mov edx, [esi+MB_TARGET]
    test WORD PTR [edx+FIELD_FLAGS], ACC_STATIC
    jz @F
    mov edx, [esi+MB_OWNER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz fd_ret
@@:
    cmp DWORD PTR [ebp+F_SET], 0
    je @F
    mov edx, [esi+MB_TARGET]
    add edx, FIELD_DESCRIPTOR
    lea ecx, [ebp+F_BITS]
    mov eax, [edi+8]
    call convert
    test eax, eax
    jnz fd_ret
@@:
    mov edx, [esi+MB_TARGET]            ; the slot, located only now (the calls above may move the receiver)
    test WORD PTR [edx+FIELD_FLAGS], ACC_STATIC
    jz @F
    lea eax, [edx+FIELD_VALUE]
    jmp fd_located
@@:
    lea eax, [ebp+F_OBJ]
    push eax
    mov edx, [edi+4]
    mov ecx, ebx
    call @jbv_object@12
    mov edx, [esi+MB_TARGET]
    mov eax, [edx+FIELD_SLOT]
    mov ecx, [ebp+F_OBJ]
    lea eax, [ecx+eax*4+DATA0]
fd_located:
    mov edi, eax
    mov eax, [esi+MB_TARGET]
    mov eax, [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    movzx ecx, BYTE PTR [eax]
    push ecx
    call @jbv_kind@4
    pop edx                             ; the descriptor's first char
    mov ecx, 1                          ; the width
    cmp al, 2
    je @F
    cmp al, 5
    jne fd_width
@@:
    inc ecx
fd_width:
    cmp DWORD PTR [ebp+F_SET], 0
    je fd_get
    mov eax, [ebp+F_BITS]
    mov [edi], eax
    cmp ecx, 2
    jne @F
    mov eax, [ebp+F_BITS+4]
    mov [edi+4], eax
@@:
    xor eax, eax
    mov edx, [ebp+F_OBJ]
    test edx, edx
    jz fd_ret
    push DWORD PTR [edi]
    mov ecx, ebx
    call @jbv_barrier_checked@12
    xor eax, eax
    jmp fd_ret
fd_get:
    mov eax, [edi]
    mov [ebp+F_BITS], eax
    cmp ecx, 2
    jne @F
    mov eax, [edi+4]
    mov [ebp+F_BITS+4], eax
@@:
    cmp dl, 'L'
    je @F
    cmp dl, '['
    jne fd_box
@@:
    mov ecx, [ebp+8]
    mov eax, [ebp+F_BITS]
    mov [ecx], eax
    xor eax, eax
    jmp fd_ret
fd_box:
    push DWORD PTR [ebp+8]
    push DWORD PTR [ebp+F_BITS+4]
    push DWORD PTR [ebp+F_BITS]
    mov ecx, ebx
    call @jbv_box@20
fd_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret 4

; java.lang.reflect.Array: esi = a {array or class, index or length, value or dims, op}, edi = &out
; op 0 newInstance(class, length), 1 newInstance(class, dims), 2 getLength, 3 get, 4 set,
; others the typed get/set of primitives
A_SIZES  EQU -1020    ; int32_t[255]
A_C      EQU -1024
A_DIMS   EQU -1028
A_N      EQU -1032
A_BITS   EQU -1040    ; uint64_t
A_CODE   EQU -1044
A_O      EQU -1048
reflect_array:
    push ebp
    mov ebp, esp
    sub esp, 1048
    mov eax, [esi+12]
    cmp eax, 1
    ja ra_access
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_mirror_type@8
    mov [ebp+A_C], eax
    test eax, eax
    jnz @F
    mov eax, S_NULL
    jmp ra_ret
@@:
    cmp BYTE PTR [eax+C_PRIMITIVE], 'V'
    je ra_bad
    mov DWORD PTR [ebp+A_DIMS], 0
    mov DWORD PTR [ebp+A_N], 1
    cmp DWORD PTR [esi+12], 1
    jne @F
    lea eax, [ebp+A_DIMS]
    push eax
    mov edx, [esi+8]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ra_ret
    mov eax, [ebp+A_DIMS]
    mov eax, [eax-4]
    mov [ebp+A_N], eax
    test eax, eax
    jz ra_bad
    cmp eax, 255
    ja ra_bad
@@:
    mov eax, [ebp+A_C]                  ; at most 255 dimensions in all
    movzx ecx, WORD PTR [eax+C_NAME+TEXT_SIZE]
    mov edx, [eax+C_NAME+TEXT_DATA]
    xor eax, eax
@@:
    cmp eax, ecx
    jae @F
    cmp BYTE PTR [edx+eax], '['
    jne @F
    inc eax
    jmp @B
@@:
    add eax, [ebp+A_N]
    cmp eax, 255
    ja ra_bad
    xor ecx, ecx
ra_dimension:
    cmp ecx, [ebp+A_N]
    jae ra_make
    mov eax, [ebp+A_DIMS]
    test eax, eax
    jz @F
    mov eax, [eax+ecx*4+DATA0]
    mov [ebp+A_SIZES+ecx*4], eax
    test eax, eax
    jns @F
    mov eax, S_NEGATIVE
    jmp ra_ret
@@:
    push ecx
    lea eax, [ebp+A_C]
    push eax
    mov edx, [ebp+A_C]
    movzx eax, BYTE PTR [edx+C_PRIMITIVE]
    test eax, eax
    jz @F
    xor edx, edx
    jmp ra_kind
@@:
    mov eax, 'L'
ra_kind:
    push eax
    mov ecx, ebx
    call @jbv_array_class@16
    pop ecx
    test eax, eax
    jnz ra_ret
    inc ecx
    jmp ra_dimension
ra_make:                                ; multi_array allocates while reading sizes: a copy
    cmp DWORD PTR [ebp+A_DIMS], 0
    je @F
    push edi
    push DWORD PTR [ebp+A_N]
    lea eax, [ebp+A_SIZES]
    push eax
    mov edx, [ebp+A_C]
    mov ecx, ebx
    call @jbv_multi_array@20
    jmp ra_ret
@@:
    push edi
    push DWORD PTR [esi+4]
    mov edx, [ebp+A_C]
    mov ecx, ebx
    call @jbv_new@16
    jmp ra_ret
ra_access:
    lea eax, [ebp+A_O]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ra_ret
    mov eax, [ebp+A_O]
    mov eax, [eax]
    movzx ecx, BYTE PTR [eax+C_ARRAY_KIND]
    mov [ebp+A_CODE], ecx
    test ecx, ecx
    jz ra_bad
    mov eax, [esi+12]
    cmp eax, 4                          ; typed accessors are for primitive arrays
    jbe @F
    cmp cl, 'L'
    je ra_bad
@@:
    cmp eax, 2
    jne @F
    push edi                            ; getLength: a boxed int
    push 0
    mov eax, [ebp+A_O]
    push DWORD PTR [eax-4]
    mov edx, 'I'
    mov ecx, ebx
    call @jbv_box@20
    jmp ra_ret
@@:
    mov edx, [esi+4]
    mov eax, [ebp+A_O]
    cmp edx, [eax-4]
    jae ra_bounds
    mov eax, [esi+12]
    cmp eax, 3
    je ra_get
    cmp eax, 4
    jle ra_set                          ; (typed setters: negative ops)
ra_get:
    push DWORD PTR [ebp+A_CODE]
    mov edx, [esi+4]
    mov ecx, [ebp+A_O]
    call @jbv_array_get@12
    cmp BYTE PTR [ebp+A_CODE], 'L'
    jne @F
    mov [edi], eax
    xor eax, eax
    jmp ra_ret
@@:
    push edi
    push edx
    push eax
    mov edx, [ebp+A_CODE]
    mov ecx, ebx
    call @jbv_box@20
    jmp ra_ret
ra_set:
    cmp BYTE PTR [ebp+A_CODE], 'L'
    jne ra_set_primitive
    mov edx, [esi+8]
    mov [ebp+A_BITS], edx
    mov DWORD PTR [ebp+A_BITS+4], 0
    test edx, edx
    jz ra_store
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    test eax, eax
    jnz ra_ret
    mov ecx, [ecx]
    mov edx, [ebp+A_O]
    mov edx, [edx]
    mov edx, [edx+C_COMPONENT]
    call @jbv_assignable@8
    test eax, eax
    jz ra_bad
    jmp ra_store
ra_set_primitive:
    lea eax, [ebp+A_CODE]               ; the element code as a one-char descriptor
    push 1
    push eax
    mov edx, esp
    lea ecx, [ebp+A_BITS]
    mov eax, [esi+8]
    call convert
    add esp, 8
    test eax, eax
    jnz ra_ret
    lea eax, [ebp+A_O]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
ra_store:
    push DWORD PTR [ebp+A_BITS+4]
    push DWORD PTR [ebp+A_BITS]
    push DWORD PTR [ebp+A_CODE]
    mov edx, [esi+4]
    mov ecx, [ebp+A_O]
    call @jbv_array_set@20
    xor eax, eax
    cmp BYTE PTR [ebp+A_CODE], 'L'
    jne ra_ret
    push DWORD PTR [ebp+A_BITS]
    mov edx, [ebp+A_O]
    mov ecx, ebx
    call @jbv_barrier_checked@12
    xor eax, eax
    jmp ra_ret
ra_bounds:
    mov eax, S_BOUNDS
    jmp ra_ret
ra_bad:
    mov eax, S_BAD_ARG
ra_ret:
    mov esp, ebp
    pop ebp
    ret

; JbvStatus JBV_CALL jbv_reflect_native(vm, user, a, count, out): jbv/runtime/Reflection
; (info, flags, invoke, field, access, array, convert, annotations, classSignature)
R_M      EQU -12      ; Member
R_O      EQU -16
R_REF    EQU -20
R_BITS   EQU -28      ; uint64_t
R_N      EQU -32
R_P      EQU -36
R_CURSOR EQU -40
R_I      EQU -44
R_ITEM   EQU -48
jbv_reflect_native PROC
    push ebp
    mov ebp, esp
    sub esp, 56
    push ebx
    push esi
    push edi
    mov ebx, [ebp+8]
    mov esi, [ebp+16]
    mov edi, [ebp+24]
    xor eax, eax
    mov [edi], eax
    mov [edi+4], eax
    mov [ebp+R_REF], eax
    mov eax, [ebp+12]
    cmp eax, 8
    jne @F
    push edi
    push esi
    mov edx, 21
    mov ecx, ebx
    call @jbv_reflect_class@16
    jmp rn_ret
@@:
    cmp eax, 5
    jne @F
    push edi
    lea edi, [ebp+R_REF]
    call reflect_array
    pop edi
    jmp rn_end
@@:
    cmp eax, 6
    jne rn_member
    lea eax, [ebp+R_BITS]               ; convert: a boxed primitive as another primitive type
    push eax
    push 0
    movzx eax, BYTE PTR [esi+4]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_unbox@20
    cmp eax, S_CAST
    je rn_bad
    cmp eax, S_NULL
    je rn_bad
    test eax, eax
    jnz rn_ret
    lea eax, [ebp+R_REF]
    push eax
    push DWORD PTR [ebp+R_BITS+4]
    push DWORD PTR [ebp+R_BITS]
    movzx edx, BYTE PTR [esi+4]
    mov ecx, ebx
    call @jbv_box@20
    jmp rn_end
rn_member:
    mov eax, [esi]
    lea edx, [ebp+R_M]
    lea ecx, [ebp+R_O]
    call unpack
    test eax, eax
    jnz rn_ret
    mov eax, [ebp+12]
    test eax, eax
    jnz @F
    mov eax, [esi+4]                    ; info
    lea edx, [ebp+R_M]
    lea ecx, [ebp+R_REF]
    call info
    jmp rn_end
@@:
    cmp eax, 1
    jne @F
    lea edx, [ebp+R_M]                  ; flags
    call member_flags
    mov [edi], eax
    xor eax, eax
    jmp rn_ret
@@:
    cmp eax, 2
    jne @F
    lea eax, [ebp+R_REF]
    push eax
    push DWORD PTR [esi+8]
    push DWORD PTR [esi+4]
    lea edx, [ebp+R_M]
    call reflect_invoke
    jmp rn_end
@@:
    cmp eax, 3
    jne @F
    lea eax, [ebp+R_REF]
    push eax
    mov eax, [ebp+R_O]
    mov ecx, esi
    lea edx, [ebp+R_M]
    call field
    jmp rn_end
@@:
    cmp eax, 4
    jne @F
    mov eax, [esi+4]                    ; access: a receiver check as a query
    mov ecx, 1
    lea edx, [ebp+R_M]
    call access
    cmp eax, S_EXCEPTION
    jne rn_answer
    cmp DWORD PTR [ebx+VM_EXCEPTION], 0
    je rn_answer
    xor eax, eax
    mov [ebx+VM_EXCEPTION], eax
    jmp rn_ret
rn_answer:
    xor ecx, ecx
    test eax, eax
    sete cl
    mov [edi], ecx
    jmp rn_ret
@@:
    cmp eax, 7
    jne rn_unsupported
    cmp DWORD PTR [esi+4], -1           ; annotations: of the member, or of each parameter
    jne rn_parameters
    mov eax, OFFSET k_annots
    lea edx, [ebp+R_M]
    call member_attribute
    lea ecx, [ebp+R_REF]
    push ecx
    push eax
    mov edx, [ebp+R_M+MB_OWNER]
    mov ecx, ebx
    call @jbv_annotations@16
    jmp rn_end
rn_parameters:
    lea edx, [ebp+R_M]
    call member_descriptor
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    mov DWORD PTR [ebp+R_N], 0
    mov DWORD PTR [ebp+D_POS], 1
@@:
    mov eax, [ebp+D_POS]
    mov ecx, [esp]
    cmp BYTE PTR [ecx+eax], ')'
    je @F
    mov eax, esp
    call dtype
    inc DWORD PTR [ebp+R_N]
    jmp @B
@@:
    add esp, 8
    mov eax, OFFSET k_param_annots
    lea edx, [ebp+R_M]
    call member_attribute
    mov [ebp+R_P], eax
    xor ecx, ecx
    test eax, eax
    jz @F
    lea ecx, [eax+1]
@@:
    mov [ebp+R_CURSOR], ecx
    mov eax, OFFSET n_annots
    mov ecx, [ebp+R_N]
    lea edx, [ebp+R_REF]
    call array
    test eax, eax
    jnz rn_ret
    mov ecx, [ebp+R_REF]
    call retain
    mov DWORD PTR [ebp+R_I], 0
rn_parameter:
    xor eax, eax
    mov ecx, [ebp+R_I]
    cmp ecx, [ebp+R_N]
    jae rn_parameters_done
    mov DWORD PTR [ebp+R_ITEM], 0
    mov edx, [ebp+R_N]                  ; the leading parameters without a table get none
    mov eax, [ebp+R_P]
    xor esi, esi                        ; 0: no table
    test eax, eax
    jz @F
    movzx eax, BYTE PTR [eax]
    sub edx, eax
    cmp ecx, edx
    jb @F
    mov esi, [ebp+R_CURSOR]
@@:
    lea eax, [ebp+R_ITEM]
    push eax
    push esi
    mov edx, [ebp+R_M+MB_OWNER]
    mov ecx, ebx
    call @jbv_annotations@16
    test eax, eax
    jnz rn_parameters_done
    mov eax, [ebp+R_REF]
    mov ecx, [ebp+R_I]
    mov edx, [ebp+R_ITEM]
    call store
    test esi, esi
    jz @F
    mov ecx, esi
    call @jbv_skip_annotations@4
    mov [ebp+R_CURSOR], eax
@@:
    inc DWORD PTR [ebp+R_I]
    jmp rn_parameter
rn_parameters_done:
    push eax
    mov ecx, [ebp+R_REF]
    call release
    pop eax
    jmp rn_end
rn_unsupported:
    mov eax, 6
    jmp rn_ret
rn_bad:
    mov eax, S_BAD_ARG
    jmp rn_ret
rn_end:
    test eax, eax
    jnz rn_ret
    mov ecx, [ebp+R_REF]
    mov [edi], ecx
rn_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_reflect_native ENDP
END

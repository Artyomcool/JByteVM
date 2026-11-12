; Runtime-visible annotations: an
; annotation is an instance of a generated $$JbvAnnotation class over jbv/runtime/AnnotationValue
; whose element methods read a values array (field 1; field 0 is the annotation type's mirror).
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_object_bytes@4:PROC
EXTERN SYSCALL @jbv_return_type@8:PROC
EXTERN SYSCALL @jbv_reference_type@8:PROC
EXTERN SYSCALL @jbv_unbox@20:PROC
EXTERN SYSCALL @jbv_box@20:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_free_class@8:PROC
EXTERN SYSCALL @jbv_prepare_method@4:PROC
EXTERN SYSCALL @jbv_type_class@16:PROC
EXTERN SYSCALL @jbv_mirror@12:PROC
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_string_mutf@16:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_text_eq@16:PROC
EXTERN SYSCALL @jbv_array_set@20:PROC
EXTERN SYSCALL @jbv_attribute@12:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC

S_OOM       EQU 2
S_LIMIT     EQU 10
S_LINKAGE   EQU 8
S_EXCEPTION EQU 22
DATA0       EQU 4

.const
n_annotation DB 'java/lang/annotation/Annotation'
n_impl       DB 'jbv/runtime/AnnotationValue'
n_suffix     DB '$$JbvAnnotation'
n_object     DB 'java/lang/Object'
n_incomplete DB 'java/lang/annotation/IncompleteAnnotationException', 0
n_enum       DB 'java/lang/EnumConstantNotPresentException', 0
s_default    DB 'AnnotationDefault', 0

.code
; esi = &p -> eax = the next big-endian u16 (p advanced)
read2:
    mov edx, [esi]
    movzx eax, WORD PTR [edx]
    xchg al, ah
    add edx, 2
    mov [esi], edx
    ret
; esi = p -> esi past one element_value / one annotation
skip_value:
    lodsb
    cmp al, '@'
    je skip_annotation
    cmp al, '['
    jne sv_scalar
    movzx ecx, WORD PTR [esi]
    xchg cl, ch
    add esi, 2
sv_items:
    test ecx, ecx
    jz sv_ret
    push ecx
    call skip_value
    pop ecx
    dec ecx
    jmp sv_items
sv_scalar:
    cmp al, 'e'
    jne @F
    add esi, 2
@@:
    add esi, 2
sv_ret:
    ret
skip_annotation:
    movzx ecx, WORD PTR [esi+2]
    xchg cl, ch
    add esi, 4
sa_pair:
    test ecx, ecx
    jz sv_ret
    push ecx
    add esi, 2
    call skip_value
    pop ecx
    dec ecx
    jmp sa_pair
@jbv_skip_annotations@4 PROC SYSCALL ; ecx = p (a u16 count of annotations) -> eax past them
    push esi
    mov esi, ecx
    movzx ecx, WORD PTR [esi]
    xchg cl, ch
    add esi, 2
@@:
    test ecx, ecx
    jz @F
    push ecx
    call skip_annotation
    pop ecx
    dec ecx
    jmp @B
@@:
    mov eax, esi
    pop esi
    ret
@jbv_skip_annotations@4 ENDP

; ebx = vm, eax = an array ref, ecx = the index, edx = the reference to store (producers allocate:
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
; ebx = vm, eax = a value -> eax status, edx = it, or a copy when it is an array
clone_array:
    push esi
    push edi
    mov esi, eax
    push 0
    push esp
    mov edx, eax
    mov ecx, ebx
    call @jbv_object@12
    pop edi
    mov edx, esi
    test eax, eax
    jnz ca_ret
    mov ecx, [edi]
    cmp BYTE PTR [ecx+C_ARRAY_KIND], 0
    je ca_ret
    push 0
    push esp
    push DWORD PTR [edi-4]
    mov edx, ecx
    mov ecx, ebx
    call @jbv_new@16
    pop edx
    test eax, eax
    jnz ca_ret
    push edx
    push 0
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop edi                             ; the copy
    push 0
    push esp
    mov edx, esi
    mov ecx, ebx
    call @jbv_object@12                 ; the value again (jbv_new may have moved it)
    pop esi
    mov ecx, esi
    call @jbv_object_bytes@4
    mov ecx, eax
    add esi, DATA0
    add edi, DATA0
    rep movsb
    pop edx
    xor eax, eax
ca_ret:
    pop edi
    pop esi
    ret

; JbvStatus JBV_CALL element(vm, user, a, count, out): an element method (user = its index)
element PROC
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    mov ebx, [ebp+8]
    mov eax, [ebp+16]
    push 0
    push esp
    mov edx, [eax]
    mov ecx, ebx
    call @jbv_object@12
    pop esi
    test eax, eax
    jnz el_ret
    mov edi, [esi]
    mov edi, [edi+C_METHODS]
    imul eax, DWORD PTR [ebp+12], M_SIZEOF
    add edi, eax                        ; the method
    push 0
    push esp
    mov edx, [esi+DATA0+4]
    mov ecx, ebx
    call @jbv_object@12
    pop eax                             ; the values
    mov ecx, [ebp+12]
    mov esi, [eax+ecx*4+DATA0]
    test esi, esi
    jz el_incomplete
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edi+M_DESCRIPTOR+TEXT_DATA]
    call @jbv_return_type@8
    mov edi, eax
    push edx
    push eax
    call @jbv_reference_type@8
    test eax, eax
    jz el_unbox
    mov eax, esi
    call clone_array
    test eax, eax
    jnz el_ret
    mov ecx, [ebp+24]
    mov [ecx], edx
    mov DWORD PTR [ecx+4], 0
    jmp el_ret
el_unbox:
    push DWORD PTR [ebp+24]
    push 0
    movzx eax, BYTE PTR [edi]
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_unbox@20
    jmp el_ret
el_incomplete:
    push S_EXCEPTION
    push 0
    mov edx, OFFSET n_incomplete
    mov ecx, ebx
    call @jbv_throw_named@16
el_ret:
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
element ENDP

; ebx = vm, eax = an annotation interface -> eax status, edx = its implementation class
implementation:
    push esi
    push edi
    push ebp
    mov esi, eax
    mov edi, [ebx+VM_CLASSES]
im_scan:
    test edi, edi
    jz im_new
    mov eax, [edi+C_SUPER]
    test eax, eax
    jz im_next
    cmp WORD PTR [eax+C_NAME+TEXT_SIZE], 27
    jne im_next
    cmp WORD PTR [edi+C_INTERFACE_COUNT], 1
    jne im_next
    mov ecx, [edi+C_INTERFACES]
    cmp [ecx], esi
    jne im_next
    push esi
    push edi
    mov esi, [eax+C_NAME+TEXT_DATA]
    mov edi, OFFSET n_impl
    mov ecx, 27
    repe cmpsb
    pop edi
    pop esi
    jne im_next
    mov edx, edi
    xor eax, eax
    jmp im_ret
im_next:
    mov edi, [edi+C_NEXT]
    jmp im_scan
im_new:
    push 0
    mov edx, esp
    push 27
    push OFFSET n_impl
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop ebp                             ; the base
    test eax, eax
    jnz im_ret
    movzx edx, WORD PTR [esi+C_NAME+TEXT_SIZE]
    add edx, C_SIZEOF+16
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz im_oom
    mov edi, eax                        ; the class, its name after it: <type>$$JbvAnnotation
    lea eax, [edi+C_SIZEOF]
    mov [edi+C_NAME+TEXT_DATA], eax
    movzx ecx, WORD PTR [esi+C_NAME+TEXT_SIZE]
    lea edx, [ecx+15]
    mov [edi+C_NAME+TEXT_SIZE], dx
    push esi
    push edi
    mov esi, [esi+C_NAME+TEXT_DATA]
    mov edi, eax
    rep movsb
    mov esi, OFFSET n_suffix
    mov ecx, 15
    rep movsb
    pop edi
    pop esi
    push DWORD PTR [edi+C_NAME+TEXT_SIZE]
    push DWORD PTR [edi+C_NAME+TEXT_DATA]
    mov ecx, ebx
    call @jbv_find_class@12
    test eax, eax
    mov eax, S_LINKAGE
    jnz im_free
    movzx edx, WORD PTR [esi+C_METHOD_COUNT]
    imul edx, edx, M_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    mov [edi+C_METHODS], eax
    mov edx, 4
    mov ecx, ebx
    call @jbv_alloc@8
    mov [edi+C_INTERFACES], eax
    test eax, eax
    jz im_free_oom
    cmp DWORD PTR [edi+C_METHODS], 0
    je im_free_oom
    mov [edi+C_SUPER], ebp
    mov ecx, [ebp+C_INSTANCE_SLOTS]
    mov [edi+C_INSTANCE_SLOTS], ecx
    mov WORD PTR [edi+C_FLAGS], 11h
    mov BYTE PTR [edi+C_INIT_STATE], 2
    mov BYTE PTR [edi+C_LINK_STATE], 2
    mov WORD PTR [edi+C_INTERFACE_COUNT], 1
    mov [eax], esi
    mov ebp, [edi+C_METHODS]            ; the abstract methods become element natives
    movzx ecx, WORD PTR [esi+C_METHOD_COUNT]
    mov edx, [esi+C_METHODS]
im_method:
    test ecx, ecx
    jz im_done
    test WORD PTR [edx+M_FLAGS], 400h
    jz im_method_next
    mov eax, [edx+M_NAME]
    mov [ebp+M_NAME], eax
    mov eax, [edx+M_NAME+4]
    mov [ebp+M_NAME+4], eax
    mov eax, [edx+M_DESCRIPTOR]
    mov [ebp+M_DESCRIPTOR], eax
    mov eax, [edx+M_DESCRIPTOR+4]
    mov [ebp+M_DESCRIPTOR+4], eax
    mov eax, [edx+M_ATTRIBUTES]
    mov [ebp+M_ATTRIBUTES], eax
    mov WORD PTR [ebp+M_FLAGS], 111h
    mov BYTE PTR [ebp+M_INTRINSIC], 4
    mov DWORD PTR [ebp+M_NATIVE_SLOTS], OFFSET element
    movzx eax, WORD PTR [edi+C_METHOD_COUNT]
    mov [ebp+M_NATIVE_USER], eax
    inc WORD PTR [edi+C_METHOD_COUNT]
    push ecx
    push edx
    mov ecx, ebp
    call @jbv_prepare_method@4
    pop edx
    pop ecx
    add ebp, M_SIZEOF
im_method_next:
    add edx, M_SIZEOF
    dec ecx
    jmp im_method
im_done:
    mov eax, [ebx+VM_CLASSES]
    mov [edi+C_NEXT], eax
    mov [ebx+VM_CLASSES], edi
    mov edx, edi
    xor eax, eax
    jmp im_ret
im_free_oom:
    mov eax, S_OOM
im_free:
    push eax
    mov edx, edi
    mov ecx, ebx
    call @jbv_free_class@8
    pop eax
    jmp im_ret
im_oom:
    mov eax, S_OOM
im_ret:
    pop ebp
    pop edi
    pop esi
    ret

; ---- element values: ebx = vm, edi = the owner (its pool), esi = &p
V_P     EQU 8
V_EXP   EQU 12        ; JbvText expected
V_REF   EQU 20
V_TYPE  EQU -4
V_BITS  EQU -12
V_I     EQU -16
V_N     EQU -20
V_ITEM  EQU -24
V_TAG   EQU -28
V_CONST EQU -32
@jbv_annotation_value@24 PROC SYSCALL ; ecx vm, edx owner, [ebp+8] p, expected, ref
    push ebp
    mov ebp, esp
    sub esp, 32
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    mov esi, [ebp+V_P]
    mov eax, [ebx+VM_DEPTH]
    cmp eax, [ebx+VM_MAX_DEPTH]
    mov eax, S_LIMIT
    jae av_ret
    inc DWORD PTR [ebx+VM_DEPTH]
    call read_value
    dec DWORD PTR [ebx+VM_DEPTH]
av_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 16
@jbv_annotation_value@24 ENDP
read_value:
    mov edx, [esi]
    movzx eax, BYTE PTR [edx]
    inc edx
    mov [esi], edx
    cmp al, '@'
    jne @F
    mov eax, [ebp+V_REF]
    jmp read_annotation
@@:
    cmp al, '['
    je rv_array
    mov [ebp+V_TAG], eax
    call read2
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    mov [ebp+V_CONST], eax
    cmp BYTE PTR [ebp+V_TAG], 's'
    jne @F
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    mov edx, [ebp+V_REF]
    mov ecx, ebx
    call @jbv_string_mutf@16
    ret
@@:
    cmp BYTE PTR [ebp+V_TAG], 'c'
    jne @F
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    lea edx, [ebp+V_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz rv_ret
    push DWORD PTR [ebp+V_REF]
    mov edx, [ebp+V_TYPE]
    mov ecx, ebx
    call @jbv_mirror@12
    ret
@@:
    cmp BYTE PTR [ebp+V_TAG], 'e'
    jne rv_box
    call read2                          ; the constant's name
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    mov [ebp+V_I], eax
    mov eax, [ebp+V_CONST]
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    lea edx, [ebp+V_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz rv_ret
    mov edx, [ebp+V_TYPE]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz rv_ret
    mov edx, [ebp+V_TYPE]
    movzx ecx, WORD PTR [edx+C_FIELD_COUNT]
    mov edx, [edx+C_FIELDS]
rv_field:
    test ecx, ecx
    jz rv_missing
    test WORD PTR [edx+FIELD_FLAGS], 4000h
    jz rv_field_next
    push ecx
    push edx
    mov eax, [ebp+V_I]
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    push DWORD PTR [edx+FIELD_NAME+TEXT_SIZE]
    push DWORD PTR [edx+FIELD_NAME+TEXT_DATA]
    call @jbv_text_eq@16
    pop edx
    pop ecx
    test eax, eax
    jz rv_field_next
    mov eax, [edx+FIELD_VALUE]
    mov ecx, [ebp+V_REF]
    mov [ecx], eax
    xor eax, eax
    ret
rv_field_next:
    add edx, FIELD_SIZEOF
    dec ecx
    jmp rv_field
rv_missing:
    push S_EXCEPTION
    push 0
    mov edx, OFFSET n_enum
    mov ecx, ebx
    call @jbv_throw_named@16
    ret
rv_box:
    push DWORD PTR [ebp+V_REF]
    push DWORD PTR [eax+CP_BITS_HI]
    push DWORD PTR [eax+CP_BITS]
    movzx edx, BYTE PTR [ebp+V_TAG]
    mov ecx, ebx
    call @jbv_box@20
    ret
rv_array:                               ; an array of the expected type, element by element
    call read2
    mov [ebp+V_N], eax
    push DWORD PTR [ebp+V_EXP+4]
    push DWORD PTR [ebp+V_EXP]
    lea edx, [ebp+V_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz rv_ret
    push DWORD PTR [ebp+V_REF]
    push DWORD PTR [ebp+V_N]
    mov edx, [ebp+V_TYPE]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz rv_ret
    mov eax, [ebp+V_REF]
    push DWORD PTR [eax]
    push ebx
    call jbv_retain
    add esp, 8
    mov DWORD PTR [ebp+V_I], 0
ra_item:
    mov eax, [ebp+V_I]
    cmp eax, [ebp+V_N]
    jae ra_done
    mov DWORD PTR [ebp+V_ITEM], 0
    lea eax, [ebp+V_ITEM]
    push eax
    movzx eax, WORD PTR [ebp+V_EXP+4]   ; the component: the expected type without its '['
    dec eax
    push eax
    mov eax, [ebp+V_EXP]
    inc eax
    push eax
    push esi
    mov edx, edi
    mov ecx, ebx
    call @jbv_annotation_value@24
    test eax, eax
    jnz ra_end
    mov ecx, [ebp+V_TYPE]
    movzx ecx, BYTE PTR [ecx+C_ARRAY_KIND]
    cmp cl, 'L'
    jne ra_primitive
    mov eax, [ebp+V_REF]
    mov eax, [eax]
    mov ecx, [ebp+V_I]
    mov edx, [ebp+V_ITEM]
    call store
    jmp ra_next
ra_primitive:
    lea eax, [ebp+V_BITS]
    push eax
    push 0
    push ecx
    mov edx, [ebp+V_ITEM]
    mov ecx, ebx
    call @jbv_unbox@20
    test eax, eax
    jnz ra_end
    mov eax, [ebp+V_REF]
    push 0
    push esp
    mov edx, [eax]
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    push DWORD PTR [ebp+V_BITS+4]
    push DWORD PTR [ebp+V_BITS]
    mov eax, [ebp+V_TYPE]
    movzx eax, BYTE PTR [eax+C_ARRAY_KIND]
    push eax
    mov edx, [ebp+V_I]
    call @jbv_array_set@20
ra_next:
    inc DWORD PTR [ebp+V_I]
    jmp ra_item
ra_done:
    xor eax, eax
ra_end:
    push eax
    mov eax, [ebp+V_REF]
    push DWORD PTR [eax]
    push ebx
    call jbv_release
    add esp, 8
    pop eax
rv_ret:
    ret

; ebx = vm, edi = owner, esi = &p (at the type index), eax = &ref -> eax status
A_REF    EQU -4
A_TYPE   EQU -8
A_IMPL   EQU -12
A_ARRT   EQU -16
A_ARRAY  EQU -20
A_MIRROR EQU -24
A_ITEM   EQU -28
A_N      EQU -32
A_I      EQU -36
A_J      EQU -40      ; also the default's cursor
A_KEY    EQU -48      ; JbvText
read_annotation:
    push ebp
    mov ebp, esp
    sub esp, 48
    mov [ebp+A_REF], eax
    xor eax, eax
    mov [ebp+A_TYPE], eax
    mov [ebp+A_ARRAY], eax
    mov [ebp+A_MIRROR], eax
    call read2
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    call read2
    mov [ebp+A_N], eax
    lea edx, [ebp+A_TYPE]
    mov ecx, ebx
    call @jbv_type_class@16
    test eax, eax
    jnz ra_ret
    mov eax, [ebp+A_TYPE]
    call implementation
    test eax, eax
    jnz ra_ret
    mov [ebp+A_IMPL], edx
    lea eax, [ebp+A_MIRROR]
    push eax
    mov edx, [ebp+A_TYPE]
    mov ecx, ebx
    call @jbv_mirror@12
    test eax, eax
    jnz ra_ret
    push 16
    push OFFSET n_object
    mov ecx, ebx
    call @jbv_find_class@12
    lea ecx, [ebp+A_ARRT]
    push ecx
    push 'L'
    mov edx, eax
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz ra_ret
    lea eax, [ebp+A_ARRAY]
    push eax
    mov eax, [ebp+A_IMPL]
    movzx eax, WORD PTR [eax+C_METHOD_COUNT]
    push eax
    mov edx, [ebp+A_ARRT]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz ra_ret
    push DWORD PTR [ebp+A_ARRAY]
    push ebx
    call jbv_retain
    add esp, 8
    ; the explicit values first: an overridden default must not be evaluated (it can
    ; mention a type no longer present in the application)
    mov DWORD PTR [ebp+A_I], 0
rx_pair:
    mov eax, [ebp+A_I]
    cmp eax, [ebp+A_N]
    jae rx_defaults
    call read2
    imul eax, eax, CP_SIZEOF
    add eax, [edi+C_POOL]
    mov ecx, [eax+CP_TEXT+TEXT_DATA]
    mov [ebp+A_KEY], ecx
    mov ecx, [eax+CP_TEXT+TEXT_SIZE]
    mov [ebp+A_KEY+4], ecx
    mov eax, [ebp+A_IMPL]
    movzx ecx, WORD PTR [eax+C_METHOD_COUNT]
    mov edx, [eax+C_METHODS]
    xor eax, eax
rx_find:
    cmp eax, ecx
    jae rx_skip
    push eax
    push ecx
    push edx
    push DWORD PTR [ebp+A_KEY+4]
    push DWORD PTR [ebp+A_KEY]
    push DWORD PTR [edx+M_NAME+TEXT_SIZE]
    push DWORD PTR [edx+M_NAME+TEXT_DATA]
    call @jbv_text_eq@16
    mov [ebp+A_ITEM], eax
    pop edx
    pop ecx
    pop eax
    cmp DWORD PTR [ebp+A_ITEM], 0
    jne rx_found
    inc eax
    add edx, M_SIZEOF
    jmp rx_find
rx_skip:
    push esi
    mov esi, [esi]
    call skip_value
    mov eax, esi
    pop esi
    mov [esi], eax
    jmp rx_next
rx_found:
    mov [ebp+A_J], eax
    push DWORD PTR [edx+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edx+M_DESCRIPTOR+TEXT_DATA]
    call @jbv_return_type@8
    lea ecx, [ebp+A_ITEM]
    push ecx
    push edx
    push eax
    push esi
    mov edx, edi
    mov ecx, ebx
    call @jbv_annotation_value@24
    test eax, eax
    jnz rx_end
    mov eax, [ebp+A_ARRAY]
    mov ecx, [ebp+A_J]
    mov edx, [ebp+A_ITEM]
    call store
rx_next:
    inc DWORD PTR [ebp+A_I]
    jmp rx_pair
rx_defaults:                            ; then each missing element's AnnotationDefault
    mov DWORD PTR [ebp+A_I], 0
rd_element:
    mov eax, [ebp+A_IMPL]
    movzx ecx, WORD PTR [eax+C_METHOD_COUNT]
    mov eax, [ebp+A_I]
    cmp eax, ecx
    jae rd_make
    push 0
    push esp
    mov edx, [ebp+A_ARRAY]
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    mov eax, [ebp+A_I]
    cmp DWORD PTR [ecx+eax*4+DATA0], 0
    jne rd_next
    mov edx, [ebp+A_IMPL]
    mov edx, [edx+C_METHODS]
    imul eax, eax, M_SIZEOF
    add edx, eax
    push edx
    push OFFSET s_default
    mov edx, [edx+M_ATTRIBUTES]
    mov ecx, [ebp+A_TYPE]
    call @jbv_attribute@12
    pop edx
    test eax, eax
    jz rd_next
    mov [ebp+A_J], eax
    push DWORD PTR [edx+M_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [edx+M_DESCRIPTOR+TEXT_DATA]
    call @jbv_return_type@8
    lea ecx, [ebp+A_ITEM]
    push ecx
    push edx
    push eax
    lea eax, [ebp+A_J]
    push eax
    mov edx, [ebp+A_TYPE]
    mov ecx, ebx
    call @jbv_annotation_value@24
    test eax, eax
    jnz rx_end
    mov eax, [ebp+A_ARRAY]
    mov ecx, [ebp+A_I]
    mov edx, [ebp+A_ITEM]
    call store
rd_next:
    inc DWORD PTR [ebp+A_I]
    jmp rd_element
rd_make:
    push DWORD PTR [ebp+A_REF]
    push 0
    mov edx, [ebp+A_IMPL]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz rx_end
    mov eax, [ebp+A_REF]
    push 0
    push esp
    mov edx, [eax]
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    mov eax, [ebp+A_MIRROR]
    mov [ecx+DATA0], eax
    mov eax, [ebp+A_ARRAY]
    mov [ecx+DATA0+4], eax
    xor eax, eax
rx_end:
    push eax
    push DWORD PTR [ebp+A_ARRAY]
    push ebx
    call jbv_release
    add esp, 8
    pop eax
ra_ret:
    mov esp, ebp
    pop ebp
    ret

; JbvStatus jbv_annotations(vm, owner, p, ref): a new Annotation[] from an annotations attribute (or none)
@jbv_annotations@16 PROC SYSCALL    ; ecx vm, edx owner, [ebp+8] p, [ebp+12] ref
    push ebp
    mov ebp, esp
    sub esp, 16
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    lea esi, [ebp+8]
    xor eax, eax
    cmp [esi], eax
    je @F
    call read2
@@:
    mov [ebp-12], eax                   ; n
    push 0
    mov edx, esp
    push 31
    push OFFSET n_annotation
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop edx
    test eax, eax
    jnz an_ret
    lea eax, [ebp-4]
    push eax
    push 'L'
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz an_ret
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp-12]
    mov edx, [ebp-4]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz an_ret
    mov eax, [ebp+12]
    push DWORD PTR [eax]
    push ebx
    call jbv_retain
    add esp, 8
    mov DWORD PTR [ebp-8], 0
an_item:
    mov eax, [ebp-8]
    cmp eax, [ebp-12]
    jae an_done
    lea eax, [ebp-16]
    call read_annotation
    test eax, eax
    jnz an_end
    mov eax, [ebp+12]
    mov eax, [eax]
    mov ecx, [ebp-8]
    mov edx, [ebp-16]
    call store
    inc DWORD PTR [ebp-8]
    jmp an_item
an_done:
    xor eax, eax
an_end:
    push eax
    mov eax, [ebp+12]
    push DWORD PTR [eax]
    push ebx
    call jbv_release
    add esp, 8
    pop eax
an_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_annotations@16 ENDP
END

; Classes and references: bootstrap, array classes, resolution and lazy loading, linking (superclass,
; interfaces, instance slots), assignability, method/field lookup with JVM interface
; rules, handle validation and host pins. Fastcall; ebx is the VM.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_free_class@8:PROC
EXTERN SYSCALL @jbv_prepare_method@4:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_find_field@20:PROC
EXTERN SYSCALL @jbv_text_eq@16:PROC
EXTERN SYSCALL @jbv_library_object@8:PROC
EXTERN SYSCALL @jbv_library_class@16:PROC
EXTERN SYSCALL @jbv_exception_name@8:PROC
EXTERN SYSCALL @jbv_exception_class@16:PROC
EXTERN SYSCALL @jbv_throw_detail@40:PROC
EXTERN jbv_archive_find:PROC
EXTERN jbv_parse_owned:PROC

S_OK        EQU 0
S_BAD_ARG   EQU 1
S_OOM       EQU 2
S_BAD_CLASS EQU 3
S_UNSUPPORTED EQU 6
S_NOT_FOUND EQU 7
S_LINKAGE   EQU 8
S_LIMIT     EQU 10
S_NULL      EQU 12
S_CAST      EQU 16
S_BAD_REF   EQU 17
F_STATIC    EQU 8
F_PRIVATE   EQU 2
F_FINAL     EQU 10h
F_NATIVE    EQU 100h
F_INTERFACE EQU 200h
F_ABSTRACT  EQU 400h

.const
n_object     DB 'java/lang/Object'
n_cloneable  DB 'java/lang/Cloneable'
n_serial     DB 'java/io/Serializable'
n_closeable  DB 'java/lang/AutoCloseable'
n_close      DB 'close'
n_init       DB '<init>'
n_void       DB '()V'
n_ncdfe      DB 'java/lang/NoClassDefFoundError', 0
boot_names   DD n_object, 16, n_cloneable, 19, n_serial, 20, n_closeable, 23
primitives   DB 'ZBCSIJFD'

.code
@jbv_reference_type@8 PROC SYSCALL  ; a descriptor of a reference: L... or [...
    xor eax, eax
    cmp WORD PTR [esp+8], 0
    je @F
    mov ecx, [esp+4]
    mov cl, [ecx]
    cmp cl, 'L'
    je rt_yes
    cmp cl, '['
    jne @F
rt_yes:
    inc eax
@@:
    ret 8
@jbv_reference_type@8 ENDP

; ---- the four classes everything starts from: Object, Cloneable, Serializable, AutoCloseable
@jbv_bootstrap@4 PROC SYSCALL
    push ebx
    push esi
    push edi
    mov ebx, ecx
    xor edi, edi                        ; i
    xor esi, esi                        ; root (Object)
bs_class:
    mov edx, C_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz bs_oom
    mov ecx, [boot_names+edi*8]
    mov [eax+C_NAME+TEXT_DATA], ecx
    mov ecx, [boot_names+edi*8+4]
    mov [eax+C_NAME+TEXT_SIZE], cx
    mov cx, 1 or F_INTERFACE or F_ABSTRACT
    test edi, edi
    jnz @F
    mov cx, 1
    mov [ebx+VM_OBJECT_CLASS], eax
@@:
    mov [eax+C_FLAGS], cx
    mov BYTE PTR [eax+C_LINK_STATE], 2
    mov BYTE PTR [eax+C_INIT_STATE], 2
    mov [eax+C_SUPER], esi
    mov ecx, [ebx+VM_CLASSES]
    mov [eax+C_NEXT], ecx
    mov [ebx+VM_CLASSES], eax
    test edi, edi
    jz @F
    cmp edi, 3
    jne bs_next
@@:
    test edi, edi
    jnz @F
    mov esi, eax
@@:
    push eax                            ; Object.<init> (intrinsic) or AutoCloseable.close (abstract)
    mov edx, M_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    pop ecx
    test eax, eax
    jz bs_oom
    mov [ecx+C_METHODS], eax
    mov WORD PTR [ecx+C_METHOD_COUNT], 1
    mov DWORD PTR [eax+M_NAME+TEXT_DATA], OFFSET n_init
    mov WORD PTR [eax+M_NAME+TEXT_SIZE], 6
    mov WORD PTR [eax+M_FLAGS], 1 or F_NATIVE
    mov BYTE PTR [eax+M_INTRINSIC], 1
    cmp edi, 3
    jne @F
    mov DWORD PTR [eax+M_NAME+TEXT_DATA], OFFSET n_close
    mov WORD PTR [eax+M_NAME+TEXT_SIZE], 5
    mov WORD PTR [eax+M_FLAGS], 1 or F_ABSTRACT
    mov BYTE PTR [eax+M_INTRINSIC], 0
@@:
    mov DWORD PTR [eax+M_DESCRIPTOR+TEXT_DATA], OFFSET n_void
    mov WORD PTR [eax+M_DESCRIPTOR+TEXT_SIZE], 3
    mov ecx, eax
    call @jbv_prepare_method@4
bs_next:
    inc edi
    cmp edi, 4
    jb bs_class
    mov edx, esi
    mov ecx, ebx
    call @jbv_library_object@8
    jmp bs_ret
bs_oom:
    mov eax, S_OOM
bs_ret:
    pop edi
    pop esi
    pop ebx
    ret
@jbv_bootstrap@4 ENDP

; an array class by element kind ('L': of the component class), made once; its name follows it
@jbv_array_class@16 PROC SYSCALL    ; ecx vm, edx component, [esp+4] kind, [esp+8] out
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    mov al, [esp+16]                    ; kind
    mov ecx, [ebx+VM_CLASSES]
ac_find:
    test ecx, ecx
    jz ac_new
    cmp [ecx+C_ARRAY_KIND], al
    jne @F
    cmp [ecx+C_COMPONENT], esi
    je ac_out
@@:
    mov ecx, [ecx+C_NEXT]
    jmp ac_find
ac_new:
    mov edi, 2                          ; the name length: [k, [Lname; or [[...
    cmp al, 'L'
    jne ac_alloc
    mov eax, S_BAD_CLASS
    test esi, esi
    jz ac_ret
    movzx edi, WORD PTR [esi+C_NAME+TEXT_SIZE]
    inc edi
    cmp BYTE PTR [esi+C_ARRAY_KIND], 0
    jne @F
    add edi, 2
@@:
    cmp edi, 0FFFFh
    ja ac_ret
ac_alloc:
    lea edx, [edi+C_SIZEOF]
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz ac_oom
    mov edx, eax                        ; edx = the class
    lea eax, [edx+C_SIZEOF]
    mov [edx+C_NAME+TEXT_DATA], eax
    mov [edx+C_NAME+TEXT_SIZE], di
    mov BYTE PTR [eax], '['
    mov cl, [esp+16]
    mov [edx+C_ARRAY_KIND], cl
    mov [edx+C_COMPONENT], esi
    cmp cl, 'L'
    je @F
    mov [eax+1], cl
    jmp ac_named
@@:
    push esi
    push edi
    push edx
    lea edi, [eax+1]
    cmp BYTE PTR [esi+C_ARRAY_KIND], 0
    jne @F
    mov BYTE PTR [edi], 'L'
    inc edi
@@:
    movzx ecx, WORD PTR [esi+C_NAME+TEXT_SIZE]
    mov esi, [esi+C_NAME+TEXT_DATA]
    rep movsb
    pop edx
    mov eax, edi
    pop edi
    pop esi
    cmp BYTE PTR [esi+C_ARRAY_KIND], 0
    jne ac_named
    mov BYTE PTR [eax], ';'
ac_named:
    mov eax, [ebx+VM_OBJECT_CLASS]
    mov [edx+C_SUPER], eax
    mov WORD PTR [edx+C_FLAGS], 1 or F_FINAL
    mov BYTE PTR [edx+C_LINK_STATE], 2
    mov BYTE PTR [edx+C_INIT_STATE], 2
    mov eax, [ebx+VM_CLASSES]
    mov [edx+C_NEXT], eax
    mov [ebx+VM_CLASSES], edx
    mov ecx, edx
ac_out:
    mov eax, [esp+20]
    mov [eax], ecx
    xor eax, eax
    jmp ac_ret
ac_oom:
    mov eax, S_OOM
ac_ret:
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_array_class@16 ENDP

; a class not loaded yet: the built-in library, else the application JAR
@jbv_lazy_class@16 PROC SYSCALL     ; ecx vm, edx out, [esp+4] name
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    push DWORD PTR [esp+20]
    push DWORD PTR [esp+20]
    call @jbv_library_class@16
    cmp eax, S_NOT_FOUND
    jne lz_ret
    cmp DWORD PTR [ebx+VM_APP], 0
    je lz_ret
    push 0                              ; size, image, then the class
    push 0
    push 0
    lea eax, [esp+8]
    push eax
    lea eax, [esp+8]
    push eax
    push DWORD PTR [esp+40]
    push DWORD PTR [esp+40]
    lea eax, [ebx+VM_APP]
    push eax
    call jbv_archive_find
    add esp, 20
    test eax, eax
    jnz lz_pop
    mov eax, esp
    push eax
    push DWORD PTR [esp+12]
    push DWORD PTR [esp+12]
    push ebx
    call jbv_parse_owned
    add esp, 16
    test eax, eax
    jnz lz_pop
    mov esi, [esp]                      ; the class
    push DWORD PTR [esp+32]
    push DWORD PTR [esp+32]
    push DWORD PTR [esi+C_NAME+TEXT_SIZE]
    push DWORD PTR [esi+C_NAME+TEXT_DATA]
    call @jbv_text_eq@16
    test eax, eax
    jnz @F
    mov edx, esi
    mov ecx, ebx
    call @jbv_free_class@8
    mov eax, S_LINKAGE
    jmp lz_pop
@@:
    mov eax, [ebx+VM_CLASSES]
    mov [esi+C_NEXT], eax
    mov [ebx+VM_CLASSES], esi
    mov [edi], esi
    push 0
    mov edx, esi
    mov ecx, ebx
    call @jbv_link@12
lz_pop:
    add esp, 12
lz_ret:
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_lazy_class@16 ENDP

; a class by name: loaded, built-in exception, lazily loaded, or an array of one
@jbv_resolve_class@16 PROC SYSCALL  ; ecx vm, edx out, [esp+4] name
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    mov esi, [esp+16]                   ; name data
    push DWORD PTR [esp+20]
    push esi
    call @jbv_find_class@12
    test eax, eax
    jz @F
    mov [edi], eax
    push 0
    mov edx, eax
    mov ecx, ebx
    call @jbv_link@12
    jmp rc_ret
@@:
    push DWORD PTR [esp+20]
    push esi
    call @jbv_exception_name@8
    test eax, eax
    jz @F
    push DWORD PTR [esp+20]
    push esi
    mov edx, edi
    mov ecx, ebx
    call @jbv_exception_class@16
    jmp rc_ret
@@:
    push DWORD PTR [esp+20]
    push esi
    mov edx, edi
    mov ecx, ebx
    call @jbv_lazy_class@16
    cmp eax, S_NOT_FOUND
    jne rc_ret
    movzx ecx, WORD PTR [esp+20]        ; an array: [k or [L...; or [[...
    test ecx, ecx
    jz rc_ret
    cmp BYTE PTR [esi], '['
    jne rc_ret
    mov eax, S_BAD_CLASS
    xor edx, edx
@@:
    cmp edx, ecx
    jae rc_ret
    cmp BYTE PTR [esi+edx], '['
    jne @F
    inc edx
    jmp @B
@@:
    cmp edx, 255
    ja rc_ret
    cmp ecx, 2
    jne rc_component
    mov al, [esi+1]                     ; a primitive array
    push edi
    mov edi, OFFSET primitives
    mov ecx, 8
    repne scasb
    pop edi
    mov eax, S_BAD_CLASS
    jne rc_ret
    push edi
    movzx eax, BYTE PTR [esi+1]
    push eax
    xor edx, edx
    mov ecx, ebx
    call @jbv_array_class@16
    jmp rc_ret
rc_component:
    inc esi                             ; part = name[1..]
    dec ecx
    cmp BYTE PTR [esi], 'L'
    jne @F
    cmp ecx, 3
    jb rc_ret
    cmp BYTE PTR [esi+ecx-1], ';'
    jne rc_ret
    inc esi
    sub ecx, 2
    jmp rc_part
@@:
    cmp BYTE PTR [esi], '['
    jne rc_ret
rc_part:
    push 0                              ; the component
    mov edx, esp
    push ecx
    push esi
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop edx
    test eax, eax
    jnz rc_ret
    push edi
    push 'L'
    mov ecx, ebx
    call @jbv_array_class@16
rc_ret:
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_resolve_class@16 ENDP

; the class of a Class constant, resolved once (cached in the entry's text pointer)
@jbv_class_constant@16 PROC SYSCALL ; ecx vm, edx class, [esp+4] index, [esp+8] out
    push ebx
    push esi
    push edi
    mov ebx, ecx
    movzx esi, WORD PTR [esp+16]
    imul esi, esi, CP_SIZEOF
    add esi, [edx+C_POOL]               ; esi = the entry
    mov edi, [esp+20]
    mov eax, [esi+CP_TEXT+TEXT_DATA]
    test eax, eax
    jz @F
    mov [edi], eax
    xor eax, eax
    jmp cc_ret
@@:
    movzx eax, WORD PTR [esi+CP_A]
    imul eax, eax, CP_SIZEOF
    add eax, [edx+C_POOL]               ; eax = its name
    push eax
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    mov edx, edi
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop edx
    cmp eax, S_NOT_FOUND
    jne @F
    push eax                            ; NoClassDefFoundError with the name
    push 0
    push 0
    push 0
    push 0
    push 0
    push DWORD PTR [edx+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [edx+CP_TEXT+TEXT_DATA]
    mov edx, OFFSET n_ncdfe
    mov ecx, ebx
    call @jbv_throw_detail@40
    jmp cc_ret
@@:
    test eax, eax
    jnz cc_ret
    mov ecx, [edi]
    mov [esi+CP_TEXT+TEXT_DATA], ecx
cc_ret:
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_class_constant@16 ENDP

; a class loaded by name if not yet: ecx/edx = the JbvText, [edi] = where -> eax = the status
find_or_load:
    push edx
    push ecx
    push edx
    push ecx
    mov ecx, ebx
    call @jbv_find_class@12
    pop ecx
    pop edx
    mov [edi], eax
    test eax, eax
    jnz fl_ok
    push edx
    push ecx
    mov edx, edi
    mov ecx, ebx
    call @jbv_lazy_class@16
    cmp eax, S_NOT_FOUND
    jne fl_ret
fl_ok:
    xor eax, eax
fl_ret:
    ret
; superclass and interfaces linked (depth-limited), instance slots laid out
L_DEPTH EQU 8
@jbv_link@12 PROC SYSCALL           ; ecx vm, edx class, [esp+4] depth
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    xor eax, eax
    cmp BYTE PTR [esi+C_LINK_STATE], 2
    je lk_ret
    mov eax, S_LINKAGE
    cmp BYTE PTR [esi+C_LINK_STATE], 1
    je lk_ret
    cmp DWORD PTR [ebp+L_DEPTH], 256
    jae lk_ret
    mov BYTE PTR [esi+C_LINK_STATE], 1
    cmp WORD PTR [esi+C_SUPER_NAME+TEXT_SIZE], 0
    je lk_fail
    lea edi, [esi+C_SUPER]
    mov ecx, [esi+C_SUPER_NAME+TEXT_DATA]
    movzx edx, WORD PTR [esi+C_SUPER_NAME+TEXT_SIZE]
    call find_or_load
    test eax, eax
    jnz lk_fail
    cmp DWORD PTR [edi], 0
    jne lk_super
    push DWORD PTR [esi+C_SUPER_NAME+TEXT_SIZE]
    push DWORD PTR [esi+C_SUPER_NAME+TEXT_DATA]
    call @jbv_exception_name@8
    test eax, eax
    mov eax, S_NOT_FOUND
    jz lk_fail
    push DWORD PTR [esi+C_SUPER_NAME+TEXT_SIZE]
    push DWORD PTR [esi+C_SUPER_NAME+TEXT_DATA]
    mov edx, edi
    mov ecx, ebx
    call @jbv_exception_class@16
    test eax, eax
    jnz lk_fail
lk_super:
    mov ecx, [edi]
    mov eax, S_LINKAGE
    test WORD PTR [ecx+C_FLAGS], F_INTERFACE or F_FINAL
    jnz lk_fail
    cmp BYTE PTR [ecx+C_ARRAY_KIND], 0
    jne lk_fail
    call lk_child
    jnz lk_fail
    movzx eax, WORD PTR [esi+C_INTERFACE_COUNT]
    test eax, eax
    jz lk_slots
    cmp DWORD PTR [esi+C_INTERFACES], 0
    jne @F
    lea edx, [eax*4]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [esi+C_INTERFACES], eax
    test eax, eax
    mov eax, S_OOM
    jz lk_fail
@@:
    push 0                              ; [esp] = i
lk_interface:
    mov eax, [esp]
    cmp ax, WORD PTR [esi+C_INTERFACE_COUNT]
    jae lk_interfaces_done
    mov edx, [esi+C_INTERFACE_INDICES]
    movzx edx, WORD PTR [edx+eax*2]
    xchg dl, dh
    imul edx, edx, CP_SIZEOF
    add edx, [esi+C_POOL]
    movzx edx, WORD PTR [edx+CP_A]
    imul edx, edx, CP_SIZEOF
    add edx, [esi+C_POOL]               ; its name
    mov edi, [esi+C_INTERFACES]
    lea edi, [edi+eax*4]
    mov ecx, [edx+CP_TEXT+TEXT_DATA]
    movzx edx, WORD PTR [edx+CP_TEXT+TEXT_SIZE]
    call find_or_load
    test eax, eax
    jnz lk_fail_pop
    mov ecx, [edi]
    mov eax, S_NOT_FOUND
    test ecx, ecx
    jz lk_fail_pop
    mov eax, S_LINKAGE
    test WORD PTR [ecx+C_FLAGS], F_INTERFACE
    jz lk_fail_pop
    call lk_child
    jnz lk_fail_pop
    inc DWORD PTR [esp]
    jmp lk_interface
lk_fail_pop:
    add esp, 4
    jmp lk_fail
lk_interfaces_done:
    add esp, 4
lk_slots:                               ; instance fields after the superclass's
    mov eax, [esi+C_SUPER]
    mov edx, [eax+C_INSTANCE_SLOTS]
    movzx ecx, WORD PTR [esi+C_FIELD_COUNT]
    mov edi, [esi+C_FIELDS]
    jecxz lk_done
lk_field:
    test WORD PTR [edi+FIELD_FLAGS], F_STATIC
    jnz lk_next
    mov eax, [edi+FIELD_DESCRIPTOR+TEXT_DATA]
    mov al, [eax]
    cmp al, 'L'
    je lk_one
    cmp al, '['
    je lk_one
    cmp WORD PTR [edi+FIELD_DESCRIPTOR+TEXT_SIZE], 1
    jne lk_unsupported
    cmp al, 'J'
    je lk_two
    cmp al, 'D'
    je lk_two
    push edi
    push ecx
    mov edi, OFFSET primitives
    mov ecx, 8
    repne scasb
    pop ecx
    pop edi
    jne lk_unsupported
lk_one:
    mov [edi+FIELD_SLOT], edx
    inc edx
    jmp lk_next
lk_two:
    mov [edi+FIELD_SLOT], edx
    add edx, 2
lk_next:
    add edi, FIELD_SIZEOF
    loop lk_field
lk_done:
    mov [esi+C_INSTANCE_SLOTS], edx
    mov BYTE PTR [esi+C_LINK_STATE], 2
    xor eax, eax
    jmp lk_ret
lk_unsupported:
    mov eax, S_UNSUPPORTED
lk_fail:
    mov BYTE PTR [esi+C_LINK_STATE], 0
lk_ret:
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret 4
lk_child:                               ; ecx = a class to link at depth + 1 -> ZF = linked
    mov edx, [ebp+L_DEPTH]
    inc edx
    push edx
    mov edx, ecx
    mov ecx, ebx
    call @jbv_link@12
    test eax, eax
    ret
@jbv_link@12 ENDP

; from is the same as, a subclass or implementation of, or an array assignable to `to`
@jbv_assignable@8 PROC SYSCALL      ; ecx from, edx to
    push esi
    push edi
    mov esi, ecx
    mov edi, edx
as_again:
    cmp esi, edi
    je as_yes
    cmp BYTE PTR [esi+C_PRIMITIVE], 0
    jne as_no
    cmp BYTE PTR [edi+C_PRIMITIVE], 0
    jne as_no
    mov al, [esi+C_ARRAY_KIND]
    test al, al
    jz as_supers
    mov ah, [edi+C_ARRAY_KIND]
    test ah, ah
    jz as_array_object
    cmp ax, 'LL'
    jne as_no
    mov esi, [esi+C_COMPONENT]          ; arrays of references: by component
    mov edi, [edi+C_COMPONENT]
    jmp as_again
as_array_object:                        ; arrays are Cloneable and Serializable too
    lea eax, [edi+C_NAME]
    mov ecx, OFFSET n_cloneable
    mov edx, 19
    call as_named
    je as_yes
    mov ecx, OFFSET n_serial
    mov edx, 20
    call as_named
    je as_yes
as_supers:
    movzx ecx, WORD PTR [esi+C_INTERFACE_COUNT]
    jecxz as_super
    mov eax, [esi+C_INTERFACES]
@@:
    push ecx
    push eax
    mov ecx, [eax]
    mov edx, edi
    call @jbv_assignable@8
    test eax, eax
    pop eax
    pop ecx
    jnz as_yes
    add eax, 4
    loop @B
as_super:
    mov esi, [esi+C_SUPER]
    test esi, esi
    jnz as_again
as_no:
    xor eax, eax
    jmp @F
as_yes:
    mov eax, 1
@@:
    pop edi
    pop esi
    ret
as_named:                               ; ZF = the JbvText at eax is ecx, edx
    cmp dx, WORD PTR [eax+TEXT_SIZE]
    jne @F
    push esi
    push edi
    mov esi, [eax+TEXT_DATA]
    mov edi, ecx
    mov ecx, edx
    repe cmpsb
    pop edi
    pop esi
@@:
    ret
@jbv_assignable@8 ENDP

; ---- method lookup: the class, its superclasses, then the maximally specific interface method
; Frames below keep the name and descriptor at [ebp+8], [ebp+16] (as JbvTexts).
LM_NAME EQU 8
LM_DESC EQU 16
find_in:                                ; ecx = class -> eax = its method name+descriptor, or 0
    push DWORD PTR [ebp+LM_DESC+4]
    push DWORD PTR [ebp+LM_DESC]
    push DWORD PTR [ebp+LM_NAME+4]
    push DWORD PTR [ebp+LM_NAME]
    call @jbv_find_method@20
    ret
virtual_in:                             ; eax = method -> ZF = it is neither static nor private
    test WORD PTR [eax+M_FLAGS], F_STATIC or F_PRIVATE
    ret
; a declaration in a strict subinterface of candidate suppresses it (traversal order chooses nothing)
; esi = root, edi = candidate -> eax = 1 if overridden
override:
    cmp esi, edi
    je ov_children
    test WORD PTR [esi+C_FLAGS], F_INTERFACE
    jz ov_children
    mov ecx, esi
    mov edx, edi
    call @jbv_assignable@8
    test eax, eax
    jz ov_children
    mov ecx, esi
    call find_in
    test eax, eax
    jz ov_children
    call virtual_in
    jz ov_yes
ov_children:
    movzx ecx, WORD PTR [esi+C_INTERFACE_COUNT]
    jecxz ov_super
    mov eax, [esi+C_INTERFACES]
@@:
    push esi
    push ecx
    push eax
    mov esi, [eax]
    call override
    mov edx, eax
    pop eax
    pop ecx
    pop esi
    test edx, edx
    jnz ov_yes
    add eax, 4
    loop @B
ov_super:
    mov esi, [esi+C_SUPER]
    test esi, esi
    jnz override
    xor eax, eax
    ret
ov_yes:
    mov eax, 1
    ret
; the interface methods of class c (eax) and above; [ebp-4] owner, [ebp-8] selected; root in [ebp-12]
; -> eax = 0 if two unrelated defaults conflict
IM_OWNER EQU -4
IM_SEL   EQU -8
IM_ROOT  EQU -12
interface_method:
    push esi
    push edi
    mov edi, eax                        ; edi = c
    test WORD PTR [edi+C_FLAGS], F_INTERFACE
    jz im_children
    mov ecx, edi
    call find_in
    test eax, eax
    jz im_children
    call virtual_in
    jnz im_children
    push eax
    mov esi, [ebp+IM_ROOT]
    call override
    mov edx, eax
    pop eax
    test edx, edx
    jnz im_children
    mov ecx, [ebp+IM_SEL]
    jecxz im_take
    cmp [ebp+IM_OWNER], edi
    je @F
    test WORD PTR [ecx+M_FLAGS], F_ABSTRACT
    jnz @F
    test WORD PTR [eax+M_FLAGS], F_ABSTRACT
    jz im_conflict
@@:
    test WORD PTR [ecx+M_FLAGS], F_ABSTRACT
    jz im_children
im_take:
    mov [ebp+IM_SEL], eax
    mov [ebp+IM_OWNER], edi
im_children:
    movzx ecx, WORD PTR [edi+C_INTERFACE_COUNT]
    jecxz im_super
    mov esi, [edi+C_INTERFACES]
@@:
    push ecx
    mov eax, [esi]
    call interface_method
    pop ecx
    test eax, eax
    jz im_ret
    add esi, 4
    loop @B
im_super:
    mov eax, [edi+C_SUPER]
    test eax, eax
    jz @F
    call interface_method
    jmp im_ret
@@:
    mov eax, 1
im_ret:
    pop edi
    pop esi
    ret
im_conflict:
    xor eax, eax
    jmp im_ret
@jbv_lookup_method@20 PROC SYSCALL  ; ecx = &owner, name and descriptor on the stack
    push ebp
    mov ebp, esp
    sub esp, 12
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, [ebx]                      ; root
    mov [ebp+IM_ROOT], edi
    mov ecx, edi
    call find_in
    test eax, eax
    jnz lm_ret
    cmp WORD PTR [ebp+LM_NAME+4], 6     ; <init> is never inherited
    jne @F
    mov ecx, [ebp+LM_NAME]
    cmp DWORD PTR [ecx], 'ini<'
    jne @F
    cmp WORD PTR [ecx+4], '>t'
    je lm_ret
@@:
    mov esi, [edi+C_SUPER]
lm_super:
    test esi, esi
    jz lm_interfaces
    mov ecx, esi
    call find_in
    test eax, eax
    jz lm_up
    test WORD PTR [edi+C_FLAGS], F_INTERFACE
    jz lm_found                         ; an interface takes only public instance Object methods
    test WORD PTR [eax+M_FLAGS], 1
    jz lm_up
    test WORD PTR [eax+M_FLAGS], F_STATIC
    jz lm_found
lm_up:
    mov esi, [esi+C_SUPER]
    jmp lm_super
lm_found:
    mov [ebx], esi
    jmp lm_ret
lm_interfaces:
    mov DWORD PTR [ebp+IM_SEL], 0
    mov [ebp+IM_OWNER], edi
    mov eax, edi
    call interface_method
    test eax, eax
    jnz @F
    mov [ebx], eax
    jmp lm_ret
@@:
    mov eax, [ebp+IM_OWNER]
    mov [ebx], eax
    mov eax, [ebp+IM_SEL]
lm_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 16
@jbv_lookup_method@20 ENDP
; a field in the class, its interfaces, then its superclass
@jbv_lookup_field@20 PROC SYSCALL   ; ecx = &owner, name and descriptor on the stack
    push ebp
    mov ebp, esp
    push ebx
    push esi
    mov ebx, ecx
    mov esi, [ebx]
    push DWORD PTR [ebp+20]
    push DWORD PTR [ebp+16]
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    mov ecx, esi
    call @jbv_find_field@20
    test eax, eax
    jnz lf_ret
    movzx ecx, WORD PTR [esi+C_INTERFACE_COUNT]
    xor edx, edx
lf_interface:
    cmp edx, ecx
    jae lf_super
    mov eax, [esi+C_INTERFACES]
    mov eax, [eax+edx*4]
    call lf_parent
    jnz lf_ret
    inc edx
    jmp lf_interface
lf_super:
    mov eax, [esi+C_SUPER]
    test eax, eax
    jz lf_ret
    call lf_parent
lf_ret:
    pop esi
    pop ebx
    pop ebp
    ret 16
lf_parent:                              ; eax = a class -> eax = the field there (owner set), ZF = none
    push ecx
    push edx
    push eax
    mov ecx, esp
    push DWORD PTR [ebp+20]
    push DWORD PTR [ebp+16]
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call @jbv_lookup_field@20
    pop ecx
    test eax, eax
    jz @F
    mov [ebx], ecx
@@:
    pop edx
    pop ecx
    test eax, eax
    ret
@jbv_lookup_field@20 ENDP

; ---- references: generation << 24 | handle index
@jbv_object@12 PROC SYSCALL         ; ecx vm, edx ref, [esp+4] out: a live handle of its generation
    mov eax, S_NULL
    test edx, edx
    jz ob_ret
    mov eax, S_BAD_REF
    js ob_ret
    push esi
    mov esi, edx
    and esi, 0FFFFFFh
    jz ob_bad
    cmp esi, [ecx+VM_HANDLE_CAPACITY]
    ja ob_bad
    push edx
    mov edx, [ecx+VM_USED_MAP]
    bt [edx], esi
    pop edx
    jnc ob_bad
    shr edx, 24
    mov eax, [ecx+VM_GENERATIONS]
    cmp dl, [eax+esi]
    mov eax, S_BAD_REF
    jne ob_bad
    mov eax, [ecx+VM_HANDLES]
    mov eax, [eax+esi*4]
    mov edx, [esp+8]
    mov [edx], eax
    xor eax, eax
ob_bad:
    pop esi
ob_ret:
    ret 4
@jbv_object@12 ENDP
; a reference (0 allowed) whose class is assignable to the descriptor's
@jbv_check_reference@16 PROC SYSCALL ; ecx vm, edx ref, [esp+4] descriptor
    xor eax, eax
    test edx, edx
    jz cr_ret
    push ebx
    push esi
    mov ebx, ecx
    push 0
    push esp
    call @jbv_object@12
    pop esi                             ; the object
    test eax, eax
    jnz cr_pop
    mov esi, [esi]                      ; its class (resolving may move objects)
    mov ecx, [esp+12]
    movzx edx, WORD PTR [esp+16]
    cmp edx, 2
    jbe @F
    cmp BYTE PTR [ecx], 'L'
    jne @F
    cmp BYTE PTR [ecx+edx-1], ';'
    jne @F
    inc ecx
    sub edx, 2
    jmp cr_resolve
@@:
    mov eax, S_BAD_CLASS
    test edx, edx
    jz cr_pop
    cmp BYTE PTR [ecx], '['
    jne cr_pop
cr_resolve:
    push 0
    mov eax, esp
    push edx
    push ecx
    mov edx, eax
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop edx
    test eax, eax
    jnz cr_pop
    mov ecx, esi
    call @jbv_assignable@8
    test eax, eax
    mov eax, 0
    jnz cr_pop
    mov eax, S_CAST
cr_pop:
    pop esi
    pop ebx
cr_ret:
    ret 8
@jbv_check_reference@16 ENDP

; ---- pins: host retain counts in a small unsorted table
find_pin:                               ; edx = handle index -> eax = its pin, or 0
    mov ecx, [ebx+VM_PIN_COUNT]
    mov eax, [ebx+VM_PINS]
    lea eax, [eax+ecx*8-8]
@@:
    test ecx, ecx
    jz fp_none
    cmp [eax], edx
    je fp_ret
    sub eax, 8
    dec ecx
    jmp @B
fp_none:
    xor eax, eax
fp_ret:
    ret
; edx = ref -> eax = the status, edx = its handle index (ebx = vm)
pin_ref:
    mov ecx, ebx
    push edx
    push 0
    push esp
    call @jbv_object@12
    pop ecx
    pop edx
    and edx, 0FFFFFFh
    test eax, eax
    ret
jbv_retain PROC EXPORT              ; (vm, ref)
    push ebx
    mov ebx, [esp+8]
    mov edx, [esp+12]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz pn_ret
    xor eax, eax
    test edx, edx
    jz pn_ret
    call pin_ref
    jnz pn_ret
    call find_pin
    test eax, eax
    jz @F
    inc DWORD PTR [eax+4]
    jnz pn_ok
    dec DWORD PTR [eax+4]               ; at UINT32_MAX already
    mov eax, S_LIMIT
    jmp pn_ret
@@:
    mov eax, [ebx+VM_PIN_COUNT]
    cmp eax, [ebx+VM_PIN_CAPACITY]
    jne pn_add
    push esi                            ; grow: twice (16 first)
    push edi
    push edx
    lea esi, [eax*2]
    test esi, esi
    jnz @F
    mov esi, 16
@@:
    lea edx, [esi*8]
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz pn_oom
    push esi
    mov edi, eax
    mov esi, [ebx+VM_PINS]
    mov ecx, [ebx+VM_PIN_COUNT]
    shl ecx, 1
    rep movsd
    mov edx, [ebx+VM_PINS]
    mov [ebx+VM_PINS], eax
    mov ecx, ebx
    call @jbv_free@8
    pop esi
    mov [ebx+VM_PIN_CAPACITY], esi
    pop edx
    pop edi
    pop esi
pn_add:
    mov eax, [ebx+VM_PIN_COUNT]
    mov ecx, [ebx+VM_PINS]
    mov [ecx+eax*8], edx
    mov DWORD PTR [ecx+eax*8+4], 1
    inc DWORD PTR [ebx+VM_PIN_COUNT]
pn_ok:
    xor eax, eax
pn_ret:
    pop ebx
    ret
pn_oom:
    pop edx
    pop edi
    pop esi
    mov eax, S_OOM
    pop ebx
    ret
jbv_retain ENDP
jbv_release PROC EXPORT             ; (vm, ref)
    push ebx
    mov ebx, [esp+8]
    mov edx, [esp+12]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz rl_ret
    xor eax, eax
    test edx, edx
    jz rl_ret
    call pin_ref
    jnz rl_ret
    call find_pin
    test eax, eax
    jz rl_bad
    dec DWORD PTR [eax+4]
    jnz rl_ok
    dec DWORD PTR [ebx+VM_PIN_COUNT]    ; the last one takes its place
    mov ecx, [ebx+VM_PIN_COUNT]
    mov edx, [ebx+VM_PINS]
    mov ecx, [edx+ecx*8]
    mov [eax], ecx
    mov ecx, [ebx+VM_PIN_COUNT]
    mov ecx, [edx+ecx*8+4]
    mov [eax+4], ecx
rl_ok:
    xor eax, eax
rl_ret:
    pop ebx
    ret
rl_bad:
    mov eax, S_BAD_REF
    pop ebx
    ret
jbv_release ENDP
END

; VM basics for x86 (vm.c is the reference and serves x64): accounted allocation,
; text comparison, class/method/field lookup, freeing classes. Same names as the C.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
PUBLIC jbv_status_string

.const
; jbv_status_string: the texts in status order (0..17, then 18, 19, 21, 22)
statuses LABEL BYTE
    DB 'ok', 0
    DB 'bad argument', 0
    DB 'out of memory', 0
    DB 'malformed class or bytecode', 0
    DB 'unsupported class version (requires non-preview Java 25)', 0
    DB 'invokedynamic is disabled', 0
    DB 'feature is not implemented in this slice', 0
    DB 'class or member not found', 0
    DB 'linkage or class initialization error', 0
    DB 'integer division by zero', 0
    DB 'execution resource limit exceeded', 0
    DB 'VM is executing', 0
    DB 'null reference', 0
    DB 'array index out of bounds', 0
    DB 'negative array size', 0
    DB 'incompatible array element type', 0
    DB 'incompatible reference type', 0
    DB 'invalid or stale reference handle', 0
    DB 'monitor is not owned by this execution thread', 0
    DB 'illegal state', 0
    DB 'unknown status', 0
    DB 'native operation failed', 0
    DB 'uncaught Java exception', 0
    DB 'unknown status', 0

.code
@jbv_u16@4 PROC SYSCALL
    movzx eax, WORD PTR [ecx]
    xchg al, ah
    ret
@jbv_u16@4 ENDP
@jbv_u32@4 PROC SYSCALL
    mov eax, [ecx]
    bswap eax
    ret
@jbv_u32@4 ENDP

; Blocks carry their size in an 8-byte header and come zeroed; the total limit counts them.
@jbv_alloc@8 PROC SYSCALL           ; ecx vm, edx bytes
    push ebx
    push edi
    mov ebx, ecx
    test edx, edx
    jnz @F
    inc edx
@@:
    mov edi, edx
    add edx, 8
    jc al_none
    mov eax, [ebx+VM_MAX_MEMORY]
    sub eax, [ebx+VM_MEMORY_USED]
    cmp edx, eax
    ja al_none
    push edx
    push edx
    push DWORD PTR [ebx+VM_ALLOC_USER]
    call DWORD PTR [ebx+VM_ALLOC]
    add esp, 8
    pop edx
    test eax, eax
    jz al_none
    mov [eax], edx
    add edx, [ebx+VM_MEMORY_USED]
    mov [ebx+VM_MEMORY_USED], edx
    cmp edx, [ebx+VM_MEMORY_PEAK]
    jbe @F
    mov [ebx+VM_MEMORY_PEAK], edx
@@:
    lea edx, [eax+8]
    mov ecx, edi
    mov edi, edx
    xor eax, eax
    rep stosb
    mov eax, edx
    pop edi
    pop ebx
    ret
al_none:
    xor eax, eax
    pop edi
    pop ebx
    ret
@jbv_alloc@8 ENDP
@jbv_free@8 PROC SYSCALL            ; ecx vm, edx block (0: nothing)
    test edx, edx
    jz @F
    sub edx, 8
    mov eax, [edx]
    sub [ecx+VM_MEMORY_USED], eax
    push edx
    push DWORD PTR [ecx+VM_ALLOC_USER]
    call DWORD PTR [ecx+VM_FREE]
    add esp, 8
@@:
    ret
@jbv_free@8 ENDP

; JbvText of a C string (at most 65535 bytes): eax = data, edx = size
@jbv_text@4 PROC SYSCALL
    mov eax, ecx
    or edx, -1
@@:
    inc edx
    cmp edx, 0FFFFh
    je @F
    cmp BYTE PTR [eax+edx], 0
    jne @B
@@:
    ret
@jbv_text@4 ENDP
; texts a and b on the stack -> 1 if equal
@jbv_text_eq@16 PROC SYSCALL
    push esi
    push edi
    xor eax, eax
    movzx ecx, WORD PTR [esp+16]
    cmp cx, WORD PTR [esp+24]
    jne @F
    mov esi, [esp+12]
    mov edi, [esp+20]
    repe cmpsb
    sete al
@@:
    pop edi
    pop esi
    ret 16
@jbv_text_eq@16 ENDP
; text a on the stack, ecx = C string -> 1 if equal
@jbv_text_is@12 PROC SYSCALL
    push esi
    push edi
    mov esi, [esp+12]
    mov edi, ecx
    movzx ecx, WORD PTR [esp+16]
    xor eax, eax
    jecxz ti_end
@@:
    mov dl, [edi]
    test dl, dl
    jz ti_ret
    cmp dl, [esi]
    jne ti_ret
    inc esi
    inc edi
    loop @B
ti_end:
    cmp BYTE PTR [edi], 0
    sete al
ti_ret:
    pop edi
    pop esi
    ret 8
@jbv_text_is@12 ENDP
; ecx = class, edx = index, tag on the stack -> the constant, or 0
@jbv_cp@12 PROC SYSCALL
    movzx edx, dx
    xor eax, eax
    test edx, edx
    jz @F
    cmp dx, WORD PTR [ecx+C_POOL_SIZE]
    jae @F
    imul edx, edx, CP_SIZEOF
    add edx, [ecx+C_POOL]
    mov cl, [esp+4]
    cmp [edx+CP_TAG], cl
    jne @F
    mov eax, edx
@@:
    ret 4
@jbv_cp@12 ENDP

; ZF = the JbvText at eax equals the one at edx
text_same:
    push esi
    push edi
    push ecx
    movzx ecx, WORD PTR [eax+TEXT_SIZE]
    cmp cx, WORD PTR [edx+TEXT_SIZE]
    jne @F
    mov esi, [eax+TEXT_DATA]
    mov edi, [edx+TEXT_DATA]
    repe cmpsb
@@:
    pop ecx
    pop edi
    pop esi
    ret
; a class by name: a 64-entry cache by name hash, then the class list
@jbv_find_class@12 PROC SYSCALL     ; ecx vm, name on the stack
    push ebx
    push esi
    mov ebx, ecx
    movzx ecx, WORD PTR [esp+16]        ; h = size; h = h * 31 + c
    mov esi, [esp+12]
    mov eax, ecx
    jecxz fc_hashed
@@:
    imul eax, eax, 31
    movzx edx, BYTE PTR [esi]
    add eax, edx
    inc esi
    loop @B
fc_hashed:
    mov edx, eax
    shr edx, 7
    xor eax, edx
    and eax, 63
    lea esi, [ebx+eax*4+VM_CLASS_CACHE]
    lea edx, [esp+12]
    mov eax, [esi]
    test eax, eax
    jz fc_list
    push eax
    add eax, C_NAME
    call text_same
    pop eax
    je fc_done
fc_list:
    mov eax, [ebx+VM_CLASSES]
fc_next:
    test eax, eax
    jz fc_done
    cmp BYTE PTR [eax+C_PRIMITIVE], 0
    jne fc_skip
    push eax
    add eax, C_NAME
    call text_same
    pop eax
    jne fc_skip
    mov [esi], eax
    jmp fc_done
fc_skip:
    mov eax, [eax+C_NEXT]
    jmp fc_next
fc_done:
    pop esi
    pop ebx
    ret 8
@jbv_find_class@12 ENDP
; a member by name and descriptor: ecx = the array, edx = count, ebx = element size, esi = name offset
find_member:
    push edi
    lea edi, [esp+20]                   ; the caller's stack arguments: name, descriptor
fm_next:
    dec edx
    js fm_none
    lea eax, [ecx+esi]
    push edx
    mov edx, edi
    call text_same
    jne fm_skip
    lea eax, [ecx+esi+TEXT_SIZEOF]      ; the descriptor follows the name
    lea edx, [edi+8]
    call text_same
fm_skip:
    pop edx
    je fm_found
    add ecx, ebx
    jmp fm_next
fm_found:
    mov eax, ecx
    pop edi
    ret
fm_none:
    xor eax, eax
    pop edi
    ret
@jbv_find_method@20 PROC SYSCALL    ; ecx class, name and descriptor on the stack
    push ebx
    push esi
    movzx edx, WORD PTR [ecx+C_METHOD_COUNT]
    mov ecx, [ecx+C_METHODS]
    mov ebx, M_SIZEOF
    mov esi, M_NAME
    call find_member
    pop esi
    pop ebx
    ret 16
@jbv_find_method@20 ENDP
@jbv_find_field@20 PROC SYSCALL
    push ebx
    push esi
    movzx edx, WORD PTR [ecx+C_FIELD_COUNT]
    mov ecx, [ecx+C_FIELDS]
    mov ebx, FIELD_SIZEOF
    mov esi, FIELD_NAME
    call find_member
    pop esi
    pop ebx
    ret 16
@jbv_find_field@20 ENDP

; an image inside the library or application archive is not a separate block
@jbv_free_image@8 PROC SYSCALL     ; ecx vm, edx image
    lea eax, [ecx+VM_LIBRARY]
    call fi_inside
    jc fi_keep
    lea eax, [ecx+VM_APP]
    call fi_inside
    jc fi_keep
    jmp @jbv_free@8
fi_keep:
    ret
fi_inside:                              ; eax = archive {data, size} -> CF = edx is inside
    push ebx
    mov ebx, [eax]
    test ebx, ebx
    jz fi_ret
    cmp edx, ebx
    jb fi_out
    mov eax, [eax+4]
    add eax, ebx
    cmp edx, eax
fi_ret:
    pop ebx
    ret
fi_out:
    clc
    pop ebx
    ret
@jbv_free_image@8 ENDP

FREE MACRO field
    mov edx, [esi+field]
    mov ecx, ebx
    call @jbv_free@8
ENDM
@jbv_free_class@8 PROC SYSCALL     ; ecx vm, edx class (0: nothing)
    test edx, edx
    jz fr_ret
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    lea edi, [ebx+VM_CLASS_CACHE]       ; forget it in the name cache
    mov ecx, 64
    mov eax, esi
@@:
    cmp [edi], eax
    jne fr_cached
    mov DWORD PTR [edi], 0
fr_cached:
    add edi, 4
    loop @B
    cmp [ebx+VM_THROWABLE], esi         ; and as the cached Throwable or StackTraceElement
    je @F
    cmp [ebx+VM_TRACE_ELEMENT], esi
    jne fr_parts
@@:
    xor eax, eax
    mov [ebx+VM_THROWABLE], eax
    mov [ebx+VM_TRACE_ELEMENT], eax
    lea edi, [ebx+VM_THROWABLE_INIT]
    mov ecx, 5
    rep stosd
fr_parts:
    FREE C_REF_SLOTS
    FREE C_ROOT_SLOTS
    FREE C_METHODS
    FREE C_FIELDS
    FREE C_INTERFACES
    mov edi, [esi+C_POOL]               ; resolved member links live in Field/Method/InterfaceMethodref text
    test edi, edi
    jz fr_image
    movzx eax, WORD PTR [esi+C_POOL_SIZE]
    dec eax
    jle fr_pool
    push eax
fr_entry:
    add edi, CP_SIZEOF
    mov al, [edi+CP_TAG]
    sub al, 9
    cmp al, 2
    ja @F
    mov edx, [edi+CP_TEXT+TEXT_DATA]
    mov ecx, ebx
    call @jbv_free@8
@@:
    dec DWORD PTR [esp]
    jnz fr_entry
    pop eax
fr_pool:
    FREE C_POOL
fr_image:
    mov edx, [esi+C_IMAGE]
    mov ecx, ebx
    call @jbv_free_image@8
    mov edx, esi
    mov ecx, ebx
    call @jbv_free@8
    pop edi
    pop esi
    pop ebx
fr_ret:
    ret
@jbv_free_class@8 ENDP

jbv_status_string PROC EXPORT       ; const char *jbv_status_string(JbvStatus), cdecl
    mov ecx, [esp+4]
    cmp ecx, 23
    jb @F
    mov ecx, 23
@@:
    mov eax, OFFSET statuses
ss_next:
    jecxz ss_done
@@:
    inc eax
    cmp BYTE PTR [eax-1], 0
    jne @B
    dec ecx
    jmp ss_next
ss_done:
    ret
jbv_status_string ENDP
END

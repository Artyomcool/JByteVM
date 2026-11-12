; VM basics for x86 (vm.c is the reference and serves x64): accounted allocation,
; text comparison, class/method/field lookup, freeing classes, the public VM API.
; Internal functions keep the C names (fastcall); the API is cdecl and exported.
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

; ---- the public VM API (cdecl, exported)
EXTERN SYSCALL @jbv_bootstrap@4:PROC
EXTERN SYSCALL @jbv_free_heap@4:PROC
EXTERN jbv_parse_owned:PROC
EXTERN SYSCALL @jbv_classpath_find@20:PROC
EXTERN SYSCALL @jbv_library_id@8:PROC
EXTERN SYSCALL @jbv_exception_name@8:PROC
EXTERN SYSCALL @jbv_lazy_class@16:PROC
EXTERN SYSCALL @jbv_signature@16:PROC
EXTERN SYSCALL @jbv_begin_call@4:PROC
EXTERN jbv_archive_open:PROC
EXTERN jbv_archive_find:PROC
EXTERN jbv_resolve_method:PROC
EXTERN jbv_invoke:PROC
S_BAD_ARG     EQU 1
S_OOM         EQU 2
S_UNSUPPORTED EQU 6
S_NOT_FOUND   EQU 7
S_LINKAGE     EQU 8
S_BUSY        EQU 11
NATIVE        EQU 100h
STATIC        EQU 8
TYPED_NATIVE  EQU 8000h

jbv_memory_stats PROC EXPORT        ; (vm, out)
    mov ecx, [esp+4]
    mov edx, [esp+8]
    mov eax, S_BAD_ARG
    test ecx, ecx
    jz @F
    test edx, edx
    jz @F
    mov eax, [ecx+VM_MEMORY_USED]
    mov [edx], eax
    mov eax, [ecx+VM_MEMORY_PEAK]
    mov [edx+4], eax
    mov eax, [ecx+VM_MAX_MEMORY]
    mov [edx+8], eax
    xor eax, eax
@@:
    ret
jbv_memory_stats ENDP

jbv_create PROC EXPORT              ; (config, out)
    push ebx
    push esi
    push edi
    mov esi, [esp+16]                   ; config
    mov eax, [esp+20]
    test eax, eax
    jz cr_bad
    mov DWORD PTR [eax], 0
    test esi, esi
    jz cr_bad
    cmp DWORD PTR [esi+CFG_ALLOC], 0
    je cr_bad
    cmp DWORD PTR [esi+CFG_FREE], 0
    je cr_bad
    cmp DWORD PTR [esi+CFG_MAX_DEPTH], 256
    ja cr_bad
    cmp DWORD PTR [esi+CFG_MAX_SLOTS], 1000000h
    ja cr_bad
    mov ebx, [esi+CFG_MAX_MEMORY]       ; the total limit: 10 MiB by default
    test ebx, ebx
    jnz @F
    mov ebx, 10*1024*1024
@@:
    cmp [esi+CFG_MAX_HEAP], ebx
    ja cr_bad
    cmp ebx, VM_SIZEOF
    jb cr_oom
    push VM_SIZEOF
    push DWORD PTR [esi+CFG_USER]
    call DWORD PTR [esi+CFG_ALLOC]
    add esp, 8
    test eax, eax
    jz cr_oom
    mov edx, eax
    mov edi, eax
    mov ecx, VM_SIZEOF
    xor eax, eax
    rep stosb
    mov edi, edx                        ; vm->config = *config
    mov ecx, CFG_SIZEOF/4
    rep movsd
    mov esi, edx                        ; esi = the VM
    mov [esi+VM_MAX_MEMORY], ebx
    mov DWORD PTR [esi+VM_MEMORY_USED], VM_SIZEOF
    mov DWORD PTR [esi+VM_MEMORY_PEAK], VM_SIZEOF
    cmp DWORD PTR [esi+CFG_MAX_DEPTH], 0
    jne @F
    mov DWORD PTR [esi+CFG_MAX_DEPTH], 64
@@:
    cmp DWORD PTR [esi+CFG_MAX_SLOTS], 0
    jne @F
    mov DWORD PTR [esi+CFG_MAX_SLOTS], 16384
@@:
    mov eax, [esi+CFG_MAX_INSTRUCTIONS]
    or eax, [esi+CFG_MAX_INSTRUCTIONS+4]
    jnz @F
    mov DWORD PTR [esi+CFG_MAX_INSTRUCTIONS], 10000000
@@:
    mov eax, [esi+CFG_MAX_HEAP]
    test eax, eax
    jnz @F
    mov eax, ebx
@@:
    mov [esi+VM_HEAP_LIMIT], eax
    mov edx, [esi+CFG_MAX_SLOTS]
    shl edx, 2
    mov ecx, esi
    call @jbv_alloc@8
    mov [esi+VM_SLOTS], eax
    test eax, eax
    jnz @F
    push esi                            ; nothing else exists yet: just the VM
    push DWORD PTR [esi+CFG_USER]
    call DWORD PTR [esi+CFG_FREE]
    add esp, 8
    jmp cr_oom
@@:
    mov edx, [esi+CFG_MAX_SLOTS]
    mov ecx, esi
    call @jbv_alloc@8
    mov [esi+VM_SLOT_REFS], eax
    mov ebx, S_OOM
    test eax, eax
    jz cr_destroy
    mov ecx, esi
    call @jbv_bootstrap@4
    mov ebx, eax
    test eax, eax
    jnz cr_destroy
    mov eax, [esp+20]
    mov [eax], esi
    xor eax, eax
    jmp cr_ret
cr_destroy:
    push esi
    call jbv_destroy
    add esp, 4
    mov eax, ebx
    jmp cr_ret
cr_oom:
    mov eax, S_OOM
    jmp cr_ret
cr_bad:
    mov eax, S_BAD_ARG
cr_ret:
    pop edi
    pop esi
    pop ebx
    ret
jbv_create ENDP

FREE_VM MACRO field
    mov edx, [ebx+field]
    mov ecx, ebx
    call @jbv_free@8
ENDM
jbv_destroy PROC EXPORT             ; (vm)
    push ebx
    push esi
    mov ebx, [esp+12]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz ds_ret
    mov eax, S_BUSY
    cmp DWORD PTR [ebx+VM_DEPTH], 0
    jne ds_ret
    mov ecx, ebx
    call @jbv_free_heap@4
    FREE_VM VM_MONITORS
    mov esi, [ebx+VM_CLASSES]
@@:
    test esi, esi
    jz @F
    mov edx, esi
    mov esi, [esi+C_NEXT]
    mov ecx, ebx
    call @jbv_free_class@8
    jmp @B
@@:
    FREE_VM VM_LIBRARY
    FREE_VM VM_APP
    FREE_VM VM_SLOTS
    FREE_VM VM_SLOT_REFS
    push ebx
    push DWORD PTR [ebx+CFG_USER]
    call DWORD PTR [ebx+CFG_FREE]
    add esp, 8
    xor eax, eax
ds_ret:
    pop esi
    pop ebx
    ret
jbv_destroy ENDP

jbv_load_jar PROC EXPORT            ; (vm, bytes, size)
    mov ecx, [esp+4]
    mov eax, S_BAD_ARG
    test ecx, ecx
    jz @F
    cmp DWORD PTR [esp+8], 0
    je @F
    cmp DWORD PTR [ecx+VM_APP], 0
    jne @F
    mov eax, S_BUSY
    cmp DWORD PTR [ecx+VM_DEPTH], 0
    jne @F
    push 1
    push DWORD PTR [esp+16]
    push DWORD PTR [esp+16]
    lea eax, [ecx+VM_APP]
    push eax
    push ecx
    call jbv_archive_open
    add esp, 20
@@:
    ret
jbv_load_jar ENDP

jbv_load_class PROC EXPORT          ; (vm, bytes, size)
    push ebx
    push esi
    push edi
    push 0                              ; [esp] = the class
    mov ebx, [esp+20]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz lc_ret
    cmp DWORD PTR [esp+24], 0
    je lc_ret
    mov eax, S_BUSY
    cmp DWORD PTR [ebx+VM_DEPTH], 0
    jne lc_ret
    mov eax, esp
    push eax
    push DWORD PTR [esp+32]
    mov edx, [esp+32]
    mov ecx, ebx
    call @jbv_parse@16
    test eax, eax
    jnz lc_ret
    mov esi, [esp]                      ; esi = the class
    lea edi, [esi+C_NAME]
    ; built-in layouts are owned by the runtime, including before lazy creation
    push 0
    push DWORD PTR [edi+4]
    push DWORD PTR [edi]
    xor edx, edx
    mov ecx, ebx
    call @jbv_classpath_find@20
    test eax, eax
    jz lc_taken
    cmp eax, S_NOT_FOUND
    jne lc_free
    push DWORD PTR [edi+4]
    push DWORD PTR [edi]
    mov ecx, ebx
    call @jbv_find_class@12
    test eax, eax
    jnz lc_taken
    push DWORD PTR [edi+4]
    push DWORD PTR [edi]
    call @jbv_library_id@8
    test al, al
    jnz lc_taken
    push DWORD PTR [edi+4]
    push DWORD PTR [edi]
    call @jbv_exception_name@8
    test eax, eax
    jnz lc_taken
    push 0
    push 0
    push DWORD PTR [edi+4]
    push DWORD PTR [edi]
    lea eax, [ebx+VM_APP]
    push eax
    call jbv_archive_find
    add esp, 20
    test eax, eax
    jz lc_taken
    mov eax, [ebx+VM_CLASSES]
    mov [esi+C_NEXT], eax
    mov [ebx+VM_CLASSES], esi
    xor eax, eax
    jmp lc_ret
lc_taken:
    mov eax, S_LINKAGE
lc_free:
    push eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_free_class@8
    pop eax
lc_ret:
    pop ecx
    pop edi
    pop esi
    pop ebx
    ret
jbv_load_class ENDP

; bind_native: [esp+4] vm, class, name, descriptor, callback, wide, user (stdcall-like frame below)
B_VM    EQU 8
B_CLASS EQU 12
B_NAME  EQU 16
B_DESC  EQU 20
B_CB    EQU 24
B_WIDE  EQU 28
B_USER  EQU 32
bind_native:
    push ebp
    mov ebp, esp
    push ebx
    push 0                              ; [ebp-8] = the class
    mov ebx, [ebp+B_VM]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz bn_ret
    cmp DWORD PTR [ebp+B_CLASS], 0
    je bn_ret
    cmp DWORD PTR [ebp+B_NAME], 0
    je bn_ret
    cmp DWORD PTR [ebp+B_DESC], 0
    je bn_ret
    mov ecx, [ebp+B_CB]
    or ecx, [ebp+B_WIDE]
    jz bn_ret
    mov eax, S_BUSY
    cmp DWORD PTR [ebx+VM_DEPTH], 0
    jne bn_ret
    mov ecx, [ebp+B_CLASS]
    call @jbv_text@4
    push edx
    push eax
    push edx
    push eax
    mov ecx, ebx
    call @jbv_find_class@12
    pop ecx                             ; the class name again
    pop edx
    mov [ebp-8], eax
    test eax, eax
    jnz bn_found
    push edx
    push ecx
    lea edx, [ebp-8]
    mov ecx, ebx
    call @jbv_lazy_class@16
    test eax, eax
    jnz bn_ret
bn_found:
    mov ecx, [ebp+B_DESC]
    call @jbv_text@4
    push edx
    push eax
    mov ecx, [ebp+B_NAME]
    call @jbv_text@4
    push edx
    push eax
    mov ecx, [ebp-8]
    call @jbv_find_method@20
    mov ecx, eax
    mov eax, S_NOT_FOUND
    test ecx, ecx
    jz bn_ret
    mov eax, S_LINKAGE
    test WORD PTR [ecx+M_FLAGS], NATIVE
    jz bn_ret
    cmp BYTE PTR [ecx+M_INTRINSIC], 0
    jne bn_ret
    mov eax, S_UNSUPPORTED
    test WORD PTR [ecx+M_FLAGS], STATIC
    jz bn_ret
    cmp DWORD PTR [ebp+B_WIDE], 0       ; a plain callback returns at most 32 bits
    jne @F
    cmp BYTE PTR [ecx+M_RESULT_KIND], 3
    je bn_ret
    cmp BYTE PTR [ecx+M_RESULT_KIND], 6
    je bn_ret
@@:
    and WORD PTR [ecx+M_FLAGS], NOT TYPED_NATIVE
    mov eax, [ebp+B_CB]
    mov [ecx+M_NATIVE], eax
    mov eax, [ebp+B_WIDE]
    mov [ecx+M_NATIVE_SLOTS], eax
    mov eax, [ebp+B_USER]
    mov [ecx+M_NATIVE_USER], eax
    xor eax, eax
bn_ret:
    pop ecx
    pop ebx
    pop ebp
    ret
jbv_bind_native PROC EXPORT         ; (vm, class, name, descriptor, callback, user)
    push DWORD PTR [esp+24]
    push 0
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    call bind_native
    add esp, 28
    ret
jbv_bind_native ENDP
jbv_bind_native_slots PROC EXPORT   ; (vm, class, name, descriptor, callback, user)
    push DWORD PTR [esp+24]
    push DWORD PTR [esp+24]
    push 0
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    push DWORD PTR [esp+28]
    call bind_native
    add esp, 28
    ret
jbv_bind_native_slots ENDP

jbv_call PROC EXPORT                ; (vm, class, name, descriptor, args, count, int32_t *result)
    push ebp
    mov ebp, esp
    sub esp, 16                         ; [ebp-8] value, [ebp-12] returns, [ebp-16] expected
    mov eax, S_BAD_ARG
    cmp DWORD PTR [ebp+20], 0
    je jc_ret
    cmp DWORD PTR [ebp+32], 0
    je jc_ret
    mov ecx, [ebp+20]
    call @jbv_text@4
    push edx
    push eax
    lea ecx, [ebp-16]
    lea edx, [ebp-12]
    call @jbv_signature@16
    test eax, eax
    jnz jc_ret
    mov eax, S_UNSUPPORTED
    cmp DWORD PTR [ebp-12], 3
    je jc_ret
    cmp DWORD PTR [ebp-12], 6
    je jc_ret
    lea eax, [ebp-8]
    push eax
    push DWORD PTR [ebp+28]
    push DWORD PTR [ebp+24]
    push DWORD PTR [ebp+20]
    push DWORD PTR [ebp+16]
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call jbv_call_slots
    add esp, 28
    test eax, eax
    jnz jc_ret
    mov ecx, [ebp+32]
    mov edx, [ebp-8]
    mov [ecx], edx
jc_ret:
    mov esp, ebp
    pop ebp
    ret
jbv_call ENDP

jbv_call_slots PROC EXPORT          ; (vm, class, name, descriptor, args, count, uint64_t *result)
    push ebp
    mov ebp, esp
    sub esp, 8                          ; the method id
    mov ecx, [ebp+8]
    mov eax, S_BAD_ARG
    test ecx, ecx
    jz cs_ret
    cmp DWORD PTR [ebp+32], 0
    je cs_ret
    cmp WORD PTR [ebp+28], 0
    je @F
    cmp DWORD PTR [ebp+24], 0
    je cs_ret
@@:
    call @jbv_begin_call@4
    lea eax, [ebp-8]
    push eax
    push DWORD PTR [ebp+20]
    push DWORD PTR [ebp+16]
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call jbv_resolve_method
    add esp, 20
    test eax, eax
    jnz cs_ret
    mov eax, [ebp-4]                    ; id.method
    test WORD PTR [eax+M_FLAGS], STATIC
    mov eax, S_UNSUPPORTED
    jz cs_ret
    push DWORD PTR [ebp+32]
    push DWORD PTR [ebp+28]
    push DWORD PTR [ebp+24]
    lea eax, [ebp-8]
    push eax
    push DWORD PTR [ebp+8]
    call jbv_invoke
    add esp, 20
cs_ret:
    mov esp, ebp
    pop ebp
    ret
jbv_call_slots ENDP
;
@jbv_parse@16 PROC SYSCALL          ; ecx vm, edx bytes, [esp+4] size, [esp+8] out: a copy, then parsed
    push esi
    push edi
    push ebx
    mov ebx, ecx
    mov esi, edx
    mov eax, 3                          ; BAD_CLASS
    mov edx, [esp+16]
    cmp edx, 10
    jb pa_ret
    cmp edx, 64*1024*1024
    ja pa_ret
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jnz @F
    mov eax, 2
    jmp pa_ret
@@:
    mov edi, eax
    mov ecx, [esp+16]
    rep movsb
    push DWORD PTR [esp+20]
    push DWORD PTR [esp+20]
    push eax
    push ebx
    call jbv_parse_owned
    add esp, 16
pa_ret:
    pop ebx
    pop edi
    pop esi
    ret 8
@jbv_parse@16 ENDP
jbv_features PROC EXPORT            ; the profile's features
IF JBV_PROFILE_FULL
    mov eax, 1 or 2 or 4 or 8 or 16 or 64 or 128
ELSEIF JBV_PROFILE_CORE
    mov eax, 1 or 2 or 4
ELSE
    mov eax, 1 or 2 or 4 or 8
ENDIF
    ret
jbv_features ENDP
jbv_set_host_services PROC EXPORT   ; (vm, services or 0): installed while idle
    mov ecx, [esp+4]
    mov eax, 1
    jecxz hs_ret
    mov eax, 11
    cmp DWORD PTR [ecx+VM_DEPTH], 0
    jne hs_ret
    mov edx, [esp+8]
    xor eax, eax
    mov [ecx+VM_CLOCK], eax
    mov [ecx+VM_WRITE], eax
    mov [ecx+VM_SERVICES_USER], eax
    test edx, edx
    jz hs_ret
    mov eax, [edx]
    mov [ecx+VM_CLOCK], eax
    mov eax, [edx+4]
    mov [ecx+VM_WRITE], eax
    mov eax, [edx+8]
    mov [ecx+VM_SERVICES_USER], eax
    xor eax, eax
hs_ret:
    ret
jbv_set_host_services ENDP
END

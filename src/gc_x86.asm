; The heap and its collector for x86 (the second part of objects.c is the reference and
; serves x64). Young generation: one bump region of blocks [spare word][array length]
; header payload. Old generation: chunks (next, size) with bump allocation and free
; lists per size up to SMALL bytes; larger blocks are host allocations. A minor collection
; promotes reachable young objects; a full one marks, sweeps and slides old objects
; together. References are handles, so moving an object rewrites only its handle.
; Here ebx is the VM; a traversal's visitor (eax = a reference) is in edi.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
PUBLIC jbv_collect
PUBLIC jbv_set_heap_limit
PUBLIC jbv_heap_stats
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_reference_type@8:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC

SMALL      EQU 512
YOUNG_MAX  EQU 1048576
S_BAD_ARG  EQU 1
S_OOM      EQU 2
S_LINKAGE  EQU 8
S_LIMIT    EQU 10
S_BUSY     EQU 11
S_NEGATIVE EQU 14
F_STATIC   EQU 8
F_INTERFACE EQU 200h
F_ABSTRACT EQU 400h
DATA0      EQU 4
MARK_SLOTS EQU 256

.code
; ---- sizes and places
; eax = an object -> eax = the payload bytes after its header
@jbv_object_bytes@4 PROC SYSCALL
    mov eax, ecx
@jbv_object_bytes@4 ENDP
payload:
    mov edx, [eax]
    movzx ecx, BYTE PTR [edx+C_ARRAY_KIND]
    test ecx, ecx
    jnz @F
    mov eax, [edx+C_INSTANCE_SLOTS]
    shl eax, 2
    ret
@@:
    mov eax, [eax-4]                    ; the length
    cmp cl, 'Z'
    je pl_one
    cmp cl, 'B'
    je pl_one
    cmp cl, 'C'
    je pl_two
    cmp cl, 'S'
    je pl_two
    cmp cl, 'J'
    je pl_eight
    cmp cl, 'D'
    je pl_eight
    shl eax, 2
    ret
pl_eight:
    shl eax, 3
    ret
pl_two:
    shl eax, 1
pl_one:
    ret
; eax = an object -> eax = its old-space block size: [array length] header payload, aligned
block_size:
    push eax
    call payload
    pop edx
    add eax, 4+3
    mov edx, [edx]
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    je @F
    add eax, 4
@@:
    and eax, -4
    ret
; eax = an object -> eax = where its block starts
block_start:
    mov edx, [eax]
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    je @F
    sub eax, 4
@@:
    ret
; eax = a pointer -> CF = it is in the young region (ecx used)
YOUNG MACRO
    mov ecx, eax
    sub ecx, [ebx+VM_NURSERY]
    cmp ecx, [ebx+VM_NURSERY_SIZE]
ENDM
; eax = a reference -> ZF = a live handle of its generation: eax = the object, edx = its index
live:
    test eax, eax
    jz lv_no
    js lv_no
    mov edx, eax
    and edx, 0FFFFFFh
    jz lv_no
    cmp edx, [ebx+VM_HANDLE_CAPACITY]
    ja lv_no
    mov ecx, [ebx+VM_USED_MAP]
    bt [ecx], edx
    jnc lv_no
    shr eax, 24
    mov ecx, [ebx+VM_GENERATIONS]
    cmp al, [ecx+edx]
    jne lv_ret
    mov eax, [ebx+VM_HANDLES]
    mov eax, [eax+edx*4]
    cmp eax, eax
lv_ret:
    ret
lv_no:
    or esp, esp
    ret
; edx = a handle index -> eax = its reference
handle_ref:
    mov eax, [ebx+VM_GENERATIONS]
    movzx eax, BYTE PTR [eax+edx]
    shl eax, 24
    or eax, edx
    ret
; zero ecx bytes (a multiple of 4) at edx
zero_words:
    push edi
    mov edi, edx
    shr ecx, 2
    xor eax, eax
    rep stosd
    pop edi
    ret

; ---- old space blocks
; eax = size (aligned) -> eax = a zeroed block, or 0
block_alloc:
    cmp eax, SMALL
    jbe @F
    mov edx, eax
    mov ecx, ebx
    jmp @jbv_alloc@8
@@:
    push esi
    mov esi, eax
    mov ecx, [ebx+VM_FREE_BLOCKS+esi]   ; the free list for this size (index = size / 4)
    test ecx, ecx
    jz ba_bump
    mov eax, [ecx]
    mov [ebx+VM_FREE_BLOCKS+esi], eax
    mov edx, ecx
    push ecx
    mov ecx, esi
    call zero_words
    pop eax
    pop esi
    ret
ba_bump:
    mov eax, [ebx+VM_BUMP_END]
    sub eax, [ebx+VM_BUMP]
    cmp eax, esi
    jae ba_take
    push edi
    push eax                            ; the rest of the current chunk
    mov edi, [ebx+VM_CHUNK_SIZE]
    test edi, edi
    jnz @F
    mov edi, 2048
@@:
    mov edx, edi
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jnz ba_chunk
    lea edi, [esi+8]                    ; a tight budget: an exact chunk
    mov edx, edi
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jnz ba_chunk
    pop edx
    pop edi
    pop esi
    ret
ba_chunk:
    pop edx                             ; the rest becomes a free block
    cmp edx, 4
    jb @F
    mov ecx, [ebx+VM_BUMP]
    push esi
    mov esi, [ebx+VM_FREE_BLOCKS+edx]
    mov [ecx], esi
    mov [ebx+VM_FREE_BLOCKS+edx], ecx
    pop esi
@@:
    mov ecx, [ebx+VM_CHUNKS]
    mov [eax], ecx
    mov [eax+4], edi
    mov [ebx+VM_CHUNKS], eax
    lea ecx, [eax+8]
    mov [ebx+VM_BUMP], ecx
    add eax, edi
    mov [ebx+VM_BUMP_END], eax
    cmp edi, [ebx+VM_CHUNK_SIZE]
    jb @F
    cmp edi, 65536
    jae @F
    shl edi, 1
    mov [ebx+VM_CHUNK_SIZE], edi
@@:
    pop edi
ba_take:                                ; chunk memory arrives zeroed
    mov eax, [ebx+VM_BUMP]
    add [ebx+VM_BUMP], esi
    pop esi
    ret
; eax = block, ecx = size
block_free:
    cmp ecx, SMALL
    jbe @F
    mov edx, eax
    mov ecx, ebx
    jmp @jbv_free@8
@@:
    mov edx, [ebx+VM_FREE_BLOCKS+ecx]
    mov [eax], edx
    mov [ebx+VM_FREE_BLOCKS+ecx], eax
    ret
; a growable pointer list (edx = its {list, count, capacity}), eax = the pointer -> ZF = failed
; Bounded: past 65536 entries the next minor collection scans the old generation instead.
push_pointer:
    cmp DWORD PTR [edx+4], 65536
    jae pp_fail
    mov ecx, [edx+4]
    cmp ecx, [edx+8]
    jne pp_store
    push esi
    push edi
    push eax
    push edx
    mov esi, ecx                        ; grow: twice, 64 first
    add esi, esi
    jnz @F
    mov esi, 64
@@:
    lea edx, [esi*4]
    mov ecx, ebx
    call @jbv_alloc@8
    pop edx
    test eax, eax
    jz pp_grow_failed
    push esi
    push edx
    mov edi, eax
    mov esi, [edx]
    mov ecx, [edx+4]
    rep movsd
    pop edi                             ; edi = the list
    pop esi
    push eax
    mov edx, [edi]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
    mov [edi], eax
    mov [edi+8], esi
    mov edx, edi
    pop eax
    pop edi
    pop esi
pp_store:
    mov ecx, [edx]
    push esi
    mov esi, [edx+4]
    mov [ecx+esi*4], eax
    pop esi
    inc DWORD PTR [edx+4]
    or eax, -1                          ; ZF = 0
    ret
pp_grow_failed:
    pop eax
    pop edi
    pop esi
pp_fail:
    xor eax, eax
    ret

; ---- the write barrier's slow path: an old object may now reference a young one
remember:                               ; eax = the owner
    cmp [ebx+VM_LAST_REMEMBERED], eax
    je @F
    push eax
    lea edx, [ebx+VM_REMEMBERED]
    call push_pointer
    pop eax
    jz rm_overflow
    mov [ebx+VM_LAST_REMEMBERED], eax
@@:
    ret
rm_overflow:
    mov BYTE PTR [ebx+VM_REMEMBERED_OVERFLOW], 1
    ret
@jbv_remember@8 PROC SYSCALL        ; ecx vm, edx owner
    push ebx
    mov ebx, ecx
    mov eax, edx
    call remember
    pop ebx
    ret
@jbv_remember@8 ENDP
@jbv_barrier_checked@12 PROC SYSCALL ; ecx vm, edx owner, [esp+4] value (may be invalid)
    push ebx
    push esi
    mov ebx, ecx
    mov esi, edx
    cmp DWORD PTR [ebx+VM_NURSERY], 0
    je bc_ret
    mov eax, esi
    YOUNG
    jb bc_ret
    mov eax, [esp+12]
    call live
    jnz bc_ret
    YOUNG
    jae bc_ret
    mov eax, esi
    call remember
bc_ret:
    pop esi
    pop ebx
    ret 4
@jbv_barrier_checked@12 ENDP

; ---- marking and scanning; a fixed mark stack, rescans on overflow
; eax = a field -> ZF = 0 if it is an instance reference field
ref_field:
    test WORD PTR [eax+FIELD_FLAGS], F_STATIC
    jnz rf_no
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    call @jbv_reference_type@8
    test eax, eax
    ret
rf_no:
    xor eax, eax
    ret
; eax = a class -> its instance reference slots (an oop map built on first use):
; eax = the slots (non-zero when ready, maybe with no slots), ecx = their count; eax = 0: no memory
ref_slots:
    cmp BYTE PTR [eax+C_REF_READY], 0
    jne rs_ready
    push esi
    push edi
    push ebp
    mov esi, eax
    xor ebp, ebp                        ; first count, then (ebp = -1) fill
rs_pass:
    xor edi, edi                        ; n
    mov edx, esi
rs_class:
    test edx, edx
    jz rs_passed
    movzx ecx, WORD PTR [edx+C_FIELD_COUNT]
    mov eax, [edx+C_FIELDS]
    jecxz rs_up
@@:
    push eax
    push ecx
    push edx
    call ref_field
    pop edx
    pop ecx
    pop eax
    jz rs_next
    test ebp, ebp
    jz rs_counted
    push ecx
    mov ecx, [esi+C_REFS]
    push eax
    mov eax, [eax+FIELD_SLOT]
    mov [ecx+edi*2], ax
    pop eax
    pop ecx
rs_counted:
    inc edi
rs_next:
    add eax, FIELD_SIZEOF
    loop @B
rs_up:
    mov edx, [edx+C_SUPER]
    jmp rs_class
rs_passed:
    test ebp, ebp
    jnz rs_built
    test edi, edi
    jz rs_built
    lea edx, [edi*2]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [esi+C_REFS], eax
    test eax, eax
    jz rs_oom
    dec ebp
    jmp rs_pass
rs_built:
    mov [esi+C_REF_COUNT], di
    mov BYTE PTR [esi+C_REF_READY], 1
    mov eax, esi
    pop ebp
    pop edi
    pop esi
rs_ready:
    movzx ecx, WORD PTR [eax+C_REF_COUNT]
    cmp DWORD PTR [eax+C_REFS], 0
    je @F
    mov eax, [eax+C_REFS]
@@:
    ret
rs_oom:
    pop ebp
    pop edi
    pop esi
    xor ecx, ecx
    xor eax, eax
    ret
; eax = a class -> ZF = 0 if its objects can hold references
needs_scan:
    movzx ecx, BYTE PTR [eax+C_ARRAY_KIND]
    test ecx, ecx
    jz @F
    cmp cl, 'L'
    sete cl
    test ecx, ecx
    ret
@@:
    cmp BYTE PTR [eax+C_REF_READY], 0
    je @F
    cmp WORD PTR [eax+C_REF_COUNT], 0
    setne cl
    test ecx, ecx
    ret
@@:
    push esi
    mov esi, eax
ns_class:
    test esi, esi
    jz ns_ret
    movzx ecx, WORD PTR [esi+C_FIELD_COUNT]
    mov eax, [esi+C_FIELDS]
    jecxz ns_up
@@:
    push eax
    push ecx
    call ref_field
    pop ecx
    pop eax
    jnz ns_yes
    add eax, FIELD_SIZEOF
    loop @B
ns_up:
    mov esi, [esi+C_SUPER]
    jmp ns_class
ns_yes:
    or esi, -1
ns_ret:
    test esi, esi
    pop esi
    ret
push_mark:                              ; edx = a handle index
    mov ecx, [ebx+VM_MARK_TOP]
    cmp ecx, MARK_SLOTS
    jae @F
    mov [ebx+VM_MARK_STACK+ecx*4], edx
    inc DWORD PTR [ebx+VM_MARK_TOP]
    ret
@@:
    mov BYTE PTR [ebx+VM_MARK_OVERFLOW], 1
    ret
mark_bit:                               ; edx = index: marked
    mov ecx, [ebx+VM_MARKS]
    bts [ecx], edx
    ret
; esi = an object: every reference in it to the visitor edi
scan:
    push esi
    push ebp
    mov [ebx+VM_SCANNING], esi
    mov eax, [esi]
    movzx ecx, BYTE PTR [eax+C_ARRAY_KIND]
    test ecx, ecx
    jz sc_plain
    cmp cl, 'L'
    jne sc_done
    mov ebp, [esi-4]                    ; elements, last first
@@:
    dec ebp
    js sc_done
    mov eax, [esi+ebp*4+DATA0]
    call edi
    jmp @B
sc_plain:
    call ref_slots
    test eax, eax
    jz sc_fields
    mov ebp, ecx
    push eax
@@:
    dec ebp
    js @F
    mov eax, [esp]
    movzx ecx, WORD PTR [eax]
    add DWORD PTR [esp], 2
    mov eax, [esi+ecx*4+DATA0]
    call edi
    jmp @B
@@:
    pop eax
    jmp sc_done
sc_fields:                              ; no memory for the map: the fields themselves
    mov ebp, [esi]
sc_class:
    test ebp, ebp
    jz sc_done
    movzx ecx, WORD PTR [ebp+C_FIELD_COUNT]
    mov eax, [ebp+C_FIELDS]
    jecxz sc_up
@@:
    push eax
    push ecx
    call ref_field
    pop ecx
    pop eax
    jz sc_next
    push eax
    push ecx
    mov eax, [eax+FIELD_SLOT]
    mov eax, [esi+eax*4+DATA0]
    call edi
    pop ecx
    pop eax
sc_next:
    add eax, FIELD_SIZEOF
    loop @B
sc_up:
    mov ebp, [ebp+C_SUPER]
    jmp sc_class
sc_done:
    mov DWORD PTR [ebx+VM_SCANNING], 0
    pop ebp
    pop esi
    ret
drain:                                  ; scan the mark stack empty
    mov ecx, [ebx+VM_MARK_TOP]
    test ecx, ecx
    jz @F
    dec ecx
    mov [ebx+VM_MARK_TOP], ecx
    mov eax, [ebx+VM_MARK_STACK+ecx*4]
    mov ecx, [ebx+VM_HANDLES]
    push esi
    mov esi, [ecx+eax*4]
    call scan
    pop esi
    jmp drain
@@:
    ret
; full marking also rebuilds the remembered set (old objects referencing young ones)
mark_full:
    call live
    jnz mf_ret
    push edx
    mov ecx, [ebx+VM_SCANNING]
    jecxz @F
    push eax
    mov eax, ecx
    YOUNG
    pop eax
    jb @F
    push eax
    YOUNG
    pop eax
    jae @F
    push eax
    mov eax, [ebx+VM_SCANNING]
    call remember
    pop eax
@@:
    pop edx
    mov ecx, [ebx+VM_MARKS]
    bts [ecx], edx
    jc mf_ret
    push edx
    mov eax, [eax]
    call needs_scan
    pop edx
    jz mf_ret
    call push_mark
mf_ret:
    ret
; esi = a class -> its reference roots outside objects, built once (fields and pool are fixed):
; ZF = 0 when ready
class_roots:
    cmp BYTE PTR [esi+C_ROOTS_READY], 0
    jne cr_ready
    push edi
    push ebp
    xor ebp, ebp                        ; first count, then (ebp = -1) fill
cr_pass:
    xor edi, edi
    mov ecx, 1                          ; String, MethodHandle and MethodType constants
cr_pool:
    cmp cx, WORD PTR [esi+C_POOL_SIZE]
    jae cr_fields
    imul eax, ecx, CP_SIZEOF
    add eax, [esi+C_POOL]
    mov dl, [eax+CP_TAG]
    cmp dl, 8
    je @F
    cmp dl, 15
    je @F
    cmp dl, 16
    jne cr_pool_next
@@:
    test ebp, ebp
    jz @F
    add eax, CP_BITS
    mov edx, [esi+C_ROOT_SLOTS]
    mov [edx+edi*4], eax
@@:
    inc edi
cr_pool_next:
    inc ecx
    jmp cr_pool
cr_fields:                              ; and static reference fields
    movzx ecx, WORD PTR [esi+C_FIELD_COUNT]
    mov eax, [esi+C_FIELDS]
    jecxz cr_passed
cr_field:
    test WORD PTR [eax+FIELD_FLAGS], F_STATIC
    jz cr_field_next
    push eax
    push ecx
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    call @jbv_reference_type@8
    mov edx, eax
    pop ecx
    pop eax
    test edx, edx
    jz cr_field_next
    test ebp, ebp
    jz @F
    lea edx, [eax+FIELD_VALUE]
    push ecx
    mov ecx, [esi+C_ROOT_SLOTS]
    mov [ecx+edi*4], edx
    pop ecx
@@:
    inc edi
cr_field_next:
    add eax, FIELD_SIZEOF
    loop cr_field
cr_passed:
    test ebp, ebp
    jnz cr_built
    test edi, edi
    jz cr_built
    lea edx, [edi*4]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [esi+C_ROOT_SLOTS], eax
    test eax, eax
    jz cr_oom
    dec ebp
    jmp cr_pass
cr_built:
    mov [esi+C_ROOT_COUNT], edi
    mov BYTE PTR [esi+C_ROOTS_READY], 1
    pop ebp
    pop edi
cr_ready:
    or esp, esp
    ret
cr_oom:
    pop ebp
    pop edi
    xor eax, eax
    ret
; every root to the visitor edi: the exception, pins, monitors, frames' references, classes
roots:
    push esi
    push ebp
    mov eax, [ebx+VM_EXCEPTION]
    call edi
    xor ebp, ebp
ro_pin:
    cmp ebp, [ebx+VM_PIN_COUNT]
    jae ro_monitors
    mov edx, [ebx+VM_PINS]
    mov edx, [edx+ebp*8]
    call handle_ref
    call edi
    inc ebp
    jmp ro_pin
ro_monitors:
    xor ebp, ebp
ro_monitor:
    cmp ebp, [ebx+VM_MONITOR_CAP]
    jae ro_frames
    imul eax, ebp, MON_SIZEOF
    add eax, [ebx+VM_MONITORS]
    mov eax, [eax]
    test eax, eax
    jz @F
    call edi
@@:
    inc ebp
    jmp ro_monitor
ro_frames:
    mov esi, [ebx+VM_FRAMES]
ro_frame:
    test esi, esi
    jz ro_classes
    mov ebp, [esi+FR_BASE]
    mov ecx, ebp
    add ecx, [esi+FR_LOCALS]
    add ecx, [esi+FR_SP]
    push ecx                            ; the end
@@:
    cmp ebp, [esp]
    jae @F
    mov eax, [ebx+VM_SLOT_REFS]
    cmp BYTE PTR [eax+ebp], 1
    jne ro_slot
    mov eax, [ebx+VM_SLOTS]
    mov eax, [eax+ebp*4]
    call edi
ro_slot:
    inc ebp
    jmp @B
@@:
    pop ecx
    mov esi, [esi+FR_PREVIOUS]
    jmp ro_frame
ro_classes:
    mov esi, [ebx+VM_CLASSES]
ro_class:
    test esi, esi
    jz ro_done
    mov eax, [esi+C_MIRROR]
    call edi
    call class_roots
    jz ro_scan_all
    xor ebp, ebp
@@:
    cmp ebp, [esi+C_ROOT_COUNT]
    jae ro_class_done
    mov eax, [esi+C_ROOT_SLOTS]
    mov eax, [eax+ebp*4]
    mov eax, [eax]
    call edi
    inc ebp
    jmp @B
ro_scan_all:                            ; no memory for the list: the pool and fields themselves
    mov ebp, 1
@@:
    cmp bp, WORD PTR [esi+C_POOL_SIZE]
    jae ro_static
    imul eax, ebp, CP_SIZEOF
    add eax, [esi+C_POOL]
    mov dl, [eax+CP_TAG]
    cmp dl, 8
    je ro_constant
    cmp dl, 15
    je ro_constant
    cmp dl, 16
    jne ro_constant_next
ro_constant:
    mov eax, [eax+CP_BITS]
    call edi
ro_constant_next:
    inc ebp
    jmp @B
ro_static:
    xor ebp, ebp
@@:
    cmp bp, WORD PTR [esi+C_FIELD_COUNT]
    jae ro_class_done
    imul eax, ebp, FIELD_SIZEOF
    add eax, [esi+C_FIELDS]
    test WORD PTR [eax+FIELD_FLAGS], F_STATIC
    jz ro_static_next
    push eax
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE]
    push DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA]
    call @jbv_reference_type@8
    mov edx, eax
    pop eax
    test edx, edx
    jz ro_static_next
    mov eax, [eax+FIELD_VALUE]
    call edi
ro_static_next:
    inc ebp
    jmp @B
ro_class_done:
    call drain
    mov esi, [esi+C_NEXT]
    jmp ro_class
ro_done:
    call drain
    pop ebp
    pop esi
    ret
clear_marks:
    push edi
    mov ecx, [ebx+VM_HANDLE_CAPACITY]
    shr ecx, 5
    inc ecx
    mov edi, [ebx+VM_MARKS]
    xor eax, eax
    rep stosd
    mov [ebx+VM_MARK_TOP], eax
    mov [ebx+VM_MARK_OVERFLOW], al
    pop edi
    ret
; rare: rescan every marked object until nothing new is marked
finish_marking:
    cmp BYTE PTR [ebx+VM_MARK_OVERFLOW], 0
    je fm_ret
    mov BYTE PTR [ebx+VM_MARK_OVERFLOW], 0
    push ebp
    push esi
    mov ebp, 1
fm_handle:
    cmp ebp, [ebx+VM_HANDLE_CAPACITY]
    ja fm_pass
    mov eax, [ebx+VM_MARKS]
    bt [eax], ebp
    jnc fm_next
    mov eax, [ebx+VM_USED_MAP]
    bt [eax], ebp
    jnc fm_next
    mov eax, [ebx+VM_HANDLES]
    mov esi, [eax+ebp*4]
    call scan
    call drain
fm_next:
    inc ebp
    jmp fm_handle
fm_pass:
    pop esi
    pop ebp
    jmp finish_marking
fm_ret:
    ret
free_handle:                            ; edx = index
    mov ecx, [ebx+VM_USED_MAP]
    btr [ecx], edx
    mov ecx, [ebx+VM_YOUNG_MAP]
    btr [ecx], edx
    mov ecx, [ebx+VM_INTERNED_MAP]
    btr [ecx], edx
    dec DWORD PTR [ebx+VM_OBJECT_COUNT]
    ret
; a free handle from the cursor in the allocation bitmap -> edx = its index (0 if none)
; Generations advance on reuse (1..127): a stale ref is caught unless reused 127 times.
take_handle:
    push esi
    push edi
    mov esi, [ebx+VM_HANDLE_CAPACITY]
    shr esi, 5
    inc esi                             ; words
    mov edi, [ebx+VM_HANDLE_CURSOR]
    mov ecx, esi
th_word:
    mov eax, [ebx+VM_USED_MAP]
    mov edx, [eax+edi*4]
    not edx
    bsf edx, edx
    jnz th_found
    inc edi
    cmp edi, esi
    jb @F
    xor edi, edi
@@:
    loop th_word
    xor edx, edx
    jmp th_ret
th_found:
    bts [eax+edi*4], edx
    mov [ebx+VM_HANDLE_CURSOR], edi
    shl edi, 5
    or edx, edi
    mov eax, [ebx+VM_GENERATIONS]
    mov cl, [eax+edx]
    inc cl
    cmp cl, 128
    jb @F
    mov cl, 1
@@:
    mov [eax+edx], cl
    inc DWORD PTR [ebx+VM_OBJECT_COUNT]
th_ret:
    pop edi
    pop esi
    ret


; ---- minor collection: promote reachable young objects, then reset the young region
promote:                                ; the visitor: eax = a reference
    call live
    jnz pr_ret
    push eax
    YOUNG
    pop eax
    jae pr_ret
    mov ecx, [ebx+VM_MARKS]
    bt [ecx], edx
    jc pr_ret
    push esi
    push edi
    push ebp
    mov esi, eax                        ; the object
    mov ebp, edx                        ; its handle
    call block_size
    push eax                            ; [esp] = the size
    call block_alloc
    test eax, eax
    jz pr_failed
    mov edx, ebp
    call mark_bit
    mov edi, eax                        ; the copy
    push esi
    mov eax, esi
    call block_start
    mov esi, eax
    mov ecx, [esp+4]
    shr ecx, 2
    push edi
    rep movsd
    pop eax
    pop esi
    mov edx, [esi]                      ; the object keeps its offset in the block
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    je @F
    add eax, 4
@@:
    mov ecx, [ebx+VM_HANDLES]
    mov [ecx+ebp*4], eax
    pop eax
    add [ebx+VM_HEAP_BYTES], eax
    mov eax, [esi]
    call needs_scan
    jz @F
    mov edx, ebp
    call push_mark
@@:
    pop ebp
    pop edi
    pop esi
pr_ret:
    ret
pr_failed:
    mov BYTE PTR [ebx+VM_PROMOTE_FAILED], 1
    pop eax
    pop ebp
    pop edi
    pop esi
    ret
promote_children:                       ; esi = an old object
    call scan
    jmp drain
; -> eax = the status (out of memory: promoted objects moved, the others stay)
minor:
    mov eax, [ebx+VM_NURSERY]
    test eax, eax
    jz mn_reset
    cmp eax, [ebx+VM_NURSERY_TOP]
    je mn_reset
    call clear_marks
    mov BYTE PTR [ebx+VM_PROMOTE_FAILED], 0
    push esi
    push edi
    push ebp
    mov edi, OFFSET promote
    call roots
    xor ebp, ebp
@@:
    cmp ebp, [ebx+VM_REMEMBERED_COUNT]
    jae @F
    mov eax, [ebx+VM_REMEMBERED]
    mov esi, [eax+ebp*4]
    call promote_children
    inc ebp
    jmp @B
@@:
    xor ebp, ebp
@@:
    cmp ebp, [ebx+VM_RECENT_COUNT]
    jae @F
    mov eax, [ebx+VM_RECENT]
    mov esi, [eax+ebp*4]
    call promote_children
    inc ebp
    jmp @B
@@:
    cmp BYTE PTR [ebx+VM_REMEMBERED_OVERFLOW], 0
    je mn_finish
    mov ebp, 1                          ; the remembered set overflowed: every unmarked old object
mn_old:
    cmp ebp, [ebx+VM_HANDLE_CAPACITY]
    ja mn_finish
    mov eax, [ebx+VM_USED_MAP]
    bt [eax], ebp
    jnc mn_old_next
    mov eax, [ebx+VM_HANDLES]
    mov esi, [eax+ebp*4]
    mov eax, esi
    YOUNG
    jb mn_old_next
    mov eax, [ebx+VM_MARKS]
    bt [eax], ebp
    jc mn_old_next
    call promote_children
mn_old_next:
    inc ebp
    jmp mn_old
mn_finish:
    call finish_marking
    pop ebp
    pop edi
    pop esi
    mov eax, S_OOM
    cmp BYTE PTR [ebx+VM_PROMOTE_FAILED], 0
    jne mn_ret
    ; unreachable young objects are not touched: their handles are young and unmarked
    push esi
    push edi
    mov ecx, [ebx+VM_HANDLE_CAPACITY]
    shr ecx, 5
    xor esi, esi
mn_word:
    mov edi, [ebx+VM_YOUNG_MAP]
    mov eax, [edi+esi*4]
    test eax, eax
    jz mn_word_next
    mov DWORD PTR [edi+esi*4], 0
    mov edx, [ebx+VM_MARKS]
    mov edx, [edx+esi*4]
    not edx
    and eax, edx                        ; the dead
    not eax
    mov edx, [ebx+VM_USED_MAP]
    and [edx+esi*4], eax
    mov edx, [ebx+VM_INTERNED_MAP]
    and [edx+esi*4], eax
    not eax
    popcnt eax, eax
    sub [ebx+VM_OBJECT_COUNT], eax
mn_word_next:
    inc esi
    cmp esi, ecx
    jbe mn_word
    mov edi, [ebx+VM_NURSERY]
    mov ecx, [ebx+VM_NURSERY_TOP]
    sub ecx, edi
    sub [ebx+VM_HEAP_BYTES], ecx
    IF JBV_GC_STRESS
    mov al, 0CDh                        ; poisoned: stale pointers read garbage
    rep stosb
    ELSE
    shr ecx, 2                          ; kept zeroed above the top: allocation needs no clearing
    xor eax, eax
    rep stosd
    ENDIF
    mov eax, [ebx+VM_NURSERY]
    mov [ebx+VM_NURSERY_TOP], eax
    pop edi
    pop esi
mn_reset:
    xor eax, eax
    mov [ebx+VM_REMEMBERED_COUNT], eax
    mov [ebx+VM_RECENT_COUNT], eax
    mov [ebx+VM_REMEMBERED_OVERFLOW], al
    mov [ebx+VM_LAST_REMEMBERED], eax
mn_ret:
    ret

; ---- full collection: mark, sweep, then slide old objects together
address:                                ; eax = a handle index -> eax = its block's address
    mov ecx, [ebx+VM_HANDLES]
    mov eax, [ecx+eax*4]
    jmp block_start
; heap order by block address: esi = the array, ecx = i, edx = n
sift:
    push ebp
    push edi
    push ecx
    push edx
    mov ebp, [esi+ecx*4]                ; x
sf_down:
    lea edi, [ecx*2+1]                  ; c
    cmp edi, [esp]
    jae sf_place
    lea eax, [edi+1]
    cmp eax, [esp]
    jae @F
    push ecx
    mov eax, [esi+edi*4]
    call address
    push eax
    mov eax, [esi+edi*4+4]
    call address
    pop edx
    pop ecx
    cmp edx, eax
    jae @F
    inc edi
@@:
    push ecx
    mov eax, ebp
    call address
    push eax
    mov eax, [esi+edi*4]
    call address
    pop edx
    pop ecx
    cmp edx, eax
    jae sf_place
    mov eax, [esi+edi*4]
    mov [esi+ecx*4], eax
    mov ecx, edi
    jmp sf_down
sf_place:
    mov [esi+ecx*4], ebp
    pop edx
    pop ecx
    pop edi
    pop ebp
    ret
; live small old objects (sorted by address) slid to the front of address-ordered chunks
CP_LIVE   EQU 8
CP_N      EQU 12
CP_CHUNKS EQU 16
CP_COUNT  EQU 20
compact:
    push ebp
    mov ebp, esp
    push esi
    push edi
    mov esi, [ebp+CP_CHUNKS]            ; the chunks by address (insertion sort)
    mov ecx, 1
cp_insert:
    cmp ecx, [ebp+CP_COUNT]
    jae cp_sorted
    mov eax, [esi+ecx*4]
    mov edx, ecx
@@:
    test edx, edx
    jz @F
    cmp [esi+edx*4-4], eax
    jbe @F
    mov edi, [esi+edx*4-4]
    mov [esi+edx*4], edi
    dec edx
    jmp @B
@@:
    mov [esi+edx*4], eax
    inc ecx
    jmp cp_insert
cp_sorted:
    mov esi, [ebp+CP_LIVE]              ; the objects by address (heapsort)
    mov edx, [ebp+CP_N]
    cmp edx, 1
    jbe cp_heaped
    mov ecx, edx
    shr ecx, 1
@@:
    dec ecx
    js @F
    push ecx
    call sift
    pop ecx
    jmp @B
@@:
    mov edi, [ebp+CP_N]
@@:
    dec edi
    jz cp_heaped
    mov eax, [esi]
    xchg eax, [esi+edi*4]
    mov [esi], eax
    xor ecx, ecx
    mov edx, edi
    call sift
    jmp @B
cp_heaped:
    lea edi, [ebx+VM_FREE_BLOCKS]       ; free lists start over
    mov ecx, SMALL/4+1
    xor eax, eax
    rep stosd
    push 0                              ; [ebp-12] k
    mov eax, [ebp+CP_CHUNKS]
    mov eax, [eax]
    lea edi, [eax+8]                    ; edi = d
    mov edx, eax
    add edx, [eax+4]
    push edx                            ; [ebp-16] end
    push 0                              ; [ebp-20] i
cp_object:
    mov ecx, [ebp-20]
    cmp ecx, [ebp+CP_N]
    jae cp_slid
    mov eax, [ebp+CP_LIVE]
    mov eax, [eax+ecx*4]
    mov ecx, [ebx+VM_HANDLES]
    mov esi, [ecx+eax*4]                ; the object
    mov eax, esi
    call block_size
    push eax                            ; [ebp-24] its size
cp_fit:
    mov ecx, [ebp-16]
    sub ecx, edi
    cmp ecx, [esp]
    jae cp_move
    cmp ecx, 4                          ; such a gap is smaller than this block: <= SMALL
    jb @F
    mov eax, edi
    call block_free
@@:
    inc DWORD PTR [ebp-12]
    mov eax, [ebp-12]
    mov edx, [ebp+CP_CHUNKS]
    mov eax, [edx+eax*4]
    lea edi, [eax+8]
    add eax, [eax+4]
    mov [ebp-16], eax
    jmp cp_fit
cp_move:
    mov eax, esi
    call block_start
    mov edx, esi                        ; the object's offset in its block
    sub edx, eax
    push edx
    cmp eax, edi
    je @F
    push esi
    push edi
    mov esi, eax
    mov ecx, [ebp-24]
    shr ecx, 2
    rep movsd                           ; forward: also right for slides towards lower addresses
    pop edi
    pop esi
@@:
    pop edx
    lea eax, [edi+edx]
    mov ecx, [ebp-20]
    mov edx, [ebp+CP_LIVE]
    mov edx, [edx+ecx*4]
    mov ecx, [ebx+VM_HANDLES]
    mov [ecx+edx*4], eax
    pop eax
    add edi, eax
    inc DWORD PTR [ebp-20]
    jmp cp_object
cp_slid:
    mov esi, [ebp+CP_CHUNKS]
    mov ecx, [ebp-12]                   ; emptied chunks go back to the host
@@:
    inc ecx
    cmp ecx, [ebp+CP_COUNT]
    jae @F
    push ecx
    mov edx, [esi+ecx*4]
    mov ecx, ebx
    call @jbv_free@8
    pop ecx
    jmp @B
@@:
    xor ecx, ecx                        ; the rest in address order
@@:
    cmp ecx, [ebp-12]
    jae @F
    mov eax, [esi+ecx*4+4]
    mov edx, [esi+ecx*4]
    mov [edx], eax
    inc ecx
    jmp @B
@@:
    mov eax, [esi+ecx*4]
    mov DWORD PTR [eax], 0
    mov edx, edi
    mov ecx, [ebp-16]
    sub ecx, edi
    call zero_words                     ; bump allocation expects zeroed memory
    mov eax, [esi]
    mov [ebx+VM_CHUNKS], eax
    mov [ebx+VM_BUMP], edi
    mov eax, [ebp-16]
    mov [ebx+VM_BUMP_END], eax
    add esp, 12
    pop edi
    pop esi
    pop ebp
    ret 16
; eax = moving -> eax = the status (always ok)
CO_MOVING EQU -4
CO_LIVE   EQU -8
CO_CHUNKS EQU -12
CO_COUNT  EQU -16
CO_N      EQU -20
collect:
    cmp DWORD PTR [ebx+VM_MARKS], 0
    je co_none                          ; nothing allocated yet
    push ebp
    mov ebp, esp
    sub esp, 20
    push esi
    push edi
    mov [ebp+CO_MOVING], eax
    add DWORD PTR [ebx+VM_COLLECTIONS], 1
    adc DWORD PTR [ebx+VM_COLLECTIONS+4], 0
    test eax, eax
    jz @F
    call minor
    test eax, eax
    jz @F
    mov DWORD PTR [ebp+CO_MOVING], 0
@@:
    xor eax, eax
    mov [ebx+VM_REMEMBERED_COUNT], eax
    mov [ebx+VM_RECENT_COUNT], eax
    mov [ebx+VM_REMEMBERED_OVERFLOW], al
    mov [ebx+VM_LAST_REMEMBERED], eax
    mov [ebp+CO_LIVE], eax
    mov [ebp+CO_CHUNKS], eax
    mov [ebp+CO_N], eax
    call clear_marks
    mov edi, OFFSET mark_full
    call roots
    call finish_marking
    xor ecx, ecx
    mov eax, [ebx+VM_CHUNKS]
@@:
    test eax, eax
    jz @F
    inc ecx
    mov eax, [eax]
    jmp @B
@@:
    mov [ebp+CO_COUNT], ecx
    cmp DWORD PTR [ebp+CO_MOVING], 0    ; scratch first: without it, sweep without moving
    je co_sweep
    test ecx, ecx
    jz co_sweep
    mov edx, [ebx+VM_OBJECT_COUNT]
    lea edx, [edx*4+4]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [ebp+CO_LIVE], eax
    mov edx, [ebp+CO_COUNT]
    shl edx, 2
    mov ecx, ebx
    call @jbv_alloc@8
    mov [ebp+CO_CHUNKS], eax
    test eax, eax
    jz co_no_scratch
    cmp DWORD PTR [ebp+CO_LIVE], 0
    je co_no_scratch
    mov edx, [ebx+VM_CHUNKS]
@@:
    test edx, edx
    jz co_sweep
    mov [eax], edx
    add eax, 4
    mov edx, [edx]
    jmp @B
co_no_scratch:
    mov edx, [ebp+CO_LIVE]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+CO_CHUNKS]
    mov ecx, ebx
    call @jbv_free@8
    xor eax, eax
    mov [ebp+CO_LIVE], eax
    mov [ebp+CO_CHUNKS], eax
co_sweep:
    mov esi, 1
co_handle:
    cmp esi, [ebx+VM_HANDLE_CAPACITY]
    ja co_swept
    mov eax, [ebx+VM_USED_MAP]
    bt [eax], esi
    jnc co_next
    mov eax, [ebx+VM_HANDLES]
    mov edi, [eax+esi*4]                ; the object
    mov eax, edi
    call block_size
    mov edx, eax                        ; edx = the size
    mov eax, [ebx+VM_MARKS]
    bt [eax], esi
    jnc co_dead
    mov eax, [ebp+CO_LIVE]
    test eax, eax
    jz co_next
    cmp edx, SMALL
    ja co_next
    push eax
    mov eax, edi
    YOUNG
    pop eax
    jb co_next
    mov ecx, [ebp+CO_N]
    mov [eax+ecx*4], esi
    inc DWORD PTR [ebp+CO_N]
    jmp co_next
co_dead:
    push edx
    mov eax, edi
    YOUNG
    pop edx
    jb co_free_handle                   ; young garbage goes when the young region resets
    sub [ebx+VM_HEAP_BYTES], edx
    cmp DWORD PTR [ebp+CO_LIVE], 0
    je @F
    cmp edx, SMALL
    jbe co_free_handle
@@:
    push edx
    mov eax, edi
    call block_start
    pop ecx
    call block_free
co_free_handle:
    mov edx, esi
    call free_handle
co_next:
    inc esi
    jmp co_handle
co_swept:
    cmp DWORD PTR [ebp+CO_LIVE], 0
    je co_done
    push DWORD PTR [ebp+CO_COUNT]
    push DWORD PTR [ebp+CO_CHUNKS]
    push DWORD PTR [ebp+CO_N]
    push DWORD PTR [ebp+CO_LIVE]
    call compact
    mov edx, [ebp+CO_LIVE]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+CO_CHUNKS]
    mov ecx, ebx
    call @jbv_free@8
co_done:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
co_none:
    xor eax, eax
    ret
jbv_collect PROC EXPORT             ; (vm): from the host nothing holds raw pointers: compact
    push ebx
    mov ebx, [esp+8]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz @F
    mov eax, 1
    call collect
@@:
    pop ebx
    ret
jbv_collect ENDP

; ---- the handle table and its bitmaps: twice as large (255 first)
GH_NEW EQU -24                          ; handles, generations, marks, interned, used, young
grow_handles:
    push ebp
    mov ebp, esp
    sub esp, 32
    push esi
    push edi
    mov esi, [ebx+VM_HANDLE_CAPACITY]   ; old
    lea edi, [esi*2]
    test esi, esi
    jnz @F
    mov edi, 255
@@:
    cmp edi, 0FFFFFFh
    jbe @F
    mov edi, 0FFFFFFh
@@:
    mov eax, S_OOM
    cmp edi, esi
    je gh_ret
    mov [ebp-28], edi                   ; the capacity
    lea edx, [edi*4+4]
    call gh_alloc
    mov [ebp-24], eax
    lea edx, [edi+1]
    call gh_alloc
    mov [ebp-20], eax
    mov ecx, edi
    shr ecx, 5
    inc ecx
    shl ecx, 2
    mov [ebp-32], ecx                   ; bitmap bytes
    xor ecx, ecx
@@:
    push ecx
    mov edx, [ebp-32]
    call gh_alloc
    pop ecx
    mov [ebp-16+ecx*4], eax
    inc ecx
    cmp ecx, 4
    jb @B
    xor ecx, ecx                        ; all six, or none
@@:
    cmp DWORD PTR [ebp-24+ecx*4], 0
    je gh_failed
    inc ecx
    cmp ecx, 6
    jb @B
    test esi, esi                       ; copy the old entries
    jz gh_fresh
    push esi
    push edi
    mov ecx, esi
    mov edi, [ebp-24]
    add edi, 4
    mov esi, [ebx+VM_HANDLES]
    add esi, 4
    rep movsd
    pop edi
    pop esi
    push esi
    push edi
    mov ecx, esi
    mov edi, [ebp-20]
    inc edi
    mov esi, [ebx+VM_GENERATIONS]
    inc esi
    rep movsb
    pop edi
    pop esi
    lea ecx, [esi+32]                   ; the old bitmap words
    shr ecx, 5
    push edi
    push esi
    mov esi, [ebx+VM_MARKS]
    mov edi, [ebp-16]
    push ecx
    rep movsd
    pop ecx
    push ecx
    mov esi, [ebx+VM_INTERNED_MAP]
    mov edi, [ebp-12]
    rep movsd
    pop ecx
    push ecx
    mov esi, [ebx+VM_USED_MAP]
    mov edi, [ebp-8]
    rep movsd
    pop ecx
    mov esi, [ebx+VM_YOUNG_MAP]
    mov edi, [ebp-4]
    rep movsd
    pop esi
    pop edi
    mov ecx, esi                        ; the old tail becomes allocatable
    and ecx, 31
    cmp ecx, 31
    je gh_new_entries
    mov eax, 2
    shl eax, cl
    dec eax
    mov edx, esi
    shr edx, 5
    mov ecx, [ebp-8]
    and [ecx+edx*4], eax
    jmp gh_new_entries
gh_fresh:
    mov eax, [ebp-8]                    ; handle 0 is null
    mov DWORD PTR [eax], 1
gh_new_entries:
    mov eax, [ebp-20]                   ; new generations start at 1
    lea ecx, [esi+1]
@@:
    cmp ecx, edi
    ja @F
    mov BYTE PTR [eax+ecx], 1
    inc ecx
    jmp @B
@@:
    mov ecx, edi                        ; past the end: never free
    and ecx, 31
    cmp ecx, 31
    je @F
    mov eax, 2
    shl eax, cl
    dec eax
    not eax
    mov edx, edi
    shr edx, 5
    mov ecx, [ebp-8]
    or [ecx+edx*4], eax
@@:
    mov edx, [ebx+VM_HANDLES]
    call gh_free
    mov edx, [ebx+VM_GENERATIONS]
    call gh_free
    mov edx, [ebx+VM_MARKS]
    call gh_free
    mov edx, [ebx+VM_INTERNED_MAP]
    call gh_free
    mov edx, [ebx+VM_USED_MAP]
    call gh_free
    mov edx, [ebx+VM_YOUNG_MAP]
    call gh_free
    mov eax, [ebp-24]
    mov [ebx+VM_HANDLES], eax
    mov eax, [ebp-20]
    mov [ebx+VM_GENERATIONS], eax
    mov eax, [ebp-16]
    mov [ebx+VM_MARKS], eax
    mov eax, [ebp-12]
    mov [ebx+VM_INTERNED_MAP], eax
    mov eax, [ebp-8]
    mov [ebx+VM_USED_MAP], eax
    mov eax, [ebp-4]
    mov [ebx+VM_YOUNG_MAP], eax
    lea eax, [esi+1]
    shr eax, 5
    mov [ebx+VM_HANDLE_CURSOR], eax
    mov [ebx+VM_HANDLE_CAPACITY], edi
    xor eax, eax
    jmp gh_ret
gh_failed:
    xor ecx, ecx
@@:
    mov edx, [ebp-24+ecx*4]
    push ecx
    call gh_free
    pop ecx
    inc ecx
    cmp ecx, 6
    jb @B
    mov eax, S_OOM
gh_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret
gh_alloc:
    mov ecx, ebx
    jmp @jbv_alloc@8
gh_free:
    mov ecx, ebx
    jmp @jbv_free@8
; out of host memory: promote everything, give the young region back -> eax = 1 if done
drop_young:
    mov eax, [ebx+VM_NURSERY]
    test eax, eax
    jz dy_no
    cmp eax, [ebx+VM_NURSERY_TOP]
    je @F
    call minor
    test eax, eax
    jnz dy_no
@@:
    mov edx, [ebx+VM_NURSERY]
    mov ecx, ebx
    call @jbv_free@8
    xor eax, eax
    mov [ebx+VM_NURSERY], eax
    mov [ebx+VM_NURSERY_TOP], eax
    mov [ebx+VM_NURSERY_SIZE], eax
    mov BYTE PTR [ebx+VM_NURSERY_OFF], 1
    inc eax
    ret
dy_no:
    xor eax, eax
    ret

; ---- allocation
N_BYTES  EQU -4
N_PRE    EQU -8
N_BLOCK  EQU -12
N_YOUNG  EQU -16
@jbv_new@16 PROC SYSCALL            ; ecx vm, edx type, [esp+4] length, [esp+8] ref
    push ebp
    mov ebp, esp
    sub esp, 16
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx                        ; esi = the type
    xor eax, eax
    mov [ebp+N_PRE], eax
    mov [ebp+N_BLOCK], eax
    mov [ebp+N_YOUNG], eax
    IF JBV_GC_STRESS EQ 0
    ; the common case: a plain object in the pre-zeroed young region, a free handle
    cmp BYTE PTR [esi+C_ARRAY_KIND], 0
    jne nw_general
    mov eax, [ebx+VM_OBJECT_COUNT]
    cmp eax, [ebx+VM_HANDLE_CAPACITY]
    jae nw_general
    test WORD PTR [esi+C_FLAGS], F_INTERFACE or F_ABSTRACT
    jnz nw_general
    mov edi, [esi+C_INSTANCE_SLOTS]
    lea edi, [edi*4+8]                  ; the spare word, the header, the fields
    cmp edi, 4 + SMALL
    ja nw_general
    mov eax, [ebx+VM_NURSERY]
    add eax, [ebx+VM_NURSERY_SIZE]
    sub eax, [ebx+VM_NURSERY_TOP]
    cmp eax, edi
    jb nw_general
    mov eax, [ebx+VM_HEAP_LIMIT]
    sub eax, [ebx+VM_HEAP_BYTES]
    jb nw_general
    cmp eax, edi
    jb nw_general
    mov eax, [ebx+VM_NURSERY_TOP]
    add [ebx+VM_NURSERY_TOP], edi
    add [ebx+VM_HEAP_BYTES], edi
    lea edi, [eax+4]                    ; the object
    mov [edi], esi
    call take_handle
    mov ecx, [ebx+VM_HANDLES]
    mov [ecx+edx*4], edi
    mov ecx, [ebx+VM_YOUNG_MAP]
    bts [ecx], edx
    jmp nw_ref
nw_general:
    ENDIF
    cmp BYTE PTR [esi+C_ARRAY_KIND], 0
    je nw_plain
    mov eax, [ebp+8]
    test eax, eax
    mov ecx, S_NEGATIVE
    js nw_fail
    movzx ecx, BYTE PTR [esi+C_ARRAY_KIND] ; the element size
    mov edx, 1
    cmp cl, 'Z'
    je @F
    cmp cl, 'B'
    je @F
    inc edx
    cmp cl, 'C'
    je @F
    cmp cl, 'S'
    je @F
    mov edx, 8
    cmp cl, 'J'
    je @F
    cmp cl, 'D'
    je @F
    mov edx, 4
@@:
    mul edx
    test edx, edx
    jnz nw_oom
    test eax, eax
    js nw_oom
    mov DWORD PTR [ebp+N_PRE], 4
    jmp nw_bytes
nw_plain:
    mov ecx, S_LINKAGE
    test WORD PTR [esi+C_FLAGS], F_INTERFACE or F_ABSTRACT
    jnz nw_fail
    mov eax, [esi+C_INSTANCE_SLOTS]
    shl eax, 2
nw_bytes:
    add eax, [ebp+N_PRE]
    add eax, 4+3
    and eax, -4
    mov [ebp+N_BYTES], eax
    cmp eax, [ebx+VM_HEAP_LIMIT]
    ja nw_oom
    IF JBV_GC_STRESS
    ; stress: move objects every N allocations (a full compacting collection every 32nd)
    cmp DWORD PTR [ebx+VM_HANDLES], 0
    je nw_stressed
    inc DWORD PTR [ebx+VM_STRESS]
    mov eax, [ebx+VM_STRESS]
    xor edx, edx
    mov ecx, JBV_GC_STRESS
    div ecx
    test edx, edx
    jnz nw_stressed
    mov eax, [ebx+VM_STRESS]
    xor edx, edx
    mov ecx, 32*JBV_GC_STRESS
    div ecx
    test edx, edx
    jz @F
    call minor
    jmp nw_stressed
@@:
    mov eax, 1
    call collect
nw_stressed:
    ENDIF
    call nw_room
    jae @F
    mov eax, [ebx+VM_OBJECT_COUNT]
    cmp eax, [ebx+VM_HANDLE_CAPACITY]
    jb nw_space
@@:
    mov eax, 1
    call collect
    ; grow the handle table early when it stays mostly live: collections stay amortized
    mov eax, [ebx+VM_HANDLE_CAPACITY]
    mov ecx, eax
    sub ecx, [ebx+VM_OBJECT_COUNT]
    shr eax, 2
    cmp ecx, eax
    jae nw_space
    cmp DWORD PTR [ebx+VM_HANDLE_CAPACITY], 0FFFFFFh
    jae nw_space
    call grow_handles
nw_space:
    call nw_room
    jae nw_oom
    mov edi, [ebp+N_BYTES]
    cmp edi, YOUNG_MAX / 8
    ja nw_old
    cmp DWORD PTR [ebx+VM_NURSERY], 0   ; the young region, lazily: 1/8 of the heap up to 1 MiB
    jne nw_young
    cmp BYTE PTR [ebx+VM_NURSERY_OFF], 0
    jne nw_old
    mov edx, [ebx+VM_HEAP_LIMIT]
    shr edx, 3
    cmp edx, YOUNG_MAX
    jbe @F
    mov edx, YOUNG_MAX
@@:
    and edx, -4
    cmp edx, 16384
    jb nw_no_young
    push edx
    mov ecx, ebx
    call @jbv_alloc@8
    pop edx
    test eax, eax
    jz nw_no_young
    mov [ebx+VM_NURSERY], eax
    mov [ebx+VM_NURSERY_TOP], eax
    mov [ebx+VM_NURSERY_SIZE], edx
    jmp nw_young
nw_no_young:
    mov BYTE PTR [ebx+VM_NURSERY_OFF], 1
    jmp nw_old
nw_young:                               ; arrays up to 1/8 of the region start young too
    cmp edi, SMALL
    jbe @F
    mov eax, [ebx+VM_NURSERY_SIZE]
    shr eax, 3
    lea ecx, [edi+4]
    cmp ecx, eax
    ja nw_old
@@:
    call nw_young_room
    jb @F
    call minor
@@:
    cmp DWORD PTR [ebx+VM_NURSERY], 0
    je nw_old
    call nw_young_room
    jae nw_old
    mov eax, [ebx+VM_NURSERY_TOP]
    lea ecx, [eax+4]
    mov [ebp+N_BLOCK], ecx
    lea ecx, [edi+4]
    add [ebx+VM_NURSERY_TOP], ecx
    add [ebx+VM_HEAP_BYTES], ecx
    IF JBV_GC_STRESS
    mov edx, eax                        ; poisoned after each minor collection
    call zero_words
    ENDIF
    mov DWORD PTR [ebp+N_YOUNG], 1
nw_old:
    cmp DWORD PTR [ebp+N_BLOCK], 0
    jne nw_place
    mov eax, edi
    call block_alloc
    test eax, eax
    jnz nw_old_got
    mov eax, 1
    call collect
    mov eax, edi
    call block_alloc
    test eax, eax
    jnz nw_old_got
    call drop_young
    test eax, eax
    jz nw_oom
    mov eax, edi
    call block_alloc
    test eax, eax
    jz nw_oom
nw_old_got:
    mov [ebp+N_BLOCK], eax
    add [ebx+VM_HEAP_BYTES], edi
nw_place:
    mov eax, [ebx+VM_OBJECT_COUNT]      ; only when no collection could free a handle: grow
    cmp eax, [ebx+VM_HANDLE_CAPACITY]
    jb nw_handle
    call grow_handles
    test eax, eax
    jz nw_handle
    push eax
    cmp DWORD PTR [ebp+N_YOUNG], 0
    je @F
    lea ecx, [edi+4]
    sub [ebx+VM_NURSERY_TOP], ecx
    sub [ebx+VM_HEAP_BYTES], ecx
    mov edx, [ebx+VM_NURSERY_TOP]
    call zero_words
    pop eax
    jmp nw_ret
@@:
    sub [ebx+VM_HEAP_BYTES], edi
    mov eax, [ebp+N_BLOCK]
    mov ecx, edi
    call block_free
    pop eax
    jmp nw_ret
nw_handle:
    mov edi, [ebp+N_BLOCK]
    cmp DWORD PTR [ebp+N_PRE], 0
    je @F
    mov eax, [ebp+8]
    mov [edi], eax
    add edi, 4
@@:
    mov [edi], esi                      ; edi = the object
    call take_handle
    mov ecx, [ebx+VM_HANDLES]
    mov [ecx+edx*4], edi
    cmp DWORD PTR [ebp+N_YOUNG], 0
    je @F
    mov ecx, [ebx+VM_YOUNG_MAP]
    bts [ecx], edx
    jmp nw_ref
@@:
    cmp DWORD PTR [ebx+VM_NURSERY], 0
    je nw_ref
    push edx
    mov eax, edi
    lea edx, [ebx+VM_RECENT]
    call push_pointer
    pop edx
    jnz nw_ref
    mov BYTE PTR [ebx+VM_REMEMBERED_OVERFLOW], 1
nw_ref:
    call handle_ref
    mov ecx, [ebp+12]
    mov [ecx], eax
    xor eax, eax
    jmp nw_ret
nw_oom:
    mov ecx, S_OOM
nw_fail:
    mov eax, ecx
nw_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
nw_room:                                ; CF = the heap has room for N_BYTES
    mov eax, [ebx+VM_HEAP_LIMIT]
    sub eax, [ebx+VM_HEAP_BYTES]
    jb @F
    cmp [ebp+N_BYTES], eax
    ja @F
    stc
    ret
@@:
    clc
    ret
nw_young_room:                          ; CF = the young region has 4 + edi bytes (eax, ecx used)
    mov eax, [ebx+VM_NURSERY]
    add eax, [ebx+VM_NURSERY_SIZE]
    sub eax, [ebx+VM_NURSERY_TOP]
    lea ecx, [edi+4]
    cmp eax, ecx
    cmc
    ret
@jbv_new@16 ENDP

@jbv_free_heap@4 PROC SYSCALL       ; ecx vm: every block and table
    push ebx
    push esi
    mov ebx, ecx
    mov esi, 1
fh_handle:
    cmp esi, [ebx+VM_HANDLE_CAPACITY]
    ja fh_chunks
    mov eax, [ebx+VM_USED_MAP]
    bt [eax], esi
    jnc fh_next
    mov eax, [ebx+VM_HANDLES]
    mov eax, [eax+esi*4]
    push eax
    YOUNG
    pop eax
    jb fh_next
    push eax
    call block_size
    mov edx, eax
    pop eax
    cmp edx, SMALL
    jbe fh_next
    call block_start
    mov edx, eax
    mov ecx, ebx
    call @jbv_free@8
fh_next:
    inc esi
    jmp fh_handle
fh_chunks:
    mov edx, [ebx+VM_CHUNKS]
    test edx, edx
    jz @F
    mov eax, [edx]
    mov [ebx+VM_CHUNKS], eax
    mov ecx, ebx
    call @jbv_free@8
    jmp fh_chunks
@@:
    mov edx, [ebx+VM_NURSERY]
    call gh_free
    mov edx, [ebx+VM_HANDLES]
    call gh_free
    mov edx, [ebx+VM_GENERATIONS]
    call gh_free
    mov edx, [ebx+VM_MARKS]
    call gh_free
    mov edx, [ebx+VM_INTERNED_MAP]
    call gh_free
    mov edx, [ebx+VM_USED_MAP]
    call gh_free
    mov edx, [ebx+VM_YOUNG_MAP]
    call gh_free
    mov edx, [ebx+VM_PINS]
    call gh_free
    mov edx, [ebx+VM_REMEMBERED]
    call gh_free
    mov edx, [ebx+VM_RECENT]
    call gh_free
    pop esi
    pop ebx
    ret
@jbv_free_heap@4 ENDP

; multianewarray: one dimension per level (each level is a call: depth and budget apply)
@jbv_multi_array@20 PROC SYSCALL    ; ecx vm, edx type, [esp+4] sizes, [esp+8] dimensions, [esp+12] ref
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    push 0                              ; [ebp-16] the parent
    mov ebx, ecx
    mov esi, edx
    mov eax, [ebx+VM_DEPTH]
    cmp eax, [ebx+VM_MAX_DEPTH]
    jae ma_limit
    mov eax, [ebx+VM_REMAINING]
    or eax, [ebx+VM_REMAINING+4]
    jz ma_limit
    sub DWORD PTR [ebx+VM_REMAINING], 1
    sbb DWORD PTR [ebx+VM_REMAINING+4], 0
    inc DWORD PTR [ebx+VM_DEPTH]
    lea eax, [ebp-16]
    push eax
    mov eax, [ebp+8]
    push DWORD PTR [eax]
    mov edx, esi
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz ma_out
    push DWORD PTR [ebp-16]
    push ebx
    call jbv_retain
    add esp, 8
    test eax, eax
    jnz ma_out
    cmp BYTE PTR [ebp+12], 1
    jbe ma_release
    xor edi, edi
ma_child:
    mov eax, [ebp+8]
    cmp edi, [eax]
    jae ma_release_ok
    push 0                              ; the child
    mov eax, esp
    push eax
    movzx eax, BYTE PTR [ebp+12]
    dec eax
    push eax
    mov eax, [ebp+8]
    add eax, 4
    push eax
    mov edx, [esi+C_COMPONENT]
    mov ecx, ebx
    call @jbv_multi_array@20
    pop ecx                             ; the child
    test eax, eax
    jnz ma_release
    mov eax, [ebp-16]                   ; the child allocation may have moved the parent
    and eax, 0FFFFFFh
    mov edx, [ebx+VM_HANDLES]
    mov eax, [edx+eax*4]
    mov [eax+edi*4+DATA0], ecx
    push ecx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    inc edi
    jmp ma_child
ma_release_ok:
    xor eax, eax
ma_release:
    push eax
    push DWORD PTR [ebp-16]
    push ebx
    call jbv_release
    add esp, 8
    pop eax
ma_out:
    dec DWORD PTR [ebx+VM_DEPTH]
    test eax, eax
    jnz ma_ret
    mov ecx, [ebp+16]
    mov edx, [ebp-16]
    mov [ecx], edx
    jmp ma_ret
ma_limit:
    mov eax, S_LIMIT
ma_ret:
    add esp, 4
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret 12
@jbv_multi_array@20 ENDP

jbv_set_heap_limit PROC EXPORT      ; (vm, bytes)
    push ebx
    mov ebx, [esp+8]
    mov edx, [esp+12]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz hl_ret
    test edx, edx
    jz hl_ret
    cmp edx, [ebx+VM_MAX_MEMORY]
    ja hl_ret
    mov eax, S_BUSY
    cmp DWORD PTR [ebx+VM_DEPTH], 0
    jne hl_ret
    mov eax, 1
    call collect
    mov edx, [esp+12]
    mov eax, S_LIMIT
    cmp [ebx+VM_HEAP_BYTES], edx
    ja hl_ret
    mov [ebx+VM_HEAP_LIMIT], edx
    xor eax, eax
hl_ret:
    pop ebx
    ret
jbv_set_heap_limit ENDP
jbv_heap_stats PROC EXPORT          ; (vm, out)
    mov ecx, [esp+4]
    mov edx, [esp+8]
    mov eax, S_BAD_ARG
    test ecx, ecx
    jz @F
    test edx, edx
    jz @F
    mov eax, [ecx+VM_HEAP_BYTES]
    mov [edx], eax
    mov eax, [ecx+VM_OBJECT_COUNT]
    mov [edx+4], eax
    mov eax, [ecx+VM_COLLECTIONS]
    mov [edx+8], eax
    mov eax, [ecx+VM_COLLECTIONS+4]
    mov [edx+12], eax
    xor eax, eax
@@:
    ret
jbv_heap_stats ENDP

; array elements as slot bits: Z 0/1, B and S sign-extended, C zero-extended, J/D two slots
@jbv_array_get@12 PROC SYSCALL      ; ecx array, edx index, [esp+4] kind -> edx:eax
    mov al, [esp+4]
    cmp al, 'Z'
    je ag_byte
    cmp al, 'B'
    je ag_signed_byte
    cmp al, 'C'
    je ag_char
    cmp al, 'S'
    je ag_short
    cmp al, 'J'
    je ag_wide
    cmp al, 'D'
    je ag_wide
    mov eax, [ecx+edx*4+DATA0]
    jmp ag_low
ag_byte:
    movzx eax, BYTE PTR [ecx+edx+DATA0]
    jmp ag_low
ag_signed_byte:
    movsx eax, BYTE PTR [ecx+edx+DATA0]
    jmp ag_low
ag_char:
    movzx eax, WORD PTR [ecx+edx*2+DATA0]
    jmp ag_low
ag_short:
    movsx eax, WORD PTR [ecx+edx*2+DATA0]
ag_low:
    xor edx, edx
    ret 4
ag_wide:
    mov eax, [ecx+edx*8+DATA0]
    mov edx, [ecx+edx*8+DATA0+4]
    ret 4
@jbv_array_get@12 ENDP
@jbv_array_set@20 PROC SYSCALL      ; ecx array, edx index, [esp+4] kind, [esp+8] bits
    mov al, [esp+4]
    cmp al, 'J'
    je as_wide
    cmp al, 'D'
    je as_wide
    push ebx
    mov ebx, [esp+12]
    cmp al, 'Z'
    je as_bool
    cmp al, 'B'
    je as_byte
    cmp al, 'C'
    je as_char
    cmp al, 'S'
    je as_char
    mov [ecx+edx*4+DATA0], ebx
    pop ebx
    ret 12
as_bool:
    and bl, 1
as_byte:
    mov [ecx+edx+DATA0], bl
    pop ebx
    ret 12
as_char:
    mov [ecx+edx*2+DATA0], bx
    pop ebx
    ret 12
as_wide:
    push ebx
    mov eax, [esp+12]
    mov ebx, [esp+16]
    mov [ecx+edx*8+DATA0], eax
    mov [ecx+edx*8+DATA0+4], ebx
    pop ebx
    ret 12
@jbv_array_set@20 ENDP
END

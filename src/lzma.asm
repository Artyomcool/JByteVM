; LZMA1 decoder.
; uint32_t jbv_unlzma_x86(JbvLzma *z): decodes until z->size bytes or an error/end
; marker, returns the number of bytes written. Size over speed: it runs when a JAR is
; opened. Registers: ebx range, esi code, edi pos, ebp z; probabilities are 11-bit uint16.
.686
.model flat, C
option casemap:none
PUBLIC jbv_unlzma_x86

Z_P     EQU 0       ; uint16_t *probabilities
Z_IN    EQU 4       ; next input byte
Z_END   EQU 8
Z_OUT   EQU 12
Z_SIZE  EQU 16
Z_LC    EQU 20
Z_LPM   EQU 24      ; (1 << lp) - 1
Z_PBM   EQU 28      ; (1 << pb) - 1
Z_STATE EQU 32
Z_REP0  EQU 36
Z_REP1  EQU 40
Z_REP2  EQU 44
Z_REP3  EQU 48
Z_PS    EQU 52      ; pos & pbm
Z_LEN   EQU 56      ; match length; the literal symbol while decoding one
Z_CODE  EQU 60      ; in: the first four code bytes
Z_TMP   EQU 64      ; the match byte of a literal after a match

; probability offsets in bytes (2 * the LZMA specification's indexes)
P_REP    EQU 384
P_G0     EQU 408
P_G1     EQU 432
P_G2     EQU 456
P_LONG   EQU 480
P_SLOT   EQU 864
P_SPEC   EQU 1376
P_ALIGN  EQU 1606
P_LEN    EQU 1638
P_REPLEN EQU 2666
P_LIT    EQU 3694

.code
; ecx = probability -> eax = the bit (ZF = !bit); uses edx
rc_bit:
    movzx eax, WORD PTR [ecx]
    mov edx, ebx
    shr edx, 11
    imul edx, eax
    cmp esi, edx
    jae rb_one
    mov ebx, edx
    mov edx, 2048
    sub edx, eax
    shr edx, 5
    add [ecx], dx
    xor eax, eax
    jmp rb_norm
rb_one:
    sub ebx, edx
    sub esi, edx
    shr eax, 5
    sub [ecx], ax
    xor eax, eax
    inc eax
rb_norm:
    call rc_norm
    test eax, eax
    ret
; range below 2^24: shift in the next byte (0 past the end); uses edx
rc_norm:
    cmp ebx, 1000000h
    jae rn_ok
    shl ebx, 8
    shl esi, 8
    mov edx, [ebp+Z_IN]
    cmp edx, [ebp+Z_END]
    jae rn_ok
    inc DWORD PTR [ebp+Z_IN]
    movzx edx, BYTE PTR [edx]
    or esi, edx
rn_ok:
    ret
; bit tree: ecx = probabilities, edx = bits -> eax = 1 followed by the bits, first one highest
tree_m:
    push edx
    push ecx
    push 1
tm_loop:
    mov ecx, [esp]
    add ecx, ecx
    add ecx, [esp+4]
    call rc_bit
    mov ecx, [esp]
    lea ecx, [ecx*2+eax]
    mov [esp], ecx
    dec DWORD PTR [esp+8]
    jnz tm_loop
    pop eax
    add esp, 8
    ret
rc_tree:                ; -> the bits, first one highest
    call tree_m
    bsr ecx, eax
    btr eax, ecx
    ret
rc_rtree:               ; -> the bits, first one lowest
    call tree_m
    xor edx, edx
rt_loop:
    cmp eax, 1
    je rt_done
    shr eax, 1
    rcl edx, 1
    jmp rt_loop
rt_done:
    mov eax, edx
    ret
; length: ecx = its probabilities (choice, choice2, low[16][8], mid[16][8], high[256]) -> eax
rc_len:
    push ecx
    call rc_bit
    jnz len_mid
    pop ecx
    mov edx, [ebp+Z_PS]
    shl edx, 4
    lea ecx, [ecx+edx+4]
    mov edx, 3
    jmp rc_tree
len_mid:
    mov ecx, [esp]
    add ecx, 2
    call rc_bit
    pop ecx
    jnz len_high
    mov edx, [ebp+Z_PS]
    shl edx, 4
    lea ecx, [ecx+edx+260]
    mov edx, 3
    call rc_tree
    add eax, 8
    ret
len_high:
    add ecx, 516
    mov edx, 8
    call rc_tree
    add eax, 16
    ret
; state after a match: 7 (literal before) or 10, rep: 8 or 11, short rep: 9 or 11
NEXT_STATE MACRO low
    cmp DWORD PTR [ebp+Z_STATE], 7
    sbb edx, edx
    IF low EQ 9
    lea edx, [edx*2+11]
    ELSEIF low EQ 8
    lea edx, [edx+edx*2+11]
    ELSE
    lea edx, [edx+edx*2+10]
    ENDIF
    mov [ebp+Z_STATE], edx
ENDM

jbv_unlzma_x86 PROC
    push ebp
    push ebx
    push esi
    push edi
    mov ebp, [esp+20]
    or ebx, -1
    mov esi, [ebp+Z_CODE]
    xor edi, edi
main:
    cmp edi, [ebp+Z_SIZE]
    jae done
    mov eax, edi
    and eax, [ebp+Z_PBM]
    mov [ebp+Z_PS], eax
    mov ecx, [ebp+Z_STATE]
    shl ecx, 4
    add ecx, eax
    add ecx, ecx
    add ecx, [ebp+Z_P]
    call rc_bit
    jnz match
    ; literal: coder chosen by the previous byte's high bits and the position's low bits
    xor eax, eax
    test edi, edi
    jz @F
    mov edx, [ebp+Z_OUT]
    movzx eax, BYTE PTR [edx+edi-1]
@@:
    mov ecx, 8
    sub ecx, [ebp+Z_LC]
    shr eax, cl
    mov edx, edi
    and edx, [ebp+Z_LPM]
    mov ecx, [ebp+Z_LC]
    shl edx, cl
    add eax, edx
    imul eax, eax, 600h
    add eax, [ebp+Z_P]
    add eax, P_LIT
    push eax                            ; [esp] = the literal coder
    mov DWORD PTR [ebp+Z_LEN], 1
    cmp DWORD PTR [ebp+Z_STATE], 7
    jb lit_plain
    mov eax, edi
    sub eax, [ebp+Z_REP0]
    jbe lit_plain
    mov edx, [ebp+Z_OUT]
    movzx eax, BYTE PTR [edx+eax-1]
    mov [ebp+Z_TMP], eax
lit_matched:                            ; bits guided by the byte at rep0 until they differ
    mov eax, [ebp+Z_TMP]
    shr eax, 7
    and eax, 1
    shl DWORD PTR [ebp+Z_TMP], 1
    push eax
    inc eax
    shl eax, 8
    add eax, [ebp+Z_LEN]
    add eax, eax
    add eax, [esp+4]
    mov ecx, eax
    call rc_bit
    mov edx, [ebp+Z_LEN]
    lea edx, [edx*2+eax]
    mov [ebp+Z_LEN], edx
    pop edx
    cmp eax, edx
    jne lit_plain
    cmp DWORD PTR [ebp+Z_LEN], 100h
    jb lit_matched
lit_plain:
    mov eax, [ebp+Z_LEN]
    cmp eax, 100h
    jae lit_done
    add eax, eax
    add eax, [esp]
    mov ecx, eax
    call rc_bit
    mov edx, [ebp+Z_LEN]
    lea edx, [edx*2+eax]
    mov [ebp+Z_LEN], edx
    jmp lit_plain
lit_done:
    pop eax
    mov eax, [ebp+Z_LEN]
    mov edx, [ebp+Z_OUT]
    mov [edx+edi], al
    inc edi
    mov eax, [ebp+Z_STATE]              ; <4: 0, <10: -3, else -6
    xor edx, edx
    cmp eax, 4
    jb @F
    sub eax, 3
    cmp eax, 7
    jb st_one
    sub eax, 3
st_one:
    mov edx, eax
@@:
    mov [ebp+Z_STATE], edx
    jmp main
match:
    mov ecx, [ebp+Z_STATE]
    add ecx, ecx
    add ecx, [ebp+Z_P]
    push ecx                            ; [esp] = probabilities + 2 * state
    add ecx, P_REP
    call rc_bit
    jz new_match
    test edi, edi
    jz done_pop
    mov ecx, [esp]
    add ecx, P_G0
    call rc_bit
    jnz rep_g1
    mov ecx, [ebp+Z_STATE]
    shl ecx, 4
    add ecx, [ebp+Z_PS]
    add ecx, ecx
    add ecx, [ebp+Z_P]
    add ecx, P_LONG
    call rc_bit
    jnz rep_len
    pop eax                             ; one byte at rep0
    NEXT_STATE 9
    mov eax, [ebp+Z_REP0]
    cmp eax, edi
    jae done
    mov edx, [ebp+Z_OUT]
    mov ecx, edi
    sub ecx, eax
    mov al, [edx+ecx-1]
    mov [edx+edi], al
    inc edi
    jmp main
rep_g1:
    mov ecx, [esp]
    add ecx, P_G1
    call rc_bit
    mov eax, [ebp+Z_REP1]
    jz rep_set
    mov ecx, [esp]
    add ecx, P_G2
    call rc_bit
    mov eax, [ebp+Z_REP2]
    jz rep_shift
    mov eax, [ebp+Z_REP3]
    mov edx, [ebp+Z_REP2]
    mov [ebp+Z_REP3], edx
rep_shift:
    mov edx, [ebp+Z_REP1]
    mov [ebp+Z_REP2], edx
rep_set:
    mov edx, [ebp+Z_REP0]
    mov [ebp+Z_REP1], edx
    mov [ebp+Z_REP0], eax
rep_len:
    pop eax
    mov ecx, [ebp+Z_P]
    add ecx, P_REPLEN
    call rc_len
    mov [ebp+Z_LEN], eax
    NEXT_STATE 8
    jmp copy
new_match:
    pop eax
    mov eax, [ebp+Z_REP2]
    mov [ebp+Z_REP3], eax
    mov eax, [ebp+Z_REP1]
    mov [ebp+Z_REP2], eax
    mov eax, [ebp+Z_REP0]
    mov [ebp+Z_REP1], eax
    mov ecx, [ebp+Z_P]
    add ecx, P_LEN
    call rc_len
    mov [ebp+Z_LEN], eax
    NEXT_STATE 7
    cmp eax, 3
    jb @F
    mov eax, 3
@@:
    shl eax, 7
    add eax, [ebp+Z_P]
    lea ecx, [eax+P_SLOT]
    mov edx, 6
    call rc_tree                        ; eax = slot
    cmp eax, 4
    jb dist_set
    mov ecx, eax
    shr ecx, 1
    dec ecx                             ; direct bits
    mov edx, eax
    and edx, 1
    or edx, 2
    shl edx, cl                         ; distance base
    push edx
    cmp eax, 14
    jae dist_far
    sub edx, eax
    add edx, edx
    add edx, [ebp+Z_P]
    add edx, P_SPEC
    xchg ecx, edx
    call rc_rtree
    pop edx
    add eax, edx
    jmp dist_set
dist_far:
    sub ecx, 4                          ; direct bits, then four through the align coder
far_loop:
    dec ecx
    shr ebx, 1
    cmp esi, ebx
    jb @F
    sub esi, ebx
    mov eax, 1
    add ecx, 4
    shl eax, cl
    sub ecx, 4
    add [esp], eax
@@:
    call rc_norm
    test ecx, ecx
    jnz far_loop
    mov ecx, [ebp+Z_P]
    add ecx, P_ALIGN
    mov edx, 4
    call rc_rtree
    pop edx
    add eax, edx
    cmp eax, -1                         ; end marker
    je done
dist_set:
    mov [ebp+Z_REP0], eax
copy:
    mov eax, [ebp+Z_REP0]
    cmp eax, edi
    jae done
    mov ecx, [ebp+Z_LEN]
    add ecx, 2
    mov edx, [ebp+Z_OUT]
copy_loop:
    cmp edi, [ebp+Z_SIZE]
    jae main
    mov eax, edi
    sub eax, [ebp+Z_REP0]
    mov al, [edx+eax-1]
    mov [edx+edi], al
    inc edi
    dec ecx
    jnz copy_loop
    jmp main
done_pop:
    pop eax
done:
    mov eax, edi
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
jbv_unlzma_x86 ENDP
END

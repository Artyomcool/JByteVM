; Long, float and double bytecodes for the C interpreter on x86 (numeric.c is the
; reference and serves x64). JbvStatus jbv_numeric(uint8_t op, uint64_t a, uint64_t b,
; uint64_t *out), cdecl; results with Java semantics, 32-bit ones zero-extended.
; Float/double run in SSE2 (and x87 for remainder and 64-bit conversions), at the
; VM's FP environment: round to nearest, exceptions masked.
.686
.xmm
.model flat, C
option casemap:none
option noscoped
PUBLIC jbv_numeric
EXTERN _alldiv:PROC
EXTERN _allrem:PROC

A_LO EQU DWORD PTR [esp+8]
A_HI EQU DWORD PTR [esp+12]
B_LO EQU DWORD PTR [esp+16]
B_HI EQU DWORD PTR [esp+20]
OUTP EQU DWORD PTR [esp+24]
S_UNSUPPORTED EQU 6
S_DIVIDE EQU 9

.const
ALIGN 4
ops LABEL DWORD
    DWORD ladd, fadd_, dadd, bad, lsub, fsub_, dsub, bad, lmul, fmul_, dmul, bad        ; 97..108
    DWORD ldiv_, fdiv_, ddiv, bad, lrem, frem, drem, bad, lneg, fneg, dneg, bad        ; 109..120
    DWORD lshl, bad, lshr, bad, lushr, bad, land, bad, lor, bad, lxor, bad              ; 121..132
    DWORD i2l, i2f, i2d, l2i, l2f, l2d, f2i, f2l, f2d, d2i, d2l, d2f                    ; 133..144
    DWORD bad, bad, bad, lcmp, fcmpl, fcmpg, dcmpl, dcmpg                               ; 145..152

.code
jbv_numeric PROC
    movzx eax, BYTE PTR [esp+4]
    sub eax, 97
    cmp eax, 152 - 97
    ja bad
    jmp DWORD PTR ops[eax*4]
bad:
    mov eax, S_UNSUPPORTED
    ret
put32:
    xor edx, edx
put64:
    mov ecx, OUTP
    mov [ecx], eax
    mov [ecx+4], edx
    xor eax, eax
    ret
putx64:
    mov ecx, OUTP
    movq QWORD PTR [ecx], xmm0
    xor eax, eax
    ret
putx32:
    movd eax, xmm0
    jmp put32
; ---- long
ladd:
    mov eax, A_LO
    mov edx, A_HI
    add eax, B_LO
    adc edx, B_HI
    jmp put64
lsub:
    mov eax, A_LO
    mov edx, A_HI
    sub eax, B_LO
    sbb edx, B_HI
    jmp put64
lmul:
    mov eax, A_HI
    imul eax, B_LO
    mov ecx, B_HI
    imul ecx, A_LO
    add ecx, eax
    mov eax, A_LO
    mul B_LO
    add edx, ecx
    jmp put64
land:
    mov eax, A_LO
    mov edx, A_HI
    and eax, B_LO
    and edx, B_HI
    jmp put64
lor:
    mov eax, A_LO
    mov edx, A_HI
    or eax, B_LO
    or edx, B_HI
    jmp put64
lxor:
    mov eax, A_LO
    mov edx, A_HI
    xor eax, B_LO
    xor edx, B_HI
    jmp put64
lneg:
    mov eax, A_LO
    mov edx, A_HI
    neg eax
    adc edx, 0
    neg edx
    jmp put64
lshl:
    mov eax, A_LO
    mov edx, A_HI
    mov ecx, B_LO
    shld edx, eax, cl
    shl eax, cl
    test cl, 32
    jz put64
    mov edx, eax
    xor eax, eax
    jmp put64
lushr:
    mov eax, A_LO
    mov edx, A_HI
    mov ecx, B_LO
    shrd eax, edx, cl
    shr edx, cl
    test cl, 32
    jz put64
    mov eax, edx
    xor edx, edx
    jmp put64
lshr:
    mov eax, A_LO
    mov edx, A_HI
    mov ecx, B_LO
    shrd eax, edx, cl
    sar edx, cl
    test cl, 32
    jz put64
    mov eax, edx
    sar edx, 31
    jmp put64
ldiv_:
    mov ecx, OFFSET _alldiv
    jmp ldivide
lrem:
    mov ecx, OFFSET _allrem
ldivide:
    mov eax, B_LO
    or eax, B_HI
    jz div_zero
    mov eax, B_LO                       ; Long.MIN_VALUE / -1: the dividend, remainder 0
    and eax, B_HI
    inc eax
    jnz ld_go
    cmp A_LO, 0
    jne ld_go
    cmp A_HI, 80000000h
    jne ld_go
    mov eax, A_LO
    mov edx, A_HI
    cmp ecx, OFFSET _alldiv
    je put64
    xor eax, eax
    xor edx, edx
    jmp put64
ld_go:
    push B_HI                           ; each push moves the next operand to [esp+20]
    push B_HI
    push B_HI
    push B_HI
    call ecx                            ; callee pops the 16 bytes
    jmp put64
div_zero:
    mov eax, S_DIVIDE
    ret
; ---- float
fadd_:
    movss xmm0, DWORD PTR A_LO
    addss xmm0, DWORD PTR B_LO
    jmp putx32
fsub_:
    movss xmm0, DWORD PTR A_LO
    subss xmm0, DWORD PTR B_LO
    jmp putx32
fmul_:
    movss xmm0, DWORD PTR A_LO
    mulss xmm0, DWORD PTR B_LO
    jmp putx32
fdiv_:
    movss xmm0, DWORD PTR A_LO
    divss xmm0, DWORD PTR B_LO
    jmp putx32
fneg:
    mov eax, A_LO
    xor eax, 80000000h
    jmp put32
frem:                                   ; x87 FPREM: the exact truncating remainder
    fld DWORD PTR B_LO
    fld DWORD PTR A_LO
    call partial
    mov ecx, OUTP
    fstp DWORD PTR [ecx]
    mov DWORD PTR [ecx+4], 0
    xor eax, eax
    ret
partial:
    fprem
    fnstsw ax
    test ah, 4
    jnz partial
    fstp st(1)
    ret
; ---- double
dadd:
    movsd xmm0, QWORD PTR A_LO
    addsd xmm0, QWORD PTR B_LO
    jmp putx64
dsub:
    movsd xmm0, QWORD PTR A_LO
    subsd xmm0, QWORD PTR B_LO
    jmp putx64
dmul:
    movsd xmm0, QWORD PTR A_LO
    mulsd xmm0, QWORD PTR B_LO
    jmp putx64
ddiv:
    movsd xmm0, QWORD PTR A_LO
    divsd xmm0, QWORD PTR B_LO
    jmp putx64
dneg:
    mov eax, A_LO
    mov edx, A_HI
    xor edx, 80000000h
    jmp put64
drem:
    fld QWORD PTR B_LO
    fld QWORD PTR A_LO
    call partial
    mov ecx, OUTP
    fstp QWORD PTR [ecx]
    xor eax, eax
    ret
; ---- conversions
i2l:
    mov eax, A_LO
    cdq
    jmp put64
i2f:
    cvtsi2ss xmm0, A_LO
    jmp putx32
i2d:
    cvtsi2sd xmm0, A_LO
    jmp putx64
l2i:
    mov eax, A_LO
    jmp put32
l2f:                                    ; FILD is exact; the store rounds once
    fild QWORD PTR A_LO
    mov ecx, OUTP
    fstp DWORD PTR [ecx]
    mov DWORD PTR [ecx+4], 0
    xor eax, eax
    ret
l2d:
    fild QWORD PTR A_LO
    mov ecx, OUTP
    fstp QWORD PTR [ecx]
    xor eax, eax
    ret
f2d:
    cvtss2sd xmm0, DWORD PTR A_LO
    jmp putx64
d2f:
    cvtsd2ss xmm0, QWORD PTR A_LO
    jmp putx32
f2i:                                    ; NaN -> 0, overflow saturates
    cvttss2si eax, DWORD PTR A_LO
    cmp eax, 80000000h
    jne put32
    movss xmm0, DWORD PTR A_LO
    ucomiss xmm0, xmm0
    jp zero32
    test BYTE PTR [esp+11], 80h
    jnz put32
    dec eax
    jmp put32
d2i:
    cvttsd2si eax, QWORD PTR A_LO
    cmp eax, 80000000h
    jne put32
    movsd xmm0, QWORD PTR A_LO
    ucomisd xmm0, xmm0
    jp zero32
    test BYTE PTR [esp+15], 80h
    jnz put32
    dec eax
    jmp put32
zero32:
    xor eax, eax
    jmp put32
f2l:
    fld DWORD PTR A_LO
    mov dl, [esp+11]
    movss xmm0, DWORD PTR A_LO
    ucomiss xmm0, xmm0
    jmp to_long
d2l:
    fld QWORD PTR A_LO
    mov dl, [esp+15]
    movsd xmm0, QWORD PTR A_LO
    ucomisd xmm0, xmm0
to_long:                                ; FISTP with truncation; the indefinite value: NaN -> 0, saturate
    lahf
    sub esp, 12
    fnstcw [esp]
    mov cx, [esp]
    or cx, 0C00h
    mov [esp+2], cx
    fldcw [esp+2]
    fistp QWORD PTR [esp+4]
    fldcw [esp]
    mov cl, dl                          ; the sign byte
    mov ch, ah                          ; the unordered flag (PF in bit 2)
    mov eax, [esp+4]
    mov edx, [esp+8]
    add esp, 12
    cmp edx, 80000000h
    jne put64
    test eax, eax
    jnz put64
    test ch, 4
    jnz zero64
    test cl, 80h
    jnz put64
    dec eax
    dec edx
    jmp put64
zero64:
    xor eax, eax
    xor edx, edx
    jmp put64
; ---- comparisons
lcmp:
    mov eax, A_HI
    cmp eax, B_HI
    jl less
    jg more
    mov eax, A_LO
    cmp eax, B_LO
    jb less
    ja more
    jmp zero32
less:
    or eax, -1
    jmp put32
more:
    mov eax, 1
    jmp put32
fcmpl:
    movss xmm0, DWORD PTR A_LO
    ucomiss xmm0, DWORD PTR B_LO
    jp less
    jmp ordered
fcmpg:
    movss xmm0, DWORD PTR A_LO
    ucomiss xmm0, DWORD PTR B_LO
    jp more
    jmp ordered
dcmpl:
    movsd xmm0, QWORD PTR A_LO
    ucomisd xmm0, QWORD PTR B_LO
    jp less
    jmp ordered
dcmpg:
    movsd xmm0, QWORD PTR A_LO
    ucomisd xmm0, QWORD PTR B_LO
    jp more
ordered:
    jb less
    ja more
    jmp zero32
jbv_numeric ENDP
;
@jbv_kind@4 PROC SYSCALL            ; cl = a descriptor char -> eax = its slot kind
    xor eax, eax
    inc eax                             ; references: L [ P
    cmp cl, 'L'
    je @F
    cmp cl, '['
    je @F
    cmp cl, 'P'
    je @F
    mov al, 2
    cmp cl, 'J'
    je @F
    mov al, 4
    cmp cl, 'F'
    je @F
    inc eax
    cmp cl, 'D'
    je @F
    xor eax, eax
@@:
    ret
@jbv_kind@4 ENDP
; the operand and result kinds of a numeric opcode: a | b << 8 | result << 16 (b = 7: none)
@jbv_numeric_types@4 PROC SYSCALL   ; cl = op (97..152)
    movzx ecx, cl
    lea ecx, [ecx+ecx*2-97*3]
    movzx eax, BYTE PTR [numeric_kinds+ecx+2]
    shl eax, 8
    mov al, [numeric_kinds+ecx+1]
    shl eax, 8
    mov al, [numeric_kinds+ecx]
    ret
@jbv_numeric_types@4 ENDP
.const
numeric_kinds LABEL BYTE
    DB 2, 2, 2, 4, 4, 4, 5, 5, 5, 5, 5, 5, 2, 2, 2, 4, 4, 4, 5, 5, 5, 5, 5, 5
    DB 2, 2, 2, 4, 4, 4, 5, 5, 5, 5, 5, 5, 2, 2, 2, 4, 4, 4, 5, 5, 5, 5, 5, 5
    DB 2, 2, 2, 4, 4, 4, 5, 5, 5, 4, 4, 0, 2, 7, 2, 4, 7, 4, 5, 7, 5, 4, 4, 0
    DB 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    DB 2, 2, 2, 2, 2, 2, 2, 2, 2, 4, 4, 0, 0, 7, 2, 0, 7, 4, 0, 7, 5, 2, 7, 0
    DB 2, 7, 4, 2, 7, 5, 4, 7, 0, 4, 7, 2, 4, 7, 5, 5, 7, 0, 5, 7, 2, 5, 7, 4
    DB 4, 4, 0, 4, 4, 0, 4, 4, 0, 2, 2, 0, 4, 4, 0, 4, 4, 0, 5, 5, 0, 5, 5, 0
.code
END

; Float/double to Java text for x86 (decimal.c's jbv_decimal_text is the reference and
; serves x64): exact interval conversion with integer arithmetic only, the shortest
; admissible decimal with at least two digits, then Java's plain or E notation.
; uint32_t jbv_decimal_text_x86(uint32_t lo, uint32_t hi, int single, uint16_t *out)
; returns the number of chars written. Big numbers: dword n, then n little-endian dwords.
.686
.xmm
.model flat, C
option casemap:none
PUBLIC jbv_decimal_text_x86

BIG    EQU 516
B_R    EQU -BIG
B_S    EQU -2*BIG
B_LOW  EQU -3*BIG
B_UP   EQU -4*BIG
B_T    EQU -5*BIG
V_FB   EQU B_T-4        ; fraction bits
V_BIAS EQU B_T-8
V_EXP  EQU B_T-12       ; biased exponent
V_FR   EQU B_T-20       ; fraction (qword)
V_NEG  EQU B_T-24
V_EVEN EQU B_T-28
V_BEXP EQU B_T-32       ; binary exponent
V_DEXP EQU B_T-36       ; decimal exponent
V_N    EQU B_T-40       ; digits generated
V_SIG  EQU B_T-48       ; significand (qword)
V_LOWF EQU B_T-52
V_HIGF EQU B_T-56
V_LEN  EQU B_T-60
V_OUT  EQU B_T-64       ; output cursor
V_DIG  EQU B_T-112      ; 24 uint16 digits
FRAME  EQU 5*BIG+112

.const
s_nan  DB 'NaN', 0
s_inf  DB 'Infinity', 0
s_zero DB '0.0', 0

.code
; edi = a, edx:eax = x
big_set:
    mov [edi+4], eax
    mov [edi+8], edx
    cmp edx, 1
    sbb ecx, ecx
    add ecx, 2
    mov [edi], ecx
    ret
; edi = destination, esi = source
big_copy:
    push esi
    push edi
    mov ecx, [esi]
    inc ecx
    rep movsd
    pop edi
    pop esi
    ret
; edi = a, ecx = factor (kept)
big_mul:
    push ebx
    push esi
    xor ebx, ebx
    xor esi, esi
bm_loop:
    cmp esi, [edi]
    jae bm_end
    mov eax, [edi+esi*4+4]
    mul ecx
    add eax, ebx
    adc edx, 0
    mov [edi+esi*4+4], eax
    mov ebx, edx
    inc esi
    jmp bm_loop
bm_end:
    test ebx, ebx
    jz bm_ret
    mov [edi+esi*4+4], ebx
    inc DWORD PTR [edi]
bm_ret:
    pop esi
    pop ebx
    ret
; esi = a, edi = b -> eax = -1, 0 or 1
big_cmp:
    mov ecx, [esi]
    cmp ecx, [edi]
    jne bc_ne
bc_loop:
    test ecx, ecx
    jz bc_eq
    dec ecx
    mov eax, [esi+ecx*4+4]
    cmp eax, [edi+ecx*4+4]
    je bc_loop
bc_ne:
    sbb eax, eax
    or eax, 1
    ret
bc_eq:
    xor eax, eax
    ret
; edi = a -= esi = b (a >= b)
big_sub:
    push ebx
    xor ebx, ebx
    xor ecx, ecx
bs_loop:
    cmp ecx, [edi]
    jae bs_trim
    xor eax, eax
    cmp ecx, [esi]
    jae @F
    mov eax, [esi+ecx*4+4]
@@:
    mov edx, [edi+ecx*4+4]
    shr ebx, 1
    sbb edx, eax
    setc bl
    mov [edi+ecx*4+4], edx
    inc ecx
    jmp bs_loop
bs_trim:
    mov ecx, [edi]
bs_t:
    cmp ecx, 1
    jbe bs_ret
    cmp DWORD PTR [edi+ecx*4], 0
    jne bs_ret
    dec ecx
    jmp bs_t
bs_ret:
    mov [edi], ecx
    pop ebx
    ret
; edi = a += esi = b
big_add:
    push ebx
    xor ebx, ebx
    xor ecx, ecx
ba_loop:
    cmp ecx, [edi]
    jb ba_do
    cmp ecx, [esi]
    jae ba_end
ba_do:
    xor eax, eax
    cmp ecx, [edi]
    jae @F
    mov eax, [edi+ecx*4+4]
@@:
    xor edx, edx
    cmp ecx, [esi]
    jae @F
    mov edx, [esi+ecx*4+4]
@@:
    shr ebx, 1
    adc eax, edx
    setc bl
    mov [edi+ecx*4+4], eax
    inc ecx
    jmp ba_loop
ba_end:
    mov [edi], ecx
    test ebx, ebx
    jz ba_ret
    mov DWORD PTR [edi+ecx*4+4], 1
    inc DWORD PTR [edi]
ba_ret:
    pop ebx
    ret
; R, LOW and UP times ecx (in the caller's frame)
mul3:
    lea edi, [ebp+B_R]
    call big_mul
    lea edi, [ebp+B_LOW]
    call big_mul
    lea edi, [ebp+B_UP]
    jmp big_mul
; eax = comparison -> eax = (below, or equal with an even significand)
admit:
    test eax, eax
    js ad_one
    jnz ad_zero
    mov eax, [ebp+V_EVEN]
    ret
ad_one:
    mov eax, 1
    ret
ad_zero:
    xor eax, eax
    ret
; edx:eax decimal digits as uint16 at edi (advanced) -> eax = count
utoa:
    push ebx
    push esi
    sub esp, 24
    xor esi, esi
    mov ecx, 10
ut_loop:
    mov ebx, eax
    mov eax, edx
    xor edx, edx
    div ecx
    xchg eax, ebx
    div ecx
    add dl, '0'
    mov [esp+esi], dl
    inc esi
    mov edx, ebx
    mov ebx, eax
    or ebx, edx
    jnz ut_loop
    mov eax, esi
ut_copy:
    dec esi
    movzx ecx, BYTE PTR [esp+esi]
    mov [edi], cx
    add edi, 2
    test esi, esi
    jnz ut_copy
    add esp, 24
    pop esi
    pop ebx
    ret

jbv_decimal_text_x86 PROC
    push ebp
    mov ebp, esp
    sub esp, FRAME
    push ebx
    push esi
    push edi
    mov edi, [ebp+20]
    cmp DWORD PTR [ebp+16], 0
    mov eax, 52
    mov ebx, 7FFh
    mov ecx, 1023
    je @F
    mov eax, 23
    mov ebx, 0FFh
    mov ecx, 127
@@:
    mov [ebp+V_FB], eax
    mov [ebp+V_BIAS], ecx
    movq xmm0, QWORD PTR [ebp+8]
    movd xmm1, eax
    movdqa xmm2, xmm0
    psrlq xmm2, xmm1
    movd edx, xmm2
    and edx, ebx
    mov [ebp+V_EXP], edx                ; exponent
    pcmpeqd xmm3, xmm3
    psllq xmm3, xmm1
    pandn xmm3, xmm0
    movq QWORD PTR [ebp+V_FR], xmm3     ; fraction
    mov eax, [ebp+12]
    cmp DWORD PTR [ebp+16], 0
    je @F
    mov eax, [ebp+8]
@@:
    shr eax, 31
    mov [ebp+V_NEG], eax
    mov eax, [ebp+V_FR]
    or eax, [ebp+V_FR+4]
    xor esi, esi
    cmp edx, ebx
    jne not_max
    mov esi, OFFSET s_inf
    test eax, eax
    jz sign
    mov esi, OFFSET s_nan
    mov DWORD PTR [ebp+V_NEG], 0
    jmp sign
not_max:
    or edx, eax
    jnz sign
    mov esi, OFFSET s_zero
sign:
    cmp DWORD PTR [ebp+V_NEG], 0
    je @F
    mov ax, '-'
    stosw
@@:
    test esi, esi
    jz finite
special:
    movzx eax, BYTE PTR [esi]
    test eax, eax
    jz finish
    stosw
    inc esi
    jmp special
finite:
    mov [ebp+V_OUT], edi
    mov eax, [ebp+V_EXP]
    mov ecx, eax
    test eax, eax
    jnz @F
    inc eax
@@:
    sub eax, [ebp+V_BIAS]
    sub eax, [ebp+V_FB]
    sub eax, 2
    mov [ebp+V_BEXP], eax
    movq xmm0, QWORD PTR [ebp+V_FR]
    test ecx, ecx
    jz @F
    mov eax, 1
    movd xmm2, eax
    movd xmm1, DWORD PTR [ebp+V_FB]
    psllq xmm2, xmm1
    por xmm0, xmm2                      ; m
@@:
    movd eax, xmm0
    not eax
    and eax, 1
    mov [ebp+V_EVEN], eax
    psllq xmm0, 2                       ; r = 4m
    movd eax, xmm0
    psrlq xmm0, 32
    movd edx, xmm0
    lea edi, [ebp+B_R]
    call big_set
    mov eax, 1
    xor edx, edx
    lea edi, [ebp+B_S]
    call big_set
    mov eax, [ebp+V_FR]                 ; lower margin: 2, or 1 at a power of two
    or eax, [ebp+V_FR+4]
    mov eax, 2
    jnz @F
    cmp DWORD PTR [ebp+V_EXP], 1
    jbe @F
    dec eax
@@:
    xor edx, edx
    lea edi, [ebp+B_LOW]
    call big_set
    mov eax, 2
    xor edx, edx
    lea edi, [ebp+B_UP]
    call big_set
bx_pos:
    cmp DWORD PTR [ebp+V_BEXP], 0
    jle bx_neg
    mov ecx, 2
    call mul3
    dec DWORD PTR [ebp+V_BEXP]
    jmp bx_pos
bx_neg:
    cmp DWORD PTR [ebp+V_BEXP], 0
    jge bx_done
    lea edi, [ebp+B_S]
    mov ecx, 2
    call big_mul
    inc DWORD PTR [ebp+V_BEXP]
    jmp bx_neg
bx_done:
    mov DWORD PTR [ebp+V_DEXP], 0
    lea edi, [ebp+B_T]
    lea esi, [ebp+B_S]
    call big_copy
    mov ecx, 10
    call big_mul
up_loop:                                ; scale s up to r's decade
    lea esi, [ebp+B_R]
    lea edi, [ebp+B_T]
    call big_cmp
    test eax, eax
    js down_loop
    lea edi, [ebp+B_S]
    lea esi, [ebp+B_T]
    call big_copy
    lea edi, [ebp+B_T]
    mov ecx, 10
    call big_mul
    inc DWORD PTR [ebp+V_DEXP]
    jmp up_loop
down_loop:
    lea esi, [ebp+B_R]
    lea edi, [ebp+B_S]
    call big_cmp
    test eax, eax
    jns digits
    mov ecx, 10
    call mul3
    dec DWORD PTR [ebp+V_DEXP]
    jmp down_loop
digits:
    xor eax, eax
    mov [ebp+V_N], eax
    mov [ebp+V_SIG], eax
    mov [ebp+V_SIG+4], eax
dg_loop:
    xor ebx, ebx
dg_sub:
    lea esi, [ebp+B_R]
    lea edi, [ebp+B_S]
    call big_cmp
    test eax, eax
    js dg_got
    lea edi, [ebp+B_R]
    lea esi, [ebp+B_S]
    call big_sub
    inc ebx
    jmp dg_sub
dg_got:
    mov eax, [ebp+V_SIG+4]
    imul ecx, eax, 10
    mov eax, [ebp+V_SIG]
    mov edx, 10
    mul edx
    add edx, ecx
    add eax, ebx
    adc edx, 0
    mov [ebp+V_SIG], eax
    mov [ebp+V_SIG+4], edx
    inc DWORD PTR [ebp+V_N]
    lea esi, [ebp+B_R]
    lea edi, [ebp+B_LOW]
    call big_cmp
    call admit
    mov [ebp+V_LOWF], eax
    lea edi, [ebp+B_T]
    lea esi, [ebp+B_R]
    call big_copy
    lea esi, [ebp+B_UP]
    call big_add
    lea esi, [ebp+B_S]                  ; s against r + upper: the high side admits when s < it
    lea edi, [ebp+B_T]
    call big_cmp
    call admit
    mov [ebp+V_HIGF], eax
    cmp DWORD PTR [ebp+V_N], 2
    jb dg_next
    or eax, [ebp+V_LOWF]
    jz dg_next
    lea edi, [ebp+B_T]
    lea esi, [ebp+B_R]
    call big_copy
    mov ecx, 2
    call big_mul
    lea esi, [ebp+B_T]
    lea edi, [ebp+B_S]
    call big_cmp
    cmp DWORD PTR [ebp+V_HIGF], 0
    je format
    cmp DWORD PTR [ebp+V_LOWF], 0
    je dg_up
    test eax, eax
    jg dg_up
    jnz format
    test BYTE PTR [ebp+V_SIG], 1
    jz format
dg_up:
    add DWORD PTR [ebp+V_SIG], 1
    adc DWORD PTR [ebp+V_SIG+4], 0
    jmp format
dg_next:
    mov ecx, 10
    call mul3
    jmp dg_loop
format:
    mov eax, [ebp+V_SIG]
    mov edx, [ebp+V_SIG+4]
    lea edi, [ebp+V_DIG]
    call utoa
    cmp eax, [ebp+V_N]
    jbe trim
    inc DWORD PTR [ebp+V_DEXP]
trim:
    cmp eax, 1
    jbe trimmed
    cmp WORD PTR [ebp+V_DIG+eax*2-2], '0'
    jne trimmed
    dec eax
    jmp trim
trimmed:
    mov [ebp+V_LEN], eax
    mov edi, [ebp+V_OUT]
    lea esi, [ebp+V_DIG]
    mov ecx, [ebp+V_DEXP]
    cmp ecx, -3
    jl sci
    cmp ecx, 7
    jge sci
    test ecx, ecx
    jns plain
    mov ax, '0'                         ; 0.00ddd
    stosw
    mov ax, '.'
    stosw
    neg ecx
    dec ecx
    mov ax, '0'
    rep stosw
    mov ecx, [ebp+V_LEN]
    rep movsw
    jmp finish
plain:
    lea edx, [ecx+1]                    ; the point after dexp + 1 digits
    xor ebx, ebx
pl_loop:
    cmp ebx, edx
    jb pl_do
    cmp ebx, [ebp+V_LEN]
    jae pl_end
pl_do:
    cmp ebx, edx
    jne @F
    mov ax, '.'
    stosw
@@:
    mov ax, '0'
    cmp ebx, [ebp+V_LEN]
    jae @F
    mov ax, [esi+ebx*2]
@@:
    stosw
    inc ebx
    jmp pl_loop
pl_end:
    cmp [ebp+V_LEN], edx
    ja finish
    mov ax, '.'
    stosw
    mov ax, '0'
    stosw
    jmp finish
sci:
    movsw
    mov ax, '.'
    stosw
    mov ecx, [ebp+V_LEN]
    dec ecx
    jnz @F
    mov ax, '0'
    stosw
    jmp sci_exp
@@:
    rep movsw
sci_exp:
    mov ax, 'E'
    stosw
    mov eax, [ebp+V_DEXP]
    test eax, eax
    jns @F
    neg eax
    push eax
    mov ax, '-'
    stosw
    pop eax
@@:
    xor edx, edx
    call utoa
finish:
    mov eax, edi
    sub eax, [ebp+20]
    shr eax, 1
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_decimal_text_x86 ENDP
END

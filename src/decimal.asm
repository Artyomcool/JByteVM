; Float/double to Java text and back: exact interval conversion with integer arithmetic only, the shortest
; admissible decimal with at least two digits, then Java's plain or E notation.
; uint32_t jbv_decimal_text_x86(uint32_t lo, uint32_t hi, int single, uint16_t *out)
; returns the number of chars written. Big numbers: dword n, then n little-endian dwords.
.686
.xmm
.model flat, C
option casemap:none
PUBLIC jbv_decimal_text_x86
PUBLIC jbv_parse_fp_x86

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

; ---- parsing: int jbv_parse_fp_x86(const uint16_t *s, uint32_t n, int single, uint64_t *out)
; 0 with *out set, 1 for a malformed number. Up to 768
; significant decimal (300 hex) digits kept exactly, the rest only as a sticky bit.
F_R     EQU -BIG
F_S     EQU -2*BIG
F_T     EQU -3*BIG
L_END   EQU F_T-4
L_BASE  EQU F_T-8
L_KEPT  EQU F_T-12
L_LIMIT EQU F_T-16
L_ANY   EQU F_T-20
L_DOT   EQU F_T-24
L_STICK EQU F_T-28
L_FRAC  EQU F_T-32
L_DROP  EQU F_T-36
L_EXP   EQU F_T-40
L_FB    EQU F_T-44
L_BIAS  EQU F_T-48
L_MIN   EQU F_T-52
L_MAX   EQU F_T-56
L_E     EQU F_T-60
L_VAL   EQU F_T-68      ; qword
L_SIGN  EQU F_T-76      ; qword: the sign bit in place
L_INF   EQU F_T-84      ; qword
PFRAME  EQU 3*BIG+84

; edi = a += ecx (small)
big_adds:
    xor edx, edx
as_loop:
    test ecx, ecx
    jz as_ret
    cmp edx, [edi]
    jae as_ext
    add [edi+edx*4+4], ecx
    mov ecx, 0
    adc ecx, 0
    inc edx
    jmp as_loop
as_ext:
    mov [edi+edx*4+4], ecx
    inc DWORD PTR [edi]
as_ret:
    ret
; edi = a <<= ecx bits
big_shl:
    jecxz bsh_ret
    push ecx
    mov ecx, 2
    call big_mul
    pop ecx
    dec ecx
    jmp big_shl
bsh_ret:
    ret
; edi = a >>= 1
big_half:
    mov ecx, [edi]
    clc
bh_loop:
    rcr DWORD PTR [edi+ecx*4], 1
    dec ecx
    jnz bh_loop
    mov ecx, [edi]
    cmp ecx, 1
    jbe bh_ret
    cmp DWORD PTR [edi+ecx*4], 0
    jne bh_ret
    dec DWORD PTR [edi]
bh_ret:
    ret
; esi = a -> eax = its bit length
bitlen:
    mov ecx, [esi]
    mov eax, [esi+ecx*4]
    dec ecx
    shl ecx, 5
    bsr eax, eax
    jz bl_zero
    lea eax, [ecx+eax+1]
    ret
bl_zero:
    mov eax, ecx
    ret
; ZF = s[ebx..end) is exactly the ASCII string at edi (esi = s)
match_word:
    mov ecx, ebx
mw_loop:
    movzx eax, BYTE PTR [edi]
    cmp ecx, [ebp+L_END]
    je mw_end
    test eax, eax
    jz mw_no
    cmp ax, [esi+ecx*2]
    jne mw_ret
    inc edi
    inc ecx
    jmp mw_loop
mw_end:
    test eax, eax
mw_ret:
    ret
mw_no:
    test esp, esp
    ret

jbv_parse_fp_x86 PROC
    push ebp
    mov ebp, esp
    sub esp, PFRAME
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    xor eax, eax
    mov [ebp+L_SIGN], eax
    mov [ebp+L_SIGN+4], eax
    mov [ebp+L_INF], eax
    mov [ebp+L_INF+4], eax
    cmp DWORD PTR [ebp+16], eax
    mov DWORD PTR [ebp+L_FB], 52
    mov DWORD PTR [ebp+L_BIAS], 1023
    mov DWORD PTR [ebp+L_MIN], -1022
    mov DWORD PTR [ebp+L_MAX], 1023
    mov DWORD PTR [ebp+L_INF+4], 7FF00000h
    je @F
    mov DWORD PTR [ebp+L_FB], 23
    mov DWORD PTR [ebp+L_BIAS], 127
    mov DWORD PTR [ebp+L_MIN], -126
    mov DWORD PTR [ebp+L_MAX], 127
    mov DWORD PTR [ebp+L_INF+4], 0
    mov DWORD PTR [ebp+L_INF], 7F800000h
@@:
    xor ebx, ebx                        ; trim ASCII controls and spaces
    mov ecx, [ebp+12]
pt_lead:
    cmp ebx, ecx
    jae pt_trail
    cmp WORD PTR [esi+ebx*2], 32
    ja pt_trail
    inc ebx
    jmp pt_lead
pt_trail:
    cmp ecx, ebx
    jbe pt_done
    cmp WORD PTR [esi+ecx*2-2], 32
    ja pt_done
    dec ecx
    jmp pt_trail
pt_done:
    mov [ebp+L_END], ecx
    cmp ebx, ecx
    je p_invalid
    movzx eax, WORD PTR [esi+ebx*2]
    cmp eax, '+'
    je p_signed
    cmp eax, '-'
    jne p_unsigned
    lea eax, [ebp+L_SIGN+4]
    cmp DWORD PTR [ebp+16], 0
    je @F
    lea eax, [ebp+L_SIGN]
@@:
    mov DWORD PTR [eax], 80000000h
p_signed:
    inc ebx
p_unsigned:
    mov edi, OFFSET s_nan
    call match_word
    jnz p_not_nan
    mov eax, [ebp+L_FB]                 ; quiet NaN, no sign
    dec eax
    bts DWORD PTR [ebp+L_INF], eax
    mov eax, [ebp+L_INF]
    mov edx, [ebp+L_INF+4]
    jmp p_store
p_not_nan:
    mov edi, OFFSET s_inf
    call match_word
    jz p_inf
    cmp ebx, [ebp+L_END]
    je p_invalid
    mov ecx, [ebp+L_END]                ; one f/F/d/D suffix
    movzx eax, WORD PTR [esi+ecx*2-2]
    or eax, 20h
    cmp eax, 'f'
    je @F
    cmp eax, 'd'
    jne p_nosuffix
@@:
    dec DWORD PTR [ebp+L_END]
p_nosuffix:
    mov DWORD PTR [ebp+L_BASE], 10
    mov DWORD PTR [ebp+L_LIMIT], 768
    lea eax, [ebx+2]
    cmp eax, [ebp+L_END]
    ja p_dec
    cmp WORD PTR [esi+ebx*2], '0'
    jne p_dec
    movzx eax, WORD PTR [esi+ebx*2+2]
    or eax, 20h
    cmp eax, 'x'
    jne p_dec
    mov DWORD PTR [ebp+L_BASE], 16
    mov DWORD PTR [ebp+L_LIMIT], 300
    add ebx, 2
p_dec:
    xor eax, eax
    xor edx, edx
    lea edi, [ebp+F_R]
    call big_set
    inc eax
    lea edi, [ebp+F_S]
    call big_set
    xor eax, eax
    mov [ebp+L_KEPT], eax
    mov [ebp+L_ANY], eax
    mov [ebp+L_DOT], eax
    mov [ebp+L_STICK], eax
    mov [ebp+L_FRAC], eax
    mov [ebp+L_DROP], eax
    mov [ebp+L_EXP], eax
pd_loop:
    cmp ebx, [ebp+L_END]
    jae pd_end
    movzx eax, WORD PTR [esi+ebx*2]
    cmp eax, '.'
    jne pd_digit
    cmp DWORD PTR [ebp+L_DOT], 0
    jne pd_digit
    mov DWORD PTR [ebp+L_DOT], 1
    inc ebx
    jmp pd_loop
pd_digit:
    lea ecx, [eax-'0']
    cmp ecx, 9
    jbe pd_value
    mov ecx, [ebp+L_BASE]
    cmp ecx, 16
    jne pd_value
    or eax, 20h
    sub eax, 'a'
    cmp eax, 5
    ja pd_value
    lea ecx, [eax+10]
pd_value:
    cmp ecx, [ebp+L_BASE]
    jae pd_end
    mov DWORD PTR [ebp+L_ANY], 1
    cmp DWORD PTR [ebp+L_DOT], 0
    je @F
    inc DWORD PTR [ebp+L_FRAC]
@@:
    mov eax, [ebp+L_KEPT]
    or eax, ecx
    jz pd_next                          ; leading zeros
    mov eax, [ebp+L_KEPT]
    cmp eax, [ebp+L_LIMIT]
    jae pd_drop
    push ecx
    lea edi, [ebp+F_R]
    mov ecx, [ebp+L_BASE]
    call big_mul
    pop ecx
    call big_adds
    inc DWORD PTR [ebp+L_KEPT]
    jmp pd_next
pd_drop:
    inc DWORD PTR [ebp+L_DROP]
    test ecx, ecx
    jz pd_next
    mov DWORD PTR [ebp+L_STICK], 1
pd_next:
    inc ebx
    jmp pd_loop
pd_end:
    cmp DWORD PTR [ebp+L_ANY], 0
    je p_invalid
    cmp ebx, [ebp+L_END]
    jae pe_none
    movzx eax, WORD PTR [esi+ebx*2]
    or eax, 20h
    cmp DWORD PTR [ebp+L_BASE], 16
    je pe_hex
    cmp eax, 'e'
    jne pe_none
    jmp pe_parse
pe_hex:
    cmp eax, 'p'
    jne p_invalid
pe_parse:
    inc ebx
    xor edi, edi
    cmp ebx, [ebp+L_END]
    jae pe_digits
    movzx eax, WORD PTR [esi+ebx*2]
    cmp eax, '+'
    je pe_sign
    cmp eax, '-'
    jne pe_digits
    inc edi
pe_sign:
    inc ebx
pe_digits:
    mov edx, ebx
    xor eax, eax
pe_loop:
    cmp ebx, [ebp+L_END]
    jae pe_end
    movzx ecx, WORD PTR [esi+ebx*2]
    sub ecx, '0'
    cmp ecx, 9
    ja pe_end
    cmp eax, 100000000                  ; past 10^9 the result is 0 or infinite anyway
    jae @F
    imul eax, eax, 10
    add eax, ecx
@@:
    inc ebx
    jmp pe_loop
pe_end:
    cmp ebx, edx
    je p_invalid
    test edi, edi
    jz @F
    neg eax
@@:
    mov [ebp+L_EXP], eax
    jmp pe_done
pe_none:
    cmp DWORD PTR [ebp+L_BASE], 16
    je p_invalid
pe_done:
    cmp ebx, [ebp+L_END]
    jne p_invalid
    cmp DWORD PTR [ebp+L_KEPT], 0
    je p_zero
    cmp DWORD PTR [ebp+L_BASE], 10
    jne p_hexscale
    mov eax, [ebp+L_EXP]                ; power of ten and the order of magnitude
    sub eax, [ebp+L_FRAC]
    add eax, [ebp+L_DROP]
    mov edx, eax
    add edx, [ebp+L_KEPT]
    dec edx
    cmp edx, 309
    jg p_inf
    cmp edx, -325
    jl p_zero
    lea edi, [ebp+F_R]
    test eax, eax
    jns @F
    neg eax
    lea edi, [ebp+F_S]
@@:
    mov ecx, 10
pw_loop:
    test eax, eax
    jz p_scaled
    push eax
    call big_mul
    pop eax
    dec eax
    jmp pw_loop
p_hexscale:
    mov eax, [ebp+L_EXP]
    mov ecx, [ebp+L_FRAC]
    sub ecx, [ebp+L_DROP]
    shl ecx, 2
    sub eax, ecx
    push eax
    lea esi, [ebp+F_R]
    call bitlen
    pop ecx
    lea edx, [eax+ecx-1]
    cmp edx, 1023
    jg p_inf
    cmp edx, -1075
    jl p_zero
    lea edi, [ebp+F_R]
    test ecx, ecx
    jns @F
    neg ecx
    lea edi, [ebp+F_S]
@@:
    call big_shl
p_scaled:
    lea esi, [ebp+F_R]                  ; e = the binary exponent of r / s
    call bitlen
    push eax
    lea esi, [ebp+F_S]
    call bitlen
    pop edx
    sub edx, eax
    mov [ebp+L_E], edx
    js pe_neg
    lea edi, [ebp+F_T]
    lea esi, [ebp+F_S]
    call big_copy
    mov ecx, [ebp+L_E]
    call big_shl
    lea esi, [ebp+F_R]
    lea edi, [ebp+F_T]
    jmp pe_cmp
pe_neg:
    lea edi, [ebp+F_T]
    lea esi, [ebp+F_R]
    call big_copy
    mov ecx, [ebp+L_E]
    neg ecx
    call big_shl
    lea esi, [ebp+F_T]
    lea edi, [ebp+F_S]
pe_cmp:
    call big_cmp
    test eax, eax
    jns @F
    dec DWORD PTR [ebp+L_E]
@@:
    mov eax, [ebp+L_E]
    cmp eax, [ebp+L_MAX]
    jg p_inf
    mov edx, [ebp+L_MIN]
    sub edx, [ebp+L_FB]
    dec edx
    cmp eax, edx
    jl p_zero
    cmp eax, [ebp+L_MIN]                ; scale to fb + 1 significant bits
    jge @F
    mov eax, [ebp+L_MIN]
@@:
    mov ecx, [ebp+L_FB]
    sub ecx, eax
    lea edi, [ebp+F_R]
    jns @F
    neg ecx
    lea edi, [ebp+F_S]
@@:
    call big_shl
    lea edi, [ebp+F_T]
    lea esi, [ebp+F_S]
    call big_copy
    mov ecx, [ebp+L_FB]
    inc ecx
    call big_shl
    xor eax, eax
    mov [ebp+L_VAL], eax
    mov [ebp+L_VAL+4], eax
    mov ebx, [ebp+L_FB]
    inc ebx
pb_loop:                                ; long division: one result bit per step
    lea esi, [ebp+F_R]
    lea edi, [ebp+F_T]
    call big_cmp
    test eax, eax
    js @F
    lea edi, [ebp+F_R]
    lea esi, [ebp+F_T]
    call big_sub
    bts DWORD PTR [ebp+L_VAL], ebx
@@:
    lea edi, [ebp+F_T]
    call big_half
    dec ebx
    jns pb_loop
    lea edi, [ebp+F_R]                  ; round half to even (sticky digits count as above)
    mov ecx, 2
    call big_mul
    lea esi, [ebp+F_R]
    lea edi, [ebp+F_S]
    call big_cmp
    test eax, eax
    jg p_up
    jnz p_rounded
    cmp DWORD PTR [ebp+L_STICK], 0
    jne p_up
    test BYTE PTR [ebp+L_VAL], 1
    jz p_rounded
p_up:
    add DWORD PTR [ebp+L_VAL], 1
    adc DWORD PTR [ebp+L_VAL+4], 0
p_rounded:
    mov eax, [ebp+L_VAL]
    mov edx, [ebp+L_VAL+4]
    mov ecx, [ebp+L_E]
    cmp ecx, [ebp+L_MIN]
    jl p_signed_out                     ; subnormal: the bits as they are
    cmp DWORD PTR [ebp+16], 0
    je p_ov64
    cmp eax, 1000000h
    jne p_pack
    jmp p_carry
p_ov64:
    test eax, eax
    jnz p_pack
    cmp edx, 200000h
    jne p_pack
p_carry:                                ; rounded up to the next power of two
    shrd eax, edx, 1
    shr edx, 1
    inc ecx
p_pack:
    cmp ecx, [ebp+L_MAX]
    jg p_inf
    add ecx, [ebp+L_BIAS]
    cmp DWORD PTR [ebp+16], 0
    je p_pack64
    and eax, 7FFFFFh
    shl ecx, 23
    or eax, ecx
    xor edx, edx
    jmp p_signed_out
p_pack64:
    and edx, 0FFFFFh
    shl ecx, 20
    or edx, ecx
    jmp p_signed_out
p_inf:
    mov eax, [ebp+L_INF]
    mov edx, [ebp+L_INF+4]
    jmp p_signed_out
p_zero:
    xor eax, eax
    xor edx, edx
p_signed_out:
    or eax, [ebp+L_SIGN]
    or edx, [ebp+L_SIGN+4]
p_store:
    mov ecx, [ebp+20]
    mov [ecx], eax
    mov [ecx+4], edx
    xor eax, eax
    jmp p_leave
p_invalid:
    mov eax, 1
p_leave:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_parse_fp_x86 ENDP
;
EXTERN SYSCALL @jbv_string_view@12:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
@jbv_decimal_text@16 PROC SYSCALL   ; ecx single, edx out, [esp+4] bits -> eax chars
    push edx
    push ecx
    push DWORD PTR [esp+16]
    push DWORD PTR [esp+16]
    call jbv_decimal_text_x86
    add esp, 16
    ret 8
@jbv_decimal_text@16 ENDP
@jbv_parse_fp@16 PROC SYSCALL       ; ecx vm, edx String, [esp+4] single, [esp+8] out
    push ebx
    mov ebx, ecx
    sub esp, 8
    push esp
    call @jbv_string_view@12
    pop ecx                             ; the chars
    pop edx                             ; their count
    test eax, eax
    jnz pf_ret
    push DWORD PTR [esp+12]
    push DWORD PTR [esp+12]
    push edx
    push ecx
    call jbv_parse_fp_x86
    add esp, 16
    test eax, eax
    jz pf_ret
    push 22
    push 0
    mov edx, OFFSET pf_nfe
    mov ecx, ebx
    call @jbv_throw_named@16
pf_ret:
    pop ebx
    ret 8
@jbv_parse_fp@16 ENDP
.const
pf_nfe DB 'java/lang/NumberFormatException', 0
.code
END

; Class file parsing for x86 (classfile.c is the reference and serves x64):
; JbvStatus jbv_parse_owned(JbvVM *vm, uint8_t *image, size_t size, JbvClass **out), cdecl.
; Takes ownership of image, also on failure. Every read is bounds-checked; a short or
; malformed file is JBV_BAD_CLASS. The class keeps pointers into the image.
; Registers: ebx the class, esi the read position, edi the end of what may be read.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
PUBLIC jbv_parse_owned
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free_image@8:PROC
EXTERN SYSCALL @jbv_free_class@8:PROC
EXTERN SYSCALL @jbv_prepare_method@4:PROC

S_OOM         EQU 2
S_BAD_CLASS   EQU 3
S_VERSION     EQU 4
S_INDY        EQU 5
S_UNSUPPORTED EQU 6
V_STATUS EQU -4
V_I      EQU -8       ; element index
V_P      EQU -12      ; current constant, field or method
V_N      EQU -16      ; attributes left
V_K      EQU -20      ; nested attributes left
V_SIZE   EQU -24      ; code size
LOCALS   EQU 24

.const
n_constant DB 13, 'ConstantValue'
n_code     DB 4, 'Code'
n_lines    DB 15, 'LineNumberTable'
n_source   DB 10, 'SourceFile'
; instruction lengths, two opcodes per byte (low nibble first); 0: computed (switches, wide)
lengths LABEL BYTE
    DB 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 032h, 032h, 023h, 022h, 022h, 011h, 011h, 011h
    DB 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 022h, 022h, 012h, 011h, 011h
    DB 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h
    DB 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h
    DB 011h, 011h, 013h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 031h, 033h, 033h, 033h
    DB 033h, 033h, 033h, 033h, 023h, 000h, 011h, 011h, 011h, 033h, 033h, 033h, 053h, 035h, 032h, 011h
    DB 033h, 011h, 040h, 033h, 055h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h
    DB 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h, 011h

.code
; ---- reading: each fails the parse (BAD_CLASS) when the bytes are not there
need:                   ; ecx = bytes
    mov eax, edi
    sub eax, esi
    cmp eax, ecx
    jb bad
    ret
get1:
    mov ecx, 1
    call need
    movzx eax, BYTE PTR [esi]
    inc esi
    ret
get2:
    mov ecx, 2
    call need
    movzx eax, WORD PTR [esi]
    xchg al, ah
    add esi, 2
    ret
get4:
    mov ecx, 4
    call need
    mov eax, [esi]
    bswap eax
    add esi, 4
    ret
take:                   ; ecx = bytes -> eax = where they are
    call need
    mov eax, esi
    add esi, ecx
    ret
cp:                     ; eax = index, cl = tag -> eax = the constant
    test eax, eax
    jz bad
    cmp ax, WORD PTR [ebx+C_POOL_SIZE]
    jae bad
    imul eax, eax, CP_SIZEOF
    add eax, [ebx+C_POOL]
    cmp BYTE PTR [eax+CP_TAG], cl
    jne bad
    ret
utf:                    ; eax = index of a Utf8 -> eax = data, edx = size
    mov cl, 1
    call cp
    movzx edx, WORD PTR [eax+CP_TEXT+TEXT_SIZE]
    mov eax, [eax+CP_TEXT+TEXT_DATA]
    ret
class_name:             ; eax = index of a Class -> its name
    mov cl, 7
    call cp
    movzx eax, WORD PTR [eax+CP_A]
    jmp utf
get_utf:
    call get2
    jmp utf
attribute:              ; -> eax/edx its name, ecx its size; esi at its body
    call get2
    push eax
    call get4
    mov ecx, eax
    call need
    pop eax
    push ecx
    call utf
    pop ecx
    ret
named:                  ; ZF = the text eax/edx equals the counted string at ecx
    push esi
    push edi
    push ecx
    movzx edi, BYTE PTR [ecx]
    cmp edx, edi
    jne nm_done
    mov esi, eax
    lea edi, [ecx+1]
    mov ecx, edx
    repe cmpsb
nm_done:
    pop ecx
    pop edi
    pop esi
    ret
; Inside an attribute body of ecx bytes: limits reading to it; ATTR_END continues after it.
ATTR_BEGIN MACRO
    push edi
    lea edi, [esi+ecx]
    push edi
ENDM
ATTR_END MACRO
    pop esi
    pop edi
ENDM

; ---- code preparation (as prepare_code): accessors and the superinstruction markers
oplen:                  ; esi = code, ecx = pc -> eax = instruction length
    movzx eax, BYTE PTR [esi+ecx]
    mov edx, eax
    shr edx, 1
    movzx edx, BYTE PTR lengths[edx]
    test al, 1
    jz @F
    shr edx, 4
@@:
    and edx, 15
    jz ol_special
    mov eax, edx
    ret
ol_special:
    cmp al, 196
    jne ol_switch
    cmp BYTE PTR [esi+ecx+1], 132       ; wide iinc
    mov eax, 6
    je @F
    mov eax, 4
@@:
    ret
ol_switch:
    lea edx, [ecx+4]
    and edx, -4                         ; the aligned operands
    push ebx
    cmp al, 170
    jne ol_lookup
    mov eax, [esi+edx+8]
    bswap eax
    mov ebx, [esi+edx+4]
    bswap ebx
    sub eax, ebx
    lea eax, [edx+eax*4+16]             ; 12 + 4 * (high - low + 1)
    jmp ol_done
ol_lookup:
    mov eax, [esi+edx+4]
    bswap eax
    lea eax, [edx+eax*8+8]
ol_done:
    sub eax, ecx
    pop ebx
    ret
prepare:                ; eax = code, ecx = size, edx = method
    push esi
    push edi
    push ebx
    mov esi, eax
    mov ebx, ecx
    test WORD PTR [edx+M_FLAGS], 28h    ; static or synchronized: no accessor
    jnz pr_scan
    cmp BYTE PTR [esi], 2Ah
    jne pr_scan
    cmp ebx, 5
    jne pr_setter
    cmp BYTE PTR [esi+1], 0B4h
    jne pr_scan
    mov al, [esi+4]
    cmp al, 0ACh
    je @F
    cmp al, 0B0h
    jne pr_scan
@@:
    mov BYTE PTR [edx+M_ACCESSOR], 1
    jmp pr_scan
pr_setter:
    cmp ebx, 6
    jne pr_scan
    cmp WORD PTR [esi+1], 0B51Bh
    jne pr_scan
    cmp BYTE PTR [esi+5], 0B1h
    jne pr_scan
    mov BYTE PTR [edx+M_ACCESSOR], 2
pr_scan:
    xor ecx, ecx
pr_loop:
    cmp ecx, ebx
    jae pr_done
    call oplen
    mov dl, [esi+ecx]
    cmp dl, 2Ah                         ; aload_0 getfield
    jne pr_iinc
    lea edx, [ecx+1]
    cmp edx, ebx
    jae pr_next
    cmp BYTE PTR [esi+ecx+1], 0B4h
    jne pr_next
    mov BYTE PTR [esi+ecx], 203
    jmp pr_next
pr_iinc:
    cmp dl, 84h                         ; iinc goto
    jne pr_next
    lea edx, [ecx+3]
    cmp edx, ebx
    jae pr_next
    cmp BYTE PTR [esi+ecx+3], 0A7h
    jne pr_next
    mov BYTE PTR [esi+ecx], 204
pr_next:
    add ecx, eax
    jmp pr_loop
pr_done:
    pop ebx
    pop edi
    pop esi
    ret

ALLOC MACRO bytes           ;; eax = jbv_alloc(vm, bytes) or the out-of-memory failure
    mov edx, bytes
    mov ecx, [ebp+8]
    call @jbv_alloc@8
    test eax, eax
    jz oom
ENDM

jbv_parse_owned PROC
    push ebp
    mov ebp, esp
    sub esp, LOCALS
    push ebx
    push esi
    push edi
    xor ebx, ebx
    mov DWORD PTR [ebp+V_STATUS], S_BAD_CLASS
    mov esi, [ebp+12]
    mov edi, esi
    mov eax, [ebp+16]
    add edi, eax
    cmp eax, 10
    jb fail
    cmp eax, 4000000h
    ja fail
    call get4
    cmp eax, 0CAFEBABEh
    jne fail
    call get4                           ; minor 0, major 69
    cmp eax, 69
    mov DWORD PTR [ebp+V_STATUS], S_VERSION
    jne fail
    mov DWORD PTR [ebp+V_STATUS], S_BAD_CLASS
    ALLOC C_SIZEOF
    mov ebx, eax
    mov eax, [ebp+12]
    mov [ebx+C_IMAGE], eax
    call get2                           ; the constant pool
    test eax, eax
    jz bad
    mov [ebx+C_POOL_SIZE], ax
    imul eax, eax, CP_SIZEOF
    ALLOC eax
    mov [ebx+C_POOL], eax
    mov DWORD PTR [ebp+V_I], 1
pool_loop:
    mov eax, [ebp+V_I]
    cmp ax, WORD PTR [ebx+C_POOL_SIZE]
    jae pool_done
    imul eax, eax, CP_SIZEOF
    add eax, [ebx+C_POOL]
    mov [ebp+V_P], eax
    call get1
    mov edx, [ebp+V_P]
    mov [edx+CP_TAG], al
    cmp al, 1
    je k_utf
    cmp al, 3
    je k_bits
    cmp al, 4
    je k_bits
    cmp al, 5
    je k_wide
    cmp al, 6
    je k_wide
    cmp al, 7
    je k_a
    cmp al, 8
    je k_a
    cmp al, 16
    je k_a
    cmp al, 19
    je k_a
    cmp al, 20
    je k_a
    cmp al, 15
    je k_handle
    cmp al, 17
    je k_condy
    cmp al, 18
    je k_indy
    cmp al, 9
    jb bad
    cmp al, 12
    ja bad
    call get2                           ; Fieldref, Methodref, InterfaceMethodref, NameAndType
    mov edx, [ebp+V_P]
    mov [edx+CP_A], ax
k_b:
    call get2
    mov edx, [ebp+V_P]
    mov [edx+CP_B], ax
    jmp pool_next
k_handle:
    call get1
    mov edx, [ebp+V_P]
    mov [edx+CP_A], ax
    jmp k_b
k_a:
    call get2
    mov edx, [ebp+V_P]
    mov [edx+CP_A], ax
    jmp pool_next
k_bits:
    call get4
    mov edx, [ebp+V_P]
    mov [edx+CP_BITS], eax
    jmp pool_next
k_wide:
    call get4
    mov edx, [ebp+V_P]
    mov [edx+CP_BITS_HI], eax
    call get4
    mov edx, [ebp+V_P]
    mov [edx+CP_BITS], eax
    inc DWORD PTR [ebp+V_I]             ; two entries
    mov eax, [ebp+V_I]
    cmp ax, WORD PTR [ebx+C_POOL_SIZE]
    jae bad
    jmp pool_next
k_utf:
    call get2
    mov edx, [ebp+V_P]
    mov [edx+CP_TEXT+TEXT_SIZE], ax
    mov ecx, eax
    call take
    mov edx, [ebp+V_P]
    mov [edx+CP_TEXT+TEXT_DATA], eax
pool_next:
    inc DWORD PTR [ebp+V_I]
    jmp pool_loop
k_condy:                                ; prepare --lower-condy
    mov DWORD PTR [ebp+V_STATUS], S_UNSUPPORTED
    jmp fail
k_indy:
    mov DWORD PTR [ebp+V_STATUS], S_INDY
    jmp fail
pool_done:
    call get2
    mov [ebx+C_FLAGS], ax
    test ah, 80h                        ; module-info
    jz @F
    mov DWORD PTR [ebp+V_STATUS], S_UNSUPPORTED
    jmp fail
@@:
    call get2
    call class_name
    test edx, edx
    jz bad
    mov [ebx+C_NAME+TEXT_DATA], eax
    mov [ebx+C_NAME+TEXT_SIZE], dx
    call get2
    test eax, eax
    jz @F
    call class_name
    mov [ebx+C_SUPER_NAME+TEXT_DATA], eax
    mov [ebx+C_SUPER_NAME+TEXT_SIZE], dx
@@:
    call get2
    mov [ebx+C_INTERFACE_COUNT], ax
    lea ecx, [eax*2]
    call take
    mov [ebx+C_INTERFACE_INDICES], eax
    call get2                           ; fields
    mov [ebx+C_FIELD_COUNT], ax
    imul eax, eax, FIELD_SIZEOF
    ALLOC eax
    mov [ebx+C_FIELDS], eax
    mov DWORD PTR [ebp+V_I], 0
field_loop:
    mov eax, [ebp+V_I]
    cmp ax, WORD PTR [ebx+C_FIELD_COUNT]
    jae fields_done
    imul eax, eax, FIELD_SIZEOF
    add eax, [ebx+C_FIELDS]
    mov [ebp+V_P], eax
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+FIELD_FLAGS], ax
    call get_utf
    mov ecx, [ebp+V_P]
    mov [ecx+FIELD_NAME+TEXT_DATA], eax
    mov [ecx+FIELD_NAME+TEXT_SIZE], dx
    call get_utf
    mov ecx, [ebp+V_P]
    mov [ecx+FIELD_DESCRIPTOR+TEXT_DATA], eax
    mov [ecx+FIELD_DESCRIPTOR+TEXT_SIZE], dx
    IF JBV_PROFILE_FULL
    mov [ecx+FIELD_ATTRIBUTES], esi
    ENDIF
    call get2
    mov [ebp+V_N], eax
field_attr:
    dec DWORD PTR [ebp+V_N]
    js field_next
    call attribute
    ATTR_BEGIN
    mov ecx, OFFSET n_constant
    call named
    jne fa_done
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+FIELD_CONSTANT], ax
    test eax, eax
    jz bad
    cmp ax, WORD PTR [ebx+C_POOL_SIZE]
    jae bad
    test BYTE PTR [ecx+FIELD_FLAGS], 8  ; a static field starts with its constant
    jz fa_done
    imul eax, eax, CP_SIZEOF
    add eax, [ebx+C_POOL]
    cmp BYTE PTR [eax+CP_TAG], 8        ; String constants are set at initialization
    je fa_done
    mov edx, [eax+CP_BITS]
    mov [ecx+FIELD_VALUE], edx
    mov edx, [eax+CP_BITS_HI]
    mov [ecx+FIELD_VALUE_HI], edx
fa_done:
    ATTR_END
    jmp field_attr
field_next:
    inc DWORD PTR [ebp+V_I]
    jmp field_loop
fields_done:
    call get2                           ; methods
    mov [ebx+C_METHOD_COUNT], ax
    imul eax, eax, M_SIZEOF
    ALLOC eax
    mov [ebx+C_METHODS], eax
    mov DWORD PTR [ebp+V_I], 0
method_loop:
    mov eax, [ebp+V_I]
    cmp ax, WORD PTR [ebx+C_METHOD_COUNT]
    jae methods_done
    imul eax, eax, M_SIZEOF
    add eax, [ebx+C_METHODS]
    mov [ebp+V_P], eax
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+M_FLAGS], ax
    call get_utf
    mov ecx, [ebp+V_P]
    mov [ecx+M_NAME+TEXT_DATA], eax
    mov [ecx+M_NAME+TEXT_SIZE], dx
    call get_utf
    mov ecx, [ebp+V_P]
    mov [ecx+M_DESCRIPTOR+TEXT_DATA], eax
    mov [ecx+M_DESCRIPTOR+TEXT_SIZE], dx
    IF JBV_PROFILE_FULL
    mov [ecx+M_ATTRIBUTES], esi
    ENDIF
    call get2
    mov [ebp+V_N], eax
method_attr:
    dec DWORD PTR [ebp+V_N]
    js method_next
    call attribute
    ATTR_BEGIN
    mov ecx, OFFSET n_code
    call named
    jne ma_done
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+M_MAX_STACK], ax
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+M_MAX_LOCALS], ax
    call get4
    mov [ebp+V_SIZE], eax
    mov ecx, eax
    call take
    mov edx, [ebp+V_P]
    mov [edx+M_CODE], eax
    mov ecx, [ebp+V_SIZE]
    call prepare
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+M_HANDLERS], ax
    lea ecx, [eax*8]
    call take
    mov ecx, [ebp+V_P]
    mov [ecx+M_EXCEPTIONS], eax
    call get2
    mov [ebp+V_K], eax
code_attr:
    dec DWORD PTR [ebp+V_K]
    js ma_done
    call attribute
    ATTR_BEGIN
    mov ecx, OFFSET n_lines
    call named
    jne ca_done
    call get2
    mov ecx, [ebp+V_P]
    mov [ecx+M_LINE_COUNT], ax
    lea ecx, [eax*4]
    call take
    mov ecx, [ebp+V_P]
    mov [ecx+M_LINES], eax
ca_done:
    ATTR_END
    jmp code_attr
ma_done:
    ATTR_END
    jmp method_attr
method_next:
    inc DWORD PTR [ebp+V_I]
    jmp method_loop
methods_done:
    IF JBV_PROFILE_FULL
    mov [ebx+C_ATTRIBUTES], esi
    ENDIF
    call get2
    mov [ebp+V_N], eax
class_attr:
    dec DWORD PTR [ebp+V_N]
    js class_done
    call attribute
    ATTR_BEGIN
    mov ecx, OFFSET n_source
    call named
    jne cl_done
    call get_utf
    mov [ebx+C_SOURCE_FILE+TEXT_DATA], eax
    mov [ebx+C_SOURCE_FILE+TEXT_SIZE], dx
cl_done:
    ATTR_END
    jmp class_attr
class_done:
    cmp esi, edi                        ; nothing after the class
    jne bad
    xor esi, esi
prep_loop:
    cmp si, WORD PTR [ebx+C_METHOD_COUNT]
    jae parsed
    imul ecx, esi, M_SIZEOF
    add ecx, [ebx+C_METHODS]
    call @jbv_prepare_method@4
    inc esi
    jmp prep_loop
parsed:
    mov eax, [ebp+20]
    mov [eax], ebx
    xor eax, eax
    jmp leave_
oom:
    mov DWORD PTR [ebp+V_STATUS], S_OOM
    jmp fail
bad:
    mov DWORD PTR [ebp+V_STATUS], S_BAD_CLASS
fail:
    lea esp, [ebp-LOCALS-12]            ; from any depth of the helpers above
    mov ecx, [ebp+8]
    test ebx, ebx
    jz fail_image
    mov edx, ebx
    call @jbv_free_class@8
    jmp fail_status
fail_image:
    mov edx, [ebp+12]
    call @jbv_free_image@8
fail_status:
    mov eax, [ebp+V_STATUS]
leave_:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_parse_owned ENDP
END

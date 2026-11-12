; JAR (ZIP) reading: stored and LZMA
; (method 14) entries, every read bounds-checked (a damaged archive is JBV_BAD_CLASS).
;   JbvStatus jbv_jar_read(vm, jar, size, JbvText name, suffix, uint8_t **out, size_t *out_size, verify)
;   JbvStatus jbv_archive_open(vm, JbvArchive *archive, jar, size, verify)
;   JbvStatus jbv_archive_find(const JbvArchive *archive, JbvText name, const uint8_t **data, uint32_t *size)
; all cdecl. The LZMA decoding loop is lzma.asm.
.686
.model flat, C
option casemap:none
option noscoped
PUBLIC jbv_jar_read
PUBLIC jbv_archive_open
PUBLIC jbv_archive_find
EXTERN jbv_unlzma_x86:PROC
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC

S_OOM       EQU 2
S_BAD_CLASS EQU 3
S_NOT_FOUND EQU 7
; arguments of jbv_jar_read
A_VM      EQU 8
A_JAR     EQU 12
A_SIZE    EQU 16
A_NAME    EQU 20
A_NAMELEN EQU 24
A_SUFFIX  EQU 28
A_OUT     EQU 32
A_OUTSIZE EQU 36
A_VERIFY  EQU 40
; locals
V_TAIL  EQU -4          ; suffix length
V_COUNT EQU -8
V_END   EQU -12         ; the end of the central directory
V_DATA  EQU -16
V_PLAIN EQU -20
V_STAT  EQU -24
Z       EQU -96         ; JbvLzma (lzma.asm), 68 bytes
Z_P EQU Z
Z_IN EQU Z+4
Z_END EQU Z+8
Z_OUT EQU Z+12
Z_SIZE EQU Z+16
Z_LC EQU Z+20
Z_LPM EQU Z+24
Z_PBM EQU Z+28
Z_CODE EQU Z+60
LOCALS  EQU 96

.const
s_classes DB 'jbv/classes', 0
s_bin     DB '.bin', 0

.code
jbv_jar_read PROC
    push ebp
    mov ebp, esp
    sub esp, LOCALS
    push ebx
    push esi
    push edi
    mov DWORD PTR [ebp+V_STAT], S_BAD_CLASS
    mov edi, [ebp+A_SUFFIX]
    xor eax, eax
    or ecx, -1
    repne scasb
    not ecx
    dec ecx
    mov [ebp+V_TAIL], ecx
    mov ebx, [ebp+A_JAR]
    mov eax, [ebp+A_SIZE]
    cmp eax, 22
    jb jr_status
    lea esi, [ebx+eax-22]               ; the end of central directory: the last signature
jr_eocd:
    cmp DWORD PTR [esi], 06054b50h
    je @F
    cmp esi, ebx
    je jr_status
    dec esi
    jmp jr_eocd
@@:
    mov [ebp+V_END], esi
    movzx eax, WORD PTR [esi+10]
    mov [ebp+V_COUNT], eax
    mov eax, [esi+16]
    mov edx, esi
    sub edx, ebx
    cmp eax, edx
    ja jr_status
    lea esi, [ebx+eax]                  ; esi = the entry
jr_entry:
    dec DWORD PTR [ebp+V_COUNT]
    js jr_missing
    mov eax, [ebp+V_END]
    sub eax, esi
    cmp eax, 46
    jl jr_status
    cmp DWORD PTR [esi], 02014b50h
    jne jr_status
    movzx ecx, WORD PTR [esi+28]        ; name length
    sub eax, 46
    cmp eax, ecx
    jb jr_status
    movzx eax, WORD PTR [ebp+A_NAMELEN]
    add eax, [ebp+V_TAIL]
    cmp eax, ecx
    jne jr_next
    push esi                            ; name, then suffix
    lea edi, [esi+46]
    mov esi, [ebp+A_NAME]
    movzx ecx, WORD PTR [ebp+A_NAMELEN]
    repe cmpsb
    jne @F
    mov esi, [ebp+A_SUFFIX]
    mov ecx, [ebp+V_TAIL]
    repe cmpsb
@@:
    pop esi
    je jr_found
jr_next:
    movzx eax, WORD PTR [esi+28]
    movzx edx, WORD PTR [esi+30]
    add eax, edx
    movzx edx, WORD PTR [esi+32]
    lea esi, [esi+eax+46]
    add esi, edx
    jmp jr_entry
jr_missing:
    mov DWORD PTR [ebp+V_STAT], S_NOT_FOUND
    jmp jr_status
jr_found:
    cmp DWORD PTR [ebp+A_OUT], 0
    je jr_ok
    movzx eax, WORD PTR [esi+10]        ; method: stored or LZMA
    test eax, eax
    jz @F
    cmp eax, 14
    jne jr_status
@@:
    mov edx, [esi+42]                   ; the local header
    mov ecx, [ebp+A_SIZE]
    cmp edx, ecx
    ja jr_status
    sub ecx, edx
    cmp ecx, 30
    jb jr_status
    lea edi, [ebx+edx]
    cmp DWORD PTR [edi], 04034b50h
    jne jr_status
    movzx ecx, WORD PTR [edi+26]
    movzx edx, WORD PTR [edi+28]
    lea edi, [edi+ecx+30]
    add edi, edx                        ; edi = the data
    mov ecx, [ebp+A_SIZE]
    add ecx, ebx
    sub ecx, edi
    jb jr_status
    cmp ecx, [esi+20]
    jb jr_status
    mov edx, [esi+24]
    mov [ebp+V_PLAIN], edx
    test eax, eax
    jnz @F
    cmp edx, [esi+20]                   ; stored: as large as packed
    jne jr_status
@@:
    push eax
    mov ecx, [ebp+A_VM]
    call @jbv_alloc@8
    mov [ebp+V_DATA], eax
    test eax, eax
    pop eax
    jz jr_oom
    test eax, eax
    jnz jr_lzma
    push esi                            ; stored
    push edi
    mov esi, edi
    mov edi, [ebp+V_DATA]
    mov ecx, [ebp+V_PLAIN]
    rep movsb
    pop edi
    pop esi
    jmp jr_check
jr_lzma:                                ; u8 version[2], u16 props size = 5, props, the stream
    mov ecx, [esi+20]
    cmp ecx, 14
    jb jr_bad_data
    cmp WORD PTR [edi+2], 5
    jne jr_bad_data
    cmp BYTE PTR [edi+9], 0
    jne jr_bad_data
    movzx eax, BYTE PTR [edi+4]
    cmp eax, 9*5*5
    jae jr_bad_data
    push ecx
    push esi
    lea esi, [ebp+Z]                    ; zero the decoder state
    push edi
    mov edi, esi
    mov ecx, 17
    push eax
    xor eax, eax
    rep stosd
    pop eax
    pop edi
    pop esi
    xor edx, edx                        ; lc = props % 9, lp = props / 9 % 5, pb = props / 45
    mov ecx, 9
    div ecx
    mov [ebp+Z_LC], edx
    xor edx, edx
    mov ecx, 5
    div ecx                             ; eax = pb, edx = lp
    mov ecx, eax
    mov eax, 1
    shl eax, cl
    dec eax
    mov [ebp+Z_PBM], eax
    mov ecx, edx
    mov eax, 1
    shl eax, cl
    dec eax
    mov [ebp+Z_LPM], eax
    add ecx, [ebp+Z_LC]                 ; lc + lp
    pop eax                             ; packed
    cmp ecx, 8
    ja jr_bad_data
    lea edx, [edi+eax]
    mov [ebp+Z_END], edx
    mov eax, [edi+10]                   ; the first four code bytes
    bswap eax
    mov [ebp+Z_CODE], eax
    add edi, 14
    mov [ebp+Z_IN], edi
    mov eax, [ebp+V_DATA]
    mov [ebp+Z_OUT], eax
    mov eax, [ebp+V_PLAIN]
    mov [ebp+Z_SIZE], eax
    mov eax, 300h                       ; probabilities: 1847 + 0x300 << (lc + lp), all 1024
    shl eax, cl
    add eax, 1847
    push eax
    lea edx, [eax*2]
    mov ecx, [ebp+A_VM]
    call @jbv_alloc@8
    pop ecx
    test eax, eax
    jz jr_oom_data
    mov [ebp+Z_P], eax
    mov edi, eax
    mov eax, 1024
    rep stosw
    lea eax, [ebp+Z]
    push eax
    call jbv_unlzma_x86
    add esp, 4
    push eax
    mov edx, [ebp+Z_P]
    mov ecx, [ebp+A_VM]
    call @jbv_free@8
    pop eax
    cmp eax, [ebp+V_PLAIN]
    jne jr_bad_data
jr_check:
    cmp DWORD PTR [ebp+A_VERIFY], 0     ; CRC-32 of the entry
    je jr_give
    mov edi, [ebp+V_DATA]
    mov ecx, [ebp+V_PLAIN]
    or eax, -1
    jecxz jr_crc_done
jr_crc:
    xor al, [edi]
    inc edi
    mov edx, 8
@@:
    shr eax, 1
    jnc jr_bit
    xor eax, 0EDB88320h
jr_bit:
    dec edx
    jnz @B
    dec ecx
    jnz jr_crc
jr_crc_done:
    not eax
    cmp eax, [esi+16]
    jne jr_bad_data
jr_give:
    mov eax, [ebp+A_OUT]
    mov edx, [ebp+V_DATA]
    mov [eax], edx
    mov eax, [ebp+A_OUTSIZE]
    mov edx, [ebp+V_PLAIN]
    mov [eax], edx
jr_ok:
    mov DWORD PTR [ebp+V_STAT], 0
    jmp jr_status
jr_oom_data:
    mov DWORD PTR [ebp+V_STAT], S_OOM
    jmp jr_free
jr_bad_data:
    mov DWORD PTR [ebp+V_STAT], S_BAD_CLASS
jr_free:
    mov edx, [ebp+V_DATA]
    mov ecx, [ebp+A_VM]
    call @jbv_free@8
    jmp jr_status
jr_oom:
    mov DWORD PTR [ebp+V_STAT], S_OOM
jr_status:
    mov eax, [ebp+V_STAT]
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
jbv_jar_read ENDP

; jbv/classes.bin read out of the JAR; missing is a bad archive
jbv_archive_open PROC
    mov eax, [esp+20]                   ; verify
    mov ecx, [esp+8]                    ; archive: data, then size
    push eax
    lea eax, [ecx+4]
    push eax
    push ecx
    push OFFSET s_bin
    push 11                             ; JbvText "jbv/classes"
    push OFFSET s_classes
    push DWORD PTR [esp+40]             ; size
    push DWORD PTR [esp+40]             ; jar
    push DWORD PTR [esp+36]             ; vm
    call jbv_jar_read
    add esp, 36
    cmp eax, S_NOT_FOUND
    jne @F
    mov eax, S_BAD_CLASS
@@:
    ret
jbv_archive_open ENDP

; classes.bin: u32 count, count x {u32 offset, u32 size, u8 length, name}, class images
jbv_archive_find PROC
    push ebx
    push esi
    push edi
    push ebp
    mov eax, [esp+20]
    mov ebx, [eax]                      ; data
    mov ebp, [eax+4]                    ; size
    mov eax, S_NOT_FOUND
    test ebx, ebx
    jz af_done
    mov eax, S_BAD_CLASS
    cmp ebp, 4
    jb af_done
    mov edx, [ebx]                      ; count
    mov ecx, 4                          ; at
af_entry:
    mov eax, S_NOT_FOUND
    dec edx
    js af_done
    mov eax, S_BAD_CLASS
    mov esi, ebp
    sub esi, ecx
    sub esi, 9
    jb af_done
    movzx edi, BYTE PTR [ebx+ecx+8]     ; name length
    cmp esi, edi
    jb af_done
    cmp di, WORD PTR [esp+28]
    jne af_next
    push ecx
    lea edi, [ebx+ecx+9]
    mov esi, [esp+28]
    movzx ecx, WORD PTR [esp+32]
    repe cmpsb
    pop ecx
    jne af_next
    mov esi, [ebx+ecx]                  ; offset, size within the archive
    cmp esi, ebp
    ja af_done
    mov edi, ebp
    sub edi, esi
    cmp [ebx+ecx+4], edi
    ja af_done
    mov eax, [esp+32]
    test eax, eax
    jz af_ok
    add esi, ebx
    mov [eax], esi
    mov eax, [esp+36]
    mov edx, [ebx+ecx+4]
    mov [eax], edx
af_ok:
    xor eax, eax
    jmp af_done
af_next:
    movzx edi, BYTE PTR [ebx+ecx+8]
    lea ecx, [ecx+edi+9]
    jmp af_entry
af_done:
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret
jbv_archive_find ENDP
END

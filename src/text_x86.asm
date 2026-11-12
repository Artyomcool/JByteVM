; java.lang.String and StringBuilder natives for x86 (text.c is the reference and serves
; x64): strings are an object holding a char[] (field 0; none for ""), builders a char[]
; and a length (fields 0, 1). Every allocation may move objects: refs are kept and
; pointers fetched again after it. Internal functions keep text.c's fastcall names.
; Here ebx is always the VM.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
PUBLIC jbv_string_new_utf16
PUBLIC jbv_string_new_utf8
PUBLIC jbv_string_length
PUBLIC jbv_string_read_utf16
PUBLIC jbv_string_read_utf8
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_decimal_text@16:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC
EXTERN jbv_invoke:PROC

S_OK        EQU 0
S_BAD_ARG   EQU 1
S_OOM       EQU 2
S_UNSUPPORTED EQU 6
S_NOT_FOUND EQU 7
S_LIMIT     EQU 10
S_NULL      EQU 12
S_BOUNDS    EQU 13
S_NEGATIVE  EQU 14
S_CAST      EQU 16
B_STRING    EQU 3
B_BUILDER   EQU 4
DATA0       EQU 4
; operations (library.h)
S_INIT EQU 19
S_LENGTH EQU 20
S_EMPTY EQU 21
S_CHAR EQU 22
S_EQUALS EQU 23
S_HASH EQU 24
S_TEXT EQU 25
S_COMPARE EQU 26
S_SUBSTRING EQU 27
S_CHARS EQU 28
S_GET_CHARS EQU 29
S_CONCAT EQU 30
S_INTERN EQU 31
S_STARTS EQU 32
S_ENDS EQU 33
S_INDEX EQU 34
S_LAST_INDEX EQU 35
S_VALUE EQU 36
S_TRIM EQU 37
S_REPLACE EQU 38
S_CONTAINS EQU 39
S_REPEAT EQU 40
A_INIT EQU 41
A_APPEND EQU 42
A_LENGTH EQU 43
A_CAPACITY EQU 44
A_ENSURE EQU 45
A_SET_LENGTH EQU 46
A_CHAR EQU 47
A_SET_CHAR EQU 48
A_TEXT EQU 49
A_SUBSTRING EQU 50
A_REVERSE EQU 51
A_COMPARE EQU 52
A_INSERT EQU 53
A_DELETE EQU 54
A_DELETE_CHAR EQU 55
A_REPLACE EQU 56
A_CODEPOINT EQU 57
A_TRIM EQU 58

.const
s_string  DB 'java/lang/String'
s_null    DB 'null'
s_true    DB 'true'
s_false   DB 'false'
s_sioobe  DB 'java/lang/StringIndexOutOfBoundsException', 0
s_ioobe   DB 'java/lang/IndexOutOfBoundsException', 0
s_tostr   DB 'toString'
s_tostr_d DB '()Ljava/lang/String;'
s_length  DB 'length'
s_length_d DB '()I'
s_charat  DB 'charAt'
s_charat_d DB '(I)C'

.code
; ---- objects
; eax = a reference the VM made (live) -> eax = the object
deref:
    and eax, 0FFFFFFh
    mov ecx, [ebx+VM_HANDLES]
    mov eax, [ecx+eax*4]
    ret
; eax = a reference from an argument -> eax = the status, ecx = the object
object:
    push 0
    push esp
    mov edx, eax
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    ret
retain:                 ; eax = ref; status ignored as in the C; eax, ecx, edx kept
    push edx
    push ecx
    push eax
    push eax
    push ebx
    call jbv_retain
    jmp rr_done
release:
    push edx
    push ecx
    push eax
    push eax
    push ebx
    call jbv_release
rr_done:
    add esp, 8
    pop eax
    pop ecx
    pop edx
    ret
barrier:                ; edx = object, eax = the reference stored into it
    push eax
    push eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    pop eax
    ret
; eax = a String reference -> eax = the status, esi = its chars, ecx = its length
sview:
    call object
    test eax, eax
    jnz sv_ret
    mov edx, [ecx]                      ; the class
    cmp BYTE PTR [edx+C_BUILTIN], B_STRING
    jne sv_cast
    xor esi, esi
    mov eax, [ecx+DATA0]                ; its char[] (none for "")
    xor ecx, ecx
    test eax, eax
    jz sv_ret
    call object
    test eax, eax
    jnz sv_ret
    lea esi, [ecx+DATA0]
    mov ecx, [ecx-4]
sv_ret:
    ret
sv_cast:
    mov eax, S_CAST
    ret
; eax = a char[] reference -> eax = the status, esi = its chars, ecx = its length
aview:
    call object
    test eax, eax
    jnz av_ret
    mov edx, [ecx]
    cmp BYTE PTR [edx+C_ARRAY_KIND], 'C'
    jne sv_cast
    lea esi, [ecx+DATA0]
    mov ecx, [ecx-4]
av_ret:
    ret
; a String or char[] (rooted) -> esi, ecx: its chars
any_view:
    push eax
    call sview
    pop edx
    test eax, eax
    jz @F
    mov eax, edx
    call aview
@@:
    ret
; eax = length -> eax = the status, ecx = a new char[] reference, edi = its chars
char_array:
    test eax, eax
    js ca_oom
    push eax
    push 0                              ; the class, then the reference
    push esp
    push 'C'
    xor edx, edx
    mov ecx, ebx
    call @jbv_array_class@16
    pop edx                             ; the class
    pop ecx                             ; the length
    test eax, eax
    jnz ca_ret
    push 0
    push esp
    push ecx
    mov ecx, ebx
    call @jbv_new@16
    pop ecx
    test eax, eax
    jnz ca_ret
    push ecx
    mov eax, ecx
    call deref
    lea edi, [eax+DATA0]
    pop ecx
    xor eax, eax
ca_ret:
    ret
ca_oom:
    mov eax, S_OOM
    ret
; eax = length -> eax = the status, ecx = a new String (borrowed), edi = its chars (none for "")
; No allocation is safe between this and publishing or pinning the reference.
salloc:
    push esi
    push eax
    push 0                              ; [esp] = the String class, then the String
    test eax, eax
    js sa_oom
    mov edx, esp
    push 16
    push OFFSET s_string
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz sa_ret
    mov edx, [esp]
    push esp
    push 0
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz sa_ret
    mov eax, [esp]
    call retain
    xor edi, edi
    mov eax, [esp+4]
    test eax, eax
    jz sa_done
    call char_array
    test eax, eax
    jnz sa_release
    mov esi, ecx                        ; the String may have been promoted meanwhile
    mov eax, [esp]
    call deref
    mov [eax+DATA0], esi
    mov edx, eax
    mov eax, esi
    call barrier
sa_done:
    xor eax, eax
sa_release:
    push eax
    mov eax, [esp+4]
    call release
    pop eax
sa_ret:
    pop ecx
    add esp, 4
    pop esi
    ret
sa_oom:
    mov eax, S_OOM
    jmp sa_ret
; eax = a String or char[] (rooted), ecx = start, edx = count -> eax = the status, ecx = a new String
copy_string:
    push esi
    push edi
    push eax
    push ecx
    push edx
    mov eax, edx
    call salloc
    test eax, eax
    jnz cs_ret
    push ecx                            ; the result
    mov ecx, [esp+4]
    jecxz cs_done
    mov eax, [esp+12]
    call any_view
    add esi, [esp+8]
    add esi, [esp+8]
    mov ecx, [esp+4]
    rep movsw
cs_done:
    pop ecx
    xor eax, eax
cs_ret:
    add esp, 12
    pop edi
    pop esi
    ret
; esi = chars, ecx = length -> eax = the status, ecx = a new String
string_of:
    push esi
    push ecx
    mov eax, ecx
    call salloc
    pop edx
    pop esi
    test eax, eax
    jnz @F
    push ecx
    mov ecx, edx
    rep movsw
    pop ecx
@@:
    ret
; edx = data, ecx = size of an ASCII text -> eax = the status, ecx = a new String
ascii:
    push esi
    push edi
    push edx
    push ecx
    mov eax, ecx
    call salloc
    pop edx
    pop esi
    test eax, eax
    jnz @F
    push ecx
    mov ecx, edx
    xor eax, eax
as_loop:
    lodsb
    stosw
    loop as_loop
    pop ecx
    xor eax, eax
@@:
    pop edi
    pop esi
    ret
bounds:                 ; StringIndexOutOfBoundsException
    push S_BOUNDS
    push 0
    mov edx, OFFSET s_sioobe
    mov ecx, ebx
    call @jbv_throw_named@16
    ret
range_error:            ; IndexOutOfBoundsException
    push S_BOUNDS
    push 0
    mov edx, OFFSET s_ioobe
    mov ecx, ebx
    call @jbv_throw_named@16
    ret

; ---- exported to C (fastcall)
@jbv_string_view@12 PROC SYSCALL    ; ecx vm, edx ref, [esp+4] view
    push ebx
    push esi
    mov ebx, ecx
    mov eax, edx
    call sview
    test eax, eax
    jnz @F
    mov edx, [esp+12]
    mov [edx], esi
    mov [edx+4], ecx
@@:
    pop esi
    pop ebx
    ret 4
@jbv_string_view@12 ENDP
@jbv_string_alloc@16 PROC SYSCALL   ; ecx vm, edx length, [esp+4] ref, [esp+8] data
    push ebx
    push edi
    mov ebx, ecx
    mov eax, [esp+16]
    mov DWORD PTR [eax], 0
    mov eax, edx
    call salloc
    test eax, eax
    jnz @F
    mov edx, [esp+12]
    mov [edx], ecx
    mov edx, [esp+16]
    mov [edx], edi
@@:
    pop edi
    pop ebx
    ret 8
@jbv_string_alloc@16 ENDP
; MUTF-8 of trusted class files: NUL is C0 80, supplementary characters two surrogates
@jbv_string_mutf@16 PROC SYSCALL    ; ecx vm, edx out, [esp+4] text
    push ebx
    push esi
    push edi
    push edx
    mov ebx, ecx
    mov esi, [esp+20]
    movzx edx, WORD PTR [esp+24]
    xor ecx, ecx                        ; the UTF-16 length
    xor eax, eax
mu_count:
    cmp eax, edx
    jae mu_alloc
    inc ecx
    mov dl, [esi+eax]
    inc eax
    cmp dl, 128
    jb mu_next
    inc eax
    cmp dl, 224
    jb mu_next
    inc eax
mu_next:
    movzx edx, WORD PTR [esp+24]
    jmp mu_count
mu_alloc:
    mov eax, ecx
    call salloc
    test eax, eax
    jnz mu_ret
    pop edx
    mov [edx], ecx
    push edx
    movzx ecx, WORD PTR [esp+24]
    lea edx, [esi+ecx]                  ; the end
mu_decode:
    cmp esi, edx
    jae mu_done
    movzx eax, BYTE PTR [esi]
    inc esi
    cmp al, 128
    jb mu_put
    cmp al, 224
    jb mu_two
    and eax, 15
    shl eax, 12
    movzx ecx, BYTE PTR [esi]
    and ecx, 63
    shl ecx, 6
    or eax, ecx
    movzx ecx, BYTE PTR [esi+1]
    and ecx, 63
    or eax, ecx
    add esi, 2
    jmp mu_put
mu_two:
    and eax, 31
    shl eax, 6
    movzx ecx, BYTE PTR [esi]
    and ecx, 63
    or eax, ecx
    inc esi
mu_put:
    stosw
    jmp mu_decode
mu_done:
    xor eax, eax
mu_ret:
    pop edx
    pop edi
    pop esi
    pop ebx
    ret 8
@jbv_string_mutf@16 ENDP
; an equal interned String, or this one interned
@jbv_string_intern@12 PROC SYSCALL  ; ecx vm, edx ref, [esp+4] out
    push ebx
    push esi
    push edi
    push ebp
    mov ebx, ecx
    push edx                            ; [esp] = the ref
    mov eax, edx
    call sview
    test eax, eax
    jnz in_ret
    mov edi, esi                        ; edi, ebp: its chars and length
    mov ebp, ecx
    xor edx, edx                        ; the handle index
in_next:
    inc edx
    cmp edx, [ebx+VM_HANDLE_CAPACITY]
    ja in_new
    mov eax, [ebx+VM_INTERNED]
    bt [eax], edx
    jnc in_next
    mov eax, [ebx+VM_GENERATIONS]
    movzx eax, BYTE PTR [eax+edx]
    shl eax, 24
    or eax, edx
    push eax
    push edx
    call sview
    pop edx
    pop eax
    cmp ecx, ebp
    jne in_next
    push edi
    repe cmpsw
    pop edi
    jne in_next
    jmp in_found
in_new:
    mov eax, [esp]
    mov edx, eax
    and edx, 0FFFFFFh
    mov ecx, [ebx+VM_INTERNED]
    bts [ecx], edx
in_found:
    mov ecx, [esp+24]
    mov [ecx], eax
    xor eax, eax
in_ret:
    pop edx
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret 4
@jbv_string_intern@12 ENDP
; String.valueOf of an object: "null" or its toString()
; eax = the object reference (rooted) -> eax = the status, ecx = the String
object_text:
    test eax, eax
    jnz @F
    mov edx, OFFSET s_null
    mov ecx, 4
    jmp ascii
@@:
    push esi
    push eax                            ; [esp] = the ref (the argument slot)
    sub esp, 16                         ; method id, then the result
    call object
    test eax, eax
    jnz ot_ret
    mov eax, [ecx]
    mov [esp], eax                      ; the owner, which lookup moves to the declaring class
    push 20
    push OFFSET s_tostr_d
    push 8
    push OFFSET s_tostr
    lea ecx, [esp+16]
    call @jbv_lookup_method@20
    mov [esp+4], eax
    test eax, eax
    mov eax, S_NOT_FOUND
    jz ot_ret
    lea eax, [esp+8]
    push eax
    push 1
    lea eax, [esp+24]
    push eax
    lea eax, [esp+12]
    push eax
    push ebx
    call jbv_invoke
    add esp, 20
    test eax, eax
    jnz ot_ret
    mov eax, [esp+8]
    call release
    mov ecx, eax
    xor eax, eax
ot_ret:
    add esp, 20
    pop esi
    ret
@jbv_object_text@12 PROC SYSCALL    ; ecx vm, edx ref, [esp+4] out
    push ebx
    mov ebx, ecx
    mov eax, edx
    call object_text
    test eax, eax
    jnz @F
    mov edx, [esp+8]
    mov [edx], ecx
@@:
    pop ebx
    ret 4
@jbv_object_text@12 ENDP
; digits of a magnitude in a radix, '-' first when negative -> the count
@jbv_integer_text@20 PROC SYSCALL   ; ecx negative, edx radix, [esp+4] magnitude, [esp+12] out
    push ebx
    push esi
    push edi
    push ebp
    mov edi, [esp+28]
    mov ebx, edx
    test ecx, ecx
    jz @F
    mov WORD PTR [edi], '-'
    add edi, 2
@@:
    mov esi, edi                        ; the first digit
    mov eax, [esp+20]
    mov edx, [esp+24]
it_digit:
    mov ebp, eax
    mov eax, edx
    xor edx, edx
    div ebx
    xchg eax, ebp
    div ebx                             ; ebp:eax = the quotient, edx = the digit
    add dl, '0'
    cmp dl, '9'
    jbe @F
    add dl, 'a' - '0' - 10
@@:
    movzx edx, dl
    mov [edi], dx
    add edi, 2
    mov edx, ebp
    mov ecx, eax
    or ecx, edx
    jnz it_digit
    mov eax, edi
    sub eax, [esp+28]
    shr eax, 1
    sub edi, 2                          ; reverse the digits
@@:
    cmp esi, edi
    jae @F
    mov cx, [esi]
    mov dx, [edi]
    mov [esi], dx
    mov [edi], cx
    add esi, 2
    sub edi, 2
    jmp @B
@@:
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret 12
@jbv_integer_text@20 ENDP
; String.valueOf: dl = the kind, esi = the value slots -> eax = the status, ecx = the String
value_string:
    cmp dl, 'L'
    je vs_object
    cmp dl, 'O'
    jne @F
vs_object:
    mov eax, [esi]
    jmp object_text
@@:
    cmp dl, 'Z'
    jne @F
    mov edx, OFFSET s_true
    mov ecx, 4
    cmp DWORD PTR [esi], 0
    jne ascii
    mov edx, OFFSET s_false
    inc ecx
    jmp ascii
@@:
    push esi
    sub esp, 64                         ; at most 32 UTF-16 units
    mov edi, esp
    cmp dl, 'C'
    jne @F
    mov eax, [esi]
    mov [edi], ax
    mov ecx, 1
    jmp vs_text
@@:
    cmp dl, 'F'
    je vs_float
    cmp dl, 'D'
    jne vs_integer
vs_float:                               ; jbv_decimal_text(bits, single, out): ecx single, edx out
    xor ecx, ecx
    xor eax, eax
    cmp dl, 'F'
    sete cl
    je @F
    mov eax, [esi+4]
@@:
    push eax
    push DWORD PTR [esi]
    mov edx, edi
    call @jbv_decimal_text@16
    mov ecx, eax
    jmp vs_text
vs_integer:
    mov eax, [esi]
    cmp dl, 'J'
    je @F
    cdq
    jmp vs_signed
@@:
    mov edx, [esi+4]
vs_signed:
    xor ecx, ecx
    test edx, edx
    jns @F
    inc ecx
    neg eax
    adc edx, 0
    neg edx
@@:
    push edi
    push edx
    push eax
    mov edx, 10
    call @jbv_integer_text@20
    mov ecx, eax
vs_text:
    mov esi, esp
    call string_of
    add esp, 64
    pop esi
    ret

; ---- CharSequence -> String: a String itself (or its slice), else length()/charAt() calls
; [ebp+8] ref, [ebp+12] sliced, [ebp+16] start, [ebp+20] end -> eax = the status, ecx = the String
Q_ID    EQU -8        ; method id: owner, method
Q_LEN   EQU -16       ; uint64_t result
Q_ARGS  EQU -24       ; ref, index
Q_TYPE  EQU -28
Q_VALUE EQU -32
Q_PIN   EQU -36
Q_STAT  EQU -40
seq_string:
    push ebp
    mov ebp, esp
    sub esp, 40
    push esi
    push edi
    mov DWORD PTR [ebp+Q_PIN], 0
    cmp DWORD PTR [ebp+8], 0
    jne @F
    mov edx, OFFSET s_null
    mov ecx, 4
    call ascii
    test eax, eax
    jnz qs_ret
    mov [ebp+8], ecx
    mov eax, ecx
    call retain
    mov DWORD PTR [ebp+Q_PIN], 1
@@:
    mov eax, [ebp+8]
    call object
    test eax, eax
    jnz qs_ret
    mov edx, [ecx]
    mov [ebp+Q_TYPE], edx
    cmp BYTE PTR [edx+C_BUILTIN], B_STRING
    jne qs_sequence
    mov eax, [ebp+8]
    call sview
    mov edi, ecx                        ; its length
    mov ecx, [ebp+8]
    xor eax, eax
    cmp DWORD PTR [ebp+12], 0
    je qs_unpin
    mov eax, [ebp+16]
    mov edx, [ebp+20]
    test eax, eax
    js qs_range
    cmp edx, eax
    jl qs_range
    cmp edx, edi
    ja qs_range
    sub edx, eax
    mov ecx, eax
    mov eax, [ebp+8]
    call copy_string
    jmp qs_unpin
qs_range:
    call range_error
qs_unpin:
    cmp DWORD PTR [ebp+Q_PIN], 0
    je qs_ret
    push eax
    mov eax, [ebp+8]
    call release
    pop eax
    jmp qs_ret
qs_sequence:
    mov eax, OFFSET s_length
    mov ecx, 6
    mov edx, OFFSET s_length_d
    push 3
    call q_method
    jnz qs_ret
    lea eax, [ebp+Q_LEN]
    push eax
    push 1
    lea eax, [ebp+8]
    push eax
    lea eax, [ebp+Q_ID]
    push eax
    push ebx
    call jbv_invoke
    add esp, 20
    test eax, eax
    jnz qs_ret
    cmp DWORD PTR [ebp+12], 0
    jne @F
    mov DWORD PTR [ebp+16], 0
    mov eax, [ebp+Q_LEN]
    mov [ebp+20], eax
@@:
    mov eax, [ebp+16]
    mov edx, [ebp+20]
    test eax, eax
    js qs_bad_range
    cmp edx, eax
    jl qs_bad_range
    cmp edx, [ebp+Q_LEN]
    ja qs_bad_range
    mov eax, edx
    sub eax, [ebp+16]
    call salloc
    test eax, eax
    jnz qs_ret
    mov [ebp+Q_VALUE], ecx
    mov eax, ecx
    call retain
    mov eax, OFFSET s_charat
    mov ecx, 6
    mov edx, OFFSET s_charat_d
    push 4
    call q_method
    mov [ebp+Q_STAT], eax
    mov eax, [ebp+8]
    mov [ebp+Q_ARGS], eax
    xor edi, edi                        ; i
qs_char:
    cmp DWORD PTR [ebp+Q_STAT], 0
    jne qs_chars_done
    mov eax, [ebp+20]
    sub eax, [ebp+16]
    cmp edi, eax
    jae qs_chars_done
    mov eax, [ebp+16]
    add eax, edi
    mov [ebp+Q_ARGS+4], eax
    lea eax, [ebp+Q_LEN]
    push eax
    push 2
    lea eax, [ebp+Q_ARGS]
    push eax
    lea eax, [ebp+Q_ID]
    push eax
    push ebx
    call jbv_invoke
    add esp, 20
    mov [ebp+Q_STAT], eax
    test eax, eax
    jnz qs_chars_done
    mov eax, [ebp+Q_VALUE]
    call sview
    mov eax, [ebp+Q_LEN]
    mov [esi+edi*2], ax
    inc edi
    jmp qs_char
qs_chars_done:
    mov eax, [ebp+Q_VALUE]
    call release
    mov ecx, eax
    mov eax, [ebp+Q_STAT]
    jmp qs_ret
qs_bad_range:
    call range_error
qs_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret 16
; the method eax/ecx (name, length), edx/[esp+4] (descriptor, length) of Q_TYPE into Q_ID -> ZF = found
q_method:
    push DWORD PTR [esp+4]
    push edx
    push ecx
    push eax
    mov eax, [ebp+Q_TYPE]
    mov [ebp+Q_ID], eax
    lea ecx, [ebp+Q_ID]
    call @jbv_lookup_method@20
    mov [ebp+Q_ID+4], eax
    test eax, eax
    mov eax, S_NOT_FOUND
    jz @F
    xor eax, eax
@@:
    test eax, eax
    ret 4

; ---- StringBuilder storage: eax = builder, edx = the minimum capacity
; -> eax = the status, esi = its chars, ecx = its capacity (grown to twice + 2 when short)
bbuf:
    push edi
    push eax
    push edx
    call deref
    xor esi, esi
    xor ecx, ecx
    mov eax, [eax+DATA0]
    test eax, eax
    jz @F
    call aview
    test eax, eax
    jnz bb_ret
@@:
    mov edx, [esp]
    cmp edx, ecx
    jbe bb_ok
    test edx, edx
    js bb_oom
    mov eax, 7FFFFFFFh
    cmp ecx, (7FFFFFFFh - 2) / 2
    ja @F
    lea eax, [ecx*2+2]
@@:
    cmp eax, edx
    jae @F
    mov eax, edx
@@:
    mov [esp], eax                      ; the new capacity
    call char_array
    test eax, eax
    jnz bb_ret
    push ecx                            ; the new array
    push edi
    mov eax, [esp+12]
    call deref
    push eax                            ; the builder object
    mov eax, [eax+DATA0]
    test eax, eax
    jz @F
    call aview
    mov edi, [esp+4]
    mov eax, [esp]
    mov ecx, [eax+DATA0+4]              ; the length so far
    rep movsw
@@:
    pop edx
    pop esi                             ; the new chars
    pop eax                             ; the new array
    mov [edx+DATA0], eax
    call barrier
    pop ecx                             ; the capacity
    push ecx
bb_ok:
    xor eax, eax
bb_ret:
    pop edx
    pop edx
    pop edi
    ret
bb_oom:
    mov eax, S_OOM
    jmp bb_ret

; ---- StringBuilder natives: [ebp+8] op, [ebp+12] kind, [ebp+16] a, [ebp+20] count, [ebp+24] int32_t *out
K_OP    EQU 8
K_KIND  EQU 12
K_A     EQU 16
K_COUNT EQU 20
K_OUT   EQU 24
K_REF   EQU -4
K_LEN   EQU -8        ; the length at the start
K_BUF   EQU -12       ; the storage view
K_CAP   EQU -16
K_START EQU -20
K_END   EQU -24
K_RM    EQU -28       ; removed by replace
K_AT    EQU -32
K_V     EQU -36       ; the value arguments
K_TEXT  EQU -40
K_TLEN  EQU -44
K_STAT  EQU -48
builder_call:
    push ebp
    mov ebp, esp
    sub esp, 48
    push esi
    push edi
    xor eax, eax
    mov [ebp+K_REF], eax
    mov [ebp+K_START], eax
    mov [ebp+K_RM], eax
    mov edi, [ebp+K_A]
    mov eax, [edi]
    call object
    test eax, eax
    jnz kb_ret
    mov eax, [ecx+DATA0+4]
    mov [ebp+K_LEN], eax
    lea eax, [edi+4]
    cmp DWORD PTR [ebp+K_OP], A_INSERT
    jne @F
    add eax, 4
@@:
    mov [ebp+K_V], eax
    mov eax, [edi]
    xor edx, edx
    call bbuf
    test eax, eax
    jnz kb_ret
    mov [ebp+K_BUF], esi
    mov [ebp+K_CAP], ecx
    mov eax, [ebp+K_OUT]
    mov DWORD PTR [eax], 0
    mov eax, [ebp+K_OP]
    cmp eax, A_TRIM
    je kb_trim
    cmp eax, A_DELETE
    je kb_delete
    cmp eax, A_DELETE_CHAR
    je kb_delete
    cmp eax, A_REPLACE
    je kb_replace
    cmp eax, A_CODEPOINT
    je kb_codepoint
    cmp eax, A_COMPARE
    je kb_compare
    cmp eax, A_LENGTH
    je kb_length
    cmp eax, A_CAPACITY
    je kb_capacity
    cmp eax, A_CHAR
    je kb_char
    cmp eax, A_SET_CHAR
    je kb_char
    cmp eax, A_ENSURE
    je kb_ensure
    cmp eax, A_SET_LENGTH
    je kb_set_length
    cmp eax, A_TEXT
    je kb_text
    cmp eax, A_SUBSTRING
    je kb_text
    cmp eax, A_REVERSE
    je kb_reverse
    jmp kb_value
kb_trim:
    mov eax, [ebp+K_LEN]
    cmp eax, [ebp+K_CAP]
    je kb_ok
    call char_array
    test eax, eax
    jnz kb_ret
    push ecx
    push edi
    mov eax, [ebp+K_A]
    mov eax, [eax]
    xor edx, edx
    call bbuf
    pop edi
    mov ecx, [ebp+K_LEN]
    rep movsw
    mov eax, [ebp+K_A]
    mov eax, [eax]
    call deref
    mov edx, eax
    pop eax
    mov [edx+DATA0], eax
    call barrier
    jmp kb_ok
kb_delete:
    mov eax, [edi+4]                    ; start
    mov edx, eax
    cmp DWORD PTR [ebp+K_OP], A_DELETE_CHAR
    je @F
    mov edx, [edi+8]                    ; end
@@:
    mov ecx, [ebp+K_LEN]
    test eax, eax
    js kb_bounds
    cmp eax, ecx
    ja kb_bounds
    cmp edx, eax
    jl kb_bounds
    cmp DWORD PTR [ebp+K_OP], A_DELETE_CHAR
    jne @F
    cmp eax, ecx
    je kb_bounds
    inc edx
@@:
    cmp edx, ecx
    jbe @F
    mov edx, ecx
@@:
    push edx
    sub edx, eax                        ; removed
    mov esi, [ebp+K_BUF]
    lea edi, [esi+eax*2]
    pop eax
    lea esi, [esi+eax*2]
    sub ecx, eax                        ; the tail
    rep movsw
    mov eax, [ebp+K_A]
    mov eax, [eax]
    push edx
    call deref
    pop edx
    sub [eax+DATA0+4], edx
    jmp kb_self
kb_replace:
    mov eax, [edi+4]
    mov ecx, [ebp+K_LEN]
    test eax, eax
    js kb_bounds
    cmp eax, ecx
    ja kb_bounds
    cmp [edi+8], eax
    jl kb_bounds
    cmp DWORD PTR [edi+12], 0
    je kb_null
    mov edx, [edi+8]
    cmp edx, ecx
    jbe @F
    mov edx, ecx
@@:
    sub edx, eax
    mov [ebp+K_RM], edx
    mov eax, [edi+12]
    mov [ebp+K_REF], eax
    jmp kb_materialized
kb_codepoint:
    mov edx, [edi+4]
    cmp edx, 10FFFFh
    ja kb_bad
    mov eax, 1
    cmp edx, 0FFFFh
    jbe @F
    inc eax
@@:
    push edx
    call salloc
    pop edx
    test eax, eax
    jnz kb_ret
    mov [ebp+K_REF], ecx
    call put_codepoint
    jmp kb_materialized
kb_compare:
    mov eax, [edi+4]
    call object
    test eax, eax
    jnz kb_ret
    mov edx, [ecx]
    cmp BYTE PTR [edx+C_BUILTIN], B_BUILDER
    jne kb_cast
    push DWORD PTR [ecx+DATA0+4]        ; the other length
    mov eax, [edi+4]
    xor edx, edx
    call bbuf
    pop edx
    test eax, eax
    jnz kb_ret
    mov edi, [ebp+K_BUF]
    mov ecx, [ebp+K_LEN]
    push ecx
    push edx
    cmp ecx, edx
    jbe @F
    mov ecx, edx
@@:
    xor eax, eax
    jecxz kb_cmp_tail
    repe cmpsw
    je kb_cmp_tail
    movzx eax, WORD PTR [edi-2]
    movzx edx, WORD PTR [esi-2]
    sub eax, edx
    add esp, 8
    jmp kb_put
kb_cmp_tail:
    pop edx
    pop eax
    sub eax, edx
    jmp kb_put
kb_length:
    mov eax, [ebp+K_LEN]
    jmp kb_put
kb_capacity:
    mov eax, [ebp+K_CAP]
    jmp kb_put
kb_char:
    mov eax, [edi+4]
    cmp eax, [ebp+K_LEN]
    jae kb_bounds
    mov esi, [ebp+K_BUF]
    cmp DWORD PTR [ebp+K_OP], A_CHAR
    jne @F
    movzx eax, WORD PTR [esi+eax*2]
    jmp kb_put
@@:
    mov edx, [edi+8]
    mov [esi+eax*2], dx
    jmp kb_ok
kb_ensure:
    mov edx, [edi+4]
    test edx, edx
    jle kb_ok
    mov eax, [edi]
    call bbuf
    jmp kb_ret
kb_set_length:
    mov edx, [edi+4]
    test edx, edx
    js kb_bounds
    mov eax, [edi]
    call bbuf
    test eax, eax
    jnz kb_ret
    mov edx, [edi+4]
    mov ecx, edx
    sub ecx, [ebp+K_LEN]
    jbe @F
    push edi
    mov eax, [ebp+K_LEN]
    lea edi, [esi+eax*2]
    xor eax, eax
    rep stosw
    pop edi
@@:
    mov eax, [edi]
    call deref
    mov [eax+DATA0+4], edx
    jmp kb_ok
kb_text:
    mov edx, [ebp+K_LEN]                ; end
    xor eax, eax                        ; start
    cmp DWORD PTR [ebp+K_OP], A_SUBSTRING
    jne @F
    mov eax, [edi+4]
    cmp DWORD PTR [ebp+K_COUNT], 3
    jne @F
    mov edx, [edi+8]
@@:
    test eax, eax
    js kb_bounds
    cmp edx, eax
    jl kb_bounds
    cmp edx, [ebp+K_LEN]
    ja kb_bounds
    sub edx, eax
    mov ecx, eax
    push ecx
    push edx
    mov eax, [edi]
    call deref
    mov eax, [eax+DATA0]
    pop edx
    pop ecx
    call copy_string
    test eax, eax
    jnz kb_ret
    mov eax, ecx
    jmp kb_put
kb_reverse:
    mov esi, [ebp+K_BUF]
    mov ecx, [ebp+K_LEN]
    lea edx, [esi+ecx*2-2]
    mov eax, esi
@@:
    cmp eax, edx
    jae @F
    mov cx, [eax]
    xchg cx, [edx]
    mov [eax], cx
    add eax, 2
    sub edx, 2
    jmp @B
@@:
    mov ecx, [ebp+K_LEN]                ; reversed surrogate pairs back in order
    xor eax, eax
kb_pairs:
    lea edx, [eax+1]
    cmp edx, ecx
    jae kb_self
    mov dx, [esi+eax*2]
    sub dx, 0DC00h
    cmp dx, 3FFh
    ja kb_pair_next
    mov dx, [esi+eax*2+2]
    sub dx, 0D800h
    cmp dx, 3FFh
    ja kb_pair_next
    mov edx, [esi+eax*2]
    rol edx, 16
    mov [esi+eax*2], edx
    inc eax
kb_pair_next:
    inc eax
    jmp kb_pairs
kb_value:                               ; init, append, insert
    cmp DWORD PTR [ebp+K_OP], A_INIT
    jne kb_insert
    movzx eax, BYTE PTR [ebp+K_KIND]
    test eax, eax
    jz @F
    cmp eax, 'I'
    jne kb_init_value
    mov eax, [edi+4]
    test eax, eax
    jns kb_capacity_set
    mov eax, S_NEGATIVE
    jmp kb_ret
@@:
    mov eax, 16
kb_capacity_set:                        ; constructor capacity is exact, unlike growth
    call char_array
    test eax, eax
    jnz kb_ret
    push ecx
    mov eax, [ebp+K_A]
    mov eax, [eax]
    call deref
    mov edx, eax
    pop eax
    mov [edx+DATA0], eax
    mov DWORD PTR [edx+DATA0+4], 0
    call barrier
    jmp kb_ok
kb_init_value:
    cmp DWORD PTR [edi+4], 0
    je kb_null
kb_insert:
    cmp DWORD PTR [ebp+K_OP], A_INSERT
    jne kb_append_char
    mov eax, [edi+4]
    test eax, eax
    js kb_bounds
    cmp eax, [ebp+K_LEN]
    ja kb_bounds
    dec DWORD PTR [ebp+K_COUNT]
kb_append_char:                         ; the common case: no temporary String
    cmp DWORD PTR [ebp+K_OP], A_APPEND
    jne kb_convert
    cmp BYTE PTR [ebp+K_KIND], 'C'
    jne kb_convert
    mov edx, [ebp+K_LEN]
    inc edx
    mov eax, [edi]
    call bbuf
    test eax, eax
    jnz kb_ret
    mov edx, [ebp+K_LEN]
    mov eax, [ebp+K_V]
    mov eax, [eax]
    mov [esi+edx*2], ax
    mov eax, [edi]
    call deref
    inc edx
    mov [eax+DATA0+4], edx
    jmp kb_self
kb_convert:
    mov esi, [ebp+K_V]
    movzx edx, BYTE PTR [ebp+K_KIND]
    cmp dl, '['
    jne kb_sequence
    mov eax, [esi]
    push esi
    call aview
    pop esi
    test eax, eax
    jnz kb_ret
    xor eax, eax
    cmp DWORD PTR [ebp+K_COUNT], 4
    jne @F
    mov eax, [esi+4]
    mov edx, [esi+8]
    test eax, eax
    js kb_array_bounds
    test edx, edx
    js kb_array_bounds
    cmp eax, ecx
    ja kb_array_bounds
    sub ecx, eax
    cmp edx, ecx
    ja kb_array_bounds
    mov ecx, edx
@@:
    mov edx, ecx
    mov ecx, eax
    mov eax, [esi]
    call copy_string
    jmp kb_converted
kb_sequence:
    cmp dl, 'Q'
    jne kb_plain
    xor eax, eax
    xor ecx, ecx
    xor edx, edx
    cmp DWORD PTR [ebp+K_COUNT], 4
    jne @F
    inc eax
    mov ecx, [esi+4]
    mov edx, [esi+8]
@@:
    push edx
    push ecx
    push eax
    push DWORD PTR [esi]
    call seq_string
    jmp kb_converted
kb_plain:
    call value_string
kb_converted:
    test eax, eax
    jnz kb_ret
    mov [ebp+K_REF], ecx
    test ecx, ecx
    jnz kb_materialized
    mov edx, OFFSET s_null
    mov ecx, 4
    call ascii
    test eax, eax
    jnz kb_ret
    mov [ebp+K_REF], ecx
kb_materialized:
    mov eax, [ebp+K_REF]
    call retain
    call sview
    mov [ebp+K_STAT], eax
    test eax, eax
    jnz kb_done
    mov [ebp+K_TLEN], ecx
    ; toString/CharSequence calls may have reentered and changed this very builder
    ; (and the GC moved it): work from its current length
    mov edi, [ebp+K_A]
    mov eax, [edi]
    call deref
    mov ecx, [eax+DATA0+4]
    mov [ebp+K_LEN], ecx
    mov edx, ecx
    mov eax, [ebp+K_OP]
    cmp eax, A_INSERT
    je @F
    cmp eax, A_REPLACE
    jne kb_at
@@:
    mov edx, [edi+4]
kb_at:
    mov [ebp+K_AT], edx
    cmp edx, ecx
    ja kb_late_bounds
    sub ecx, [ebp+K_RM]                 ; length - removed
    mov eax, 7FFFFFFFh
    sub eax, ecx
    cmp [ebp+K_TLEN], eax
    ja kb_late_oom
    add ecx, [ebp+K_TLEN]
    cmp DWORD PTR [ebp+K_OP], A_INIT
    jne @F
    cmp DWORD PTR [ebp+K_TLEN], 7FFFFFFFh - 16
    ja kb_late_oom
    add ecx, 16
@@:
    mov edx, ecx
    mov eax, [edi]
    call bbuf
    mov [ebp+K_STAT], eax
    test eax, eax
    jnz kb_done
    mov [ebp+K_BUF], esi                ; growth may move both
    mov eax, [ebp+K_REF]
    call sview
    mov [ebp+K_TEXT], esi
    mov esi, [ebp+K_BUF]
    ; make room: the tail after at + removed moves by tlen - removed
    mov ecx, [ebp+K_LEN]
    mov edx, [ebp+K_AT]
    add edx, [ebp+K_RM]                 ; edx = where the tail starts
    sub ecx, edx                        ; ecx = its length
    jbe kb_room
    mov eax, [ebp+K_TLEN]
    sub eax, [ebp+K_RM]                 ; the shift
    push esi
    push edi
    lea edi, [esi+edx*2]
    lea esi, [edi+eax*2]
    xchg esi, edi                       ; esi = the tail, edi = its new place
    cmp edi, esi
    jbe @F
    lea esi, [esi+ecx*2-2]              ; moving up: backwards
    lea edi, [edi+ecx*2-2]
    std
@@:
    rep movsw
    cld
    pop edi
    pop esi
kb_room:
    mov eax, [ebp+K_AT]
    lea edx, [esi+eax*2]                ; edx = the destination
    mov ecx, [ebp+K_TLEN]
    push esi
    push edi
    mov esi, [ebp+K_TEXT]
    ; inserting a CharSequence that is this same builder reads it after making room
    cmp DWORD PTR [ebp+K_OP], A_INSERT
    jne @F
    cmp BYTE PTR [ebp+K_KIND], 'Q'
    jne @F
    mov eax, [ebp+K_V]
    mov eax, [eax]
    cmp eax, [edi]
    jne @F
    mov esi, [ebp+K_BUF]
    cmp DWORD PTR [ebp+K_COUNT], 4
    jne @F
    mov eax, [ebp+K_V]
    mov eax, [eax+4]
    lea esi, [esi+eax*2]
@@:
    mov edi, edx
    rep movsw
    pop edi
    pop esi
    mov eax, [edi]
    call deref
    mov ecx, [ebp+K_LEN]
    sub ecx, [ebp+K_RM]
    add ecx, [ebp+K_TLEN]
    mov [eax+DATA0+4], ecx
    cmp DWORD PTR [ebp+K_OP], A_INIT
    je kb_done
    mov eax, [ebp+K_OUT]
    mov ecx, [edi]
    mov [eax], ecx
    jmp kb_done
kb_late_bounds:
    call bounds
    mov [ebp+K_STAT], eax
    jmp kb_done
kb_late_oom:
    mov DWORD PTR [ebp+K_STAT], S_OOM
kb_done:
    mov eax, [ebp+K_REF]
    call release
    mov eax, [ebp+K_STAT]
    jmp kb_ret
kb_self:
    mov eax, [ebp+K_A]
    mov eax, [eax]
kb_put:
    mov ecx, [ebp+K_OUT]
    mov [ecx], eax
kb_ok:
    xor eax, eax
    jmp kb_ret
kb_bounds:
    call bounds
    jmp kb_ret
kb_array_bounds:
    mov eax, S_BOUNDS
    jmp kb_ret
kb_null:
    mov eax, S_NULL
    jmp kb_ret
kb_bad:
    mov eax, S_BAD_ARG
    jmp kb_ret
kb_cast:
    mov eax, S_CAST
kb_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret 20
; edx = a code point, edi = room for it (two units if supplementary)
put_codepoint:
    cmp edx, 0FFFFh
    ja @F
    mov [edi], dx
    ret
@@:
    sub edx, 10000h
    mov eax, edx
    shr eax, 10
    add eax, 0D800h
    mov [edi], ax
    and edx, 3FFh
    add edx, 0DC00h
    mov [edi+2], dx
    ret

; ---- String.replace/contains(CharSequence...): esi = a, edx = contains -> eax = the status, ecx = the result
R_P     EQU -4        ; the pattern String
R_R     EQU -8        ; the replacement String
R_HITS  EQU -12
R_OUT   EQU -16
R_PLEN  EQU -20
R_RLEN  EQU -24
R_TEXT  EQU -28
R_TLEN  EQU -32
R_PAT   EQU -36
R_REPL  EQU -40
R_CONT  EQU -44
R_STAT  EQU -48
replace_sequence:
    push ebp
    mov ebp, esp
    sub esp, 48
    push esi
    push edi
    xor eax, eax
    mov [ebp+R_P], eax
    mov [ebp+R_R], eax
    mov [ebp+R_STAT], eax
    mov [ebp+R_CONT], edx
    mov eax, S_NULL
    cmp DWORD PTR [esi+4], 0
    je rs_ret
    test edx, edx
    jnz @F
    cmp DWORD PTR [esi+8], 0
    je rs_ret
@@:
    push 0
    push 0
    push 0
    push DWORD PTR [esi+4]
    call seq_string
    test eax, eax
    jnz rs_ret
    mov [ebp+R_P], ecx
    mov eax, ecx
    call retain
    cmp DWORD PTR [ebp+R_CONT], 0
    jne rs_views
    push 0
    push 0
    push 0
    push DWORD PTR [esi+8]
    call seq_string
    mov [ebp+R_STAT], eax
    test eax, eax
    jnz rs_done
    mov [ebp+R_R], ecx
    mov eax, ecx
    call retain
rs_views:
    call rs_view                        ; count the matches
    xor edx, edx                        ; hits
    xor eax, eax                        ; i
rs_count:
    cmp eax, [ebp+R_TLEN]
    ja rs_counted
    call rs_match
    jne @F
    inc edx
    mov ecx, [ebp+R_PLEN]
    jecxz @F
    lea eax, [eax+ecx-1]
@@:
    inc eax
    jmp rs_count
rs_counted:
    mov [ebp+R_HITS], edx
    cmp DWORD PTR [ebp+R_CONT], 0
    je @F
    xor ecx, ecx
    test edx, edx
    setnz cl
    mov [ebp+R_OUT], ecx
    jmp rs_done
@@:
    mov ecx, [esi]
    mov [ebp+R_OUT], ecx
    test edx, edx
    jz rs_done
    push esi
    mov eax, [ebp+R_R]
    call sview
    pop esi
    mov [ebp+R_RLEN], ecx
    mov eax, ecx                        ; length = tlen + hits * (rlen - plen)
    sub eax, [ebp+R_PLEN]
    imul eax, [ebp+R_HITS]
    jo rs_oom
    add eax, [ebp+R_TLEN]
    jo rs_oom
    js rs_oom
    call salloc
    mov [ebp+R_STAT], eax
    test eax, eax
    jnz rs_done
    mov [ebp+R_OUT], ecx
    call rs_view                        ; the text, pattern and replacement again
    push esi
    mov eax, [ebp+R_R]
    call sview
    mov [ebp+R_REPL], esi
    pop esi
    xor eax, eax                        ; i; edi writes the result
rs_build:
    cmp eax, [ebp+R_TLEN]
    ja rs_done
    call rs_match
    jne rs_plain
    push esi
    mov esi, [ebp+R_REPL]
    mov ecx, [ebp+R_RLEN]
    rep movsw
    pop esi
    mov ecx, [ebp+R_PLEN]
    jecxz rs_plain
    add eax, ecx
    jmp rs_build
rs_plain:
    cmp eax, [ebp+R_TLEN]
    jae @F
    mov ecx, [ebp+R_TEXT]
    mov cx, [ecx+eax*2]
    mov [edi], cx
    add edi, 2
@@:
    inc eax
    jmp rs_build
rs_oom:
    mov DWORD PTR [ebp+R_STAT], S_OOM
rs_done:
    mov eax, [ebp+R_P]
    call release
    mov eax, [ebp+R_R]
    call release
    mov ecx, [ebp+R_OUT]
    mov eax, [ebp+R_STAT]
rs_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret
rs_view:                                ; the text a[0] and the pattern
    push esi
    push edi
    mov eax, [esi]
    call sview
    mov [ebp+R_TEXT], esi
    mov [ebp+R_TLEN], ecx
    mov eax, [ebp+R_P]
    call sview
    mov [ebp+R_PAT], esi
    mov [ebp+R_PLEN], ecx
    pop edi
    pop esi
    ret
rs_match:                               ; ZF = the pattern is at eax in the text
    push esi
    push edi
    push ecx
    mov ecx, [ebp+R_TLEN]
    sub ecx, eax
    cmp ecx, [ebp+R_PLEN]
    jb rm_no
    mov ecx, [ebp+R_PLEN]
    mov esi, [ebp+R_TEXT]
    lea esi, [esi+eax*2]
    mov edi, [ebp+R_PAT]
    cmp ecx, ecx                        ; ZF for an empty pattern
    repe cmpsw
    jmp rm_ret
rm_no:
    or esp, esp
rm_ret:
    pop ecx
    pop edi
    pop esi
    ret

; ---- the String and StringBuilder natives: ecx vm, edx op, stack kind, a, count, uint64_t *out
T_KIND  EQU 8
T_A     EQU 12
T_COUNT EQU 16
T_OUT   EQU 20
T_RES   EQU -4
T_PAIR  EQU -8        ; a supplementary character's two units
T_TDATA EQU -12       ; the text a[0] (valid until an allocation)
T_TLEN  EQU -16
T_OP    EQU -20
T_END   EQU -24
@jbv_text_native@24 PROC SYSCALL
    push ebp
    mov ebp, esp
    sub esp, 24
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, [ebp+T_A]
    mov DWORD PTR [ebp+T_RES], 0
    mov [ebp+T_OP], edx
    cmp edx, A_INIT
    jb tn_string
    lea eax, [ebp+T_RES]
    push eax
    movzx eax, WORD PTR [ebp+T_COUNT]
    push eax
    push esi
    movzx eax, BYTE PTR [ebp+T_KIND]
    push eax
    push edx
    call builder_call
    jmp tn_result
tn_string:
    cmp edx, S_VALUE
    jne tn_view
    mov dl, [ebp+T_KIND]
    cmp dl, '['
    je @F
    call value_string
    jmp tn_value
@@:
    mov eax, [esi]                      ; String.valueOf(char[] [, offset, count])
    call aview
    test eax, eax
    jnz tn_ret
    mov esi, [ebp+T_A]
    xor eax, eax
    mov edx, ecx
    cmp WORD PTR [ebp+T_COUNT], 3
    jne @F
    mov eax, [esi+4]
    mov edx, [esi+8]
@@:
    test eax, eax
    js tn_bounds
    test edx, edx
    js tn_bounds
    cmp eax, ecx
    ja tn_bounds
    sub ecx, eax
    cmp edx, ecx
    ja tn_bounds
    mov ecx, eax
    mov eax, [esi]
    call copy_string
tn_value:
    test eax, eax
    jnz tn_ret
    mov [ebp+T_RES], ecx
    jmp tn_ok
tn_view:
    mov eax, [esi]
    push esi
    call sview
    mov [ebp+T_TDATA], esi
    mov [ebp+T_TLEN], ecx
    pop esi
    test eax, eax
    jnz tn_ret
    mov edi, [ebp+T_OP]
    cmp edi, S_TRIM
    je tn_trim
    cmp edi, S_REPLACE
    je tn_replace
    cmp edi, S_CONTAINS
    je tn_replace
    cmp edi, S_REPEAT
    je tn_repeat
    cmp edi, S_INIT
    je tn_init
    cmp edi, S_LENGTH
    je tn_length
    cmp edi, S_EMPTY
    je tn_empty
    cmp edi, S_TEXT
    je tn_self
    cmp edi, S_CHAR
    je tn_char
    cmp edi, S_HASH
    je tn_hash
    cmp edi, S_EQUALS
    je tn_equals
    cmp edi, S_COMPARE
    je tn_equals
    cmp edi, S_SUBSTRING
    je tn_substring
    cmp edi, S_CHARS
    je tn_chars
    cmp edi, S_GET_CHARS
    je tn_get_chars
    cmp edi, S_CONCAT
    je tn_concat
    cmp edi, S_INTERN
    je tn_intern
    cmp edi, S_STARTS
    je tn_starts
    cmp edi, S_ENDS
    je tn_starts
    cmp edi, S_INDEX
    je tn_index
    cmp edi, S_LAST_INDEX
    je tn_index
    mov eax, S_UNSUPPORTED
    jmp tn_ret
tn_trim:                                ; without the chars <= ' ' at both ends
    mov edx, [ebp+T_TDATA]
    mov ecx, [ebp+T_TLEN]
    xor eax, eax
@@:
    cmp eax, ecx
    jae @F
    cmp WORD PTR [edx+eax*2], 32
    ja @F
    inc eax
    jmp @B
@@:
    cmp ecx, eax
    jbe tn_slice
    cmp WORD PTR [edx+ecx*2-2], 32
    ja tn_slice
    dec ecx
    jmp @B
tn_substring:
    mov eax, [esi+4]
    mov ecx, [ebp+T_TLEN]
    cmp WORD PTR [ebp+T_COUNT], 3
    jne @F
    mov ecx, [esi+8]
@@:
    test eax, eax
    js tn_bounds
    cmp ecx, eax
    jl tn_bounds
    cmp ecx, [ebp+T_TLEN]
    ja tn_bounds
tn_slice:                               ; eax = start, ecx = end: a[0] itself when that is all of it
    test eax, eax
    jnz @F
    cmp ecx, [ebp+T_TLEN]
    je tn_self
@@:
    mov edx, ecx
    sub edx, eax
    mov ecx, eax
    mov eax, [esi]
    call copy_string
    jmp tn_value
tn_replace:
    cmp BYTE PTR [ebp+T_KIND], 0
    jne tn_replace_char
    xor edx, edx
    cmp edi, S_CONTAINS
    sete dl
    call replace_sequence
    jmp tn_value
tn_replace_char:
    mov ecx, [ebp+T_TLEN]
    test ecx, ecx
    jz tn_self
    mov edi, [ebp+T_TDATA]
    mov eax, [esi+4]
    repne scasw
    jne tn_self                         ; not there
    mov eax, [esi+4]
    cmp eax, [esi+8]
    je tn_self
    mov eax, [ebp+T_TLEN]
    call salloc
    test eax, eax
    jnz tn_ret
    mov [ebp+T_RES], ecx
    push esi
    mov eax, [esi]
    call sview
    pop edx
    mov eax, [edx+4]
    mov edx, [edx+8]
    push ebx
@@:
    mov bx, [esi]
    cmp bx, ax
    jne tn_rc_put
    mov bx, dx
tn_rc_put:
    mov [edi], bx
    add esi, 2
    add edi, 2
    loop @B
    pop ebx
    jmp tn_ok
tn_repeat:
    mov eax, [esi+4]
    test eax, eax
    js tn_bad
    cmp eax, 1
    je tn_self
    mul DWORD PTR [ebp+T_TLEN]
    test edx, edx
    jnz tn_oom
    test eax, eax
    js tn_oom
    call salloc
    test eax, eax
    jnz tn_ret
    mov [ebp+T_RES], ecx
    push esi
    mov eax, [esi]
    call sview
    pop edx
    mov edx, [edx+4]                    ; the count
    test ecx, ecx
    jz tn_ok
    mov eax, esi
@@:
    test edx, edx
    jz tn_ok
    push ecx
    mov esi, eax
    rep movsw
    pop ecx
    dec edx
    jmp @B
tn_init:
    mov eax, [esi]
    call object
    mov edi, ecx                        ; edi = the String being made
    movzx eax, BYTE PTR [ebp+T_KIND]
    test eax, eax
    jz tn_ok
    cmp eax, 'L'
    jne tn_init_chars
    mov eax, [esi+4]                    ; a copy of a String shares its char[]
    push esi
    call sview
    pop esi
    test eax, eax
    jnz tn_ret
    mov eax, [esi+4]
    call deref
    mov eax, [eax+DATA0]
    mov [edi+DATA0], eax
    mov edx, edi
    call barrier
    jmp tn_ok
tn_init_chars:                          ; new String(char[] [, offset, count])
    mov eax, [esi+4]
    push esi
    call aview
    pop esi
    test eax, eax
    jnz tn_ret
    xor eax, eax
    mov edx, ecx
    cmp WORD PTR [ebp+T_COUNT], 4
    jne @F
    mov eax, [esi+8]
    mov edx, [esi+12]
@@:
    test eax, eax
    js tn_bounds
    test edx, edx
    js tn_bounds
    cmp eax, ecx
    ja tn_bounds
    sub ecx, eax
    cmp edx, ecx
    ja tn_bounds
    push eax                            ; start
    push edx                            ; count
    mov eax, edx
    call char_array
    test eax, eax
    jnz tn_init_fail
    push ecx                            ; the new char[]
    push edi
    mov eax, [esi+4]
    call aview
    pop edi
    add esi, [esp+8]
    add esi, [esp+8]
    mov ecx, [esp+4]
    rep movsw
    mov esi, [ebp+T_A]
    mov eax, [esi]
    call deref
    mov edx, eax
    pop eax
    add esp, 8
    mov [edx+DATA0], eax
    call barrier
    jmp tn_ok
tn_init_fail:
    add esp, 8
    jmp tn_ret
tn_length:
    mov eax, [ebp+T_TLEN]
    jmp tn_put
tn_empty:
    xor eax, eax
    cmp [ebp+T_TLEN], eax
    sete al
    jmp tn_put
tn_char:
    mov eax, [esi+4]
    cmp eax, [ebp+T_TLEN]
    jae tn_bounds
    mov edx, [ebp+T_TDATA]
    movzx eax, WORD PTR [edx+eax*2]
    jmp tn_put
tn_hash:
    xor eax, eax
    mov edx, [ebp+T_TDATA]
    mov ecx, [ebp+T_TLEN]
    test ecx, ecx
    jz tn_put
@@:
    imul eax, eax, 31
    movzx edi, WORD PTR [edx]
    add eax, edi
    add edx, 2
    loop @B
    jmp tn_put
tn_equals:
    mov eax, [esi+4]
    cmp edi, S_EQUALS
    jne @F
    test eax, eax
    jz tn_ok
@@:
    push esi
    call sview
    mov edx, esi                        ; edx, ecx: the other
    pop esi
    cmp eax, S_CAST
    jne @F
    cmp edi, S_EQUALS                   ; equals(a non-String): false
    je tn_ok
@@:
    test eax, eax
    jnz tn_ret
    push esi
    push edi
    mov esi, [ebp+T_TDATA]
    mov edi, edx
    mov eax, [ebp+T_TLEN]
    mov edx, ecx                        ; edx = the other length
    cmp ecx, eax
    jbe @F
    mov ecx, eax
@@:
    cmp eax, eax
    repe cmpsw
    je tn_eq_tail
    movzx eax, WORD PTR [esi-2]
    movzx ecx, WORD PTR [edi-2]
    sub eax, ecx
    pop edi
    pop esi
    cmp edi, S_EQUALS
    jne tn_put
    xor eax, eax
    jmp tn_put
tn_eq_tail:
    sub eax, edx                        ; the length difference
    pop edi
    pop esi
    cmp edi, S_EQUALS
    jne tn_put
    test eax, eax
    sete al
    movzx eax, al
    jmp tn_put
tn_chars:
    mov eax, [ebp+T_TLEN]
    call char_array
    test eax, eax
    jnz tn_ret
    mov [ebp+T_RES], ecx
    mov eax, [esi]
    call sview
    rep movsw
    jmp tn_ok
tn_get_chars:                           ; (srcBegin, srcEnd, dst, dstBegin)
    mov eax, [esi+4]
    test eax, eax
    js tn_bounds
    cmp [esi+8], eax
    jl tn_bounds
    mov eax, [esi+8]
    cmp eax, [ebp+T_TLEN]
    ja tn_bounds
    mov eax, [esi+12]
    push esi
    call aview
    mov edi, esi
    pop esi
    test eax, eax
    jnz tn_ret
    mov eax, [esi+16]
    test eax, eax
    js tn_array_bounds
    cmp eax, ecx
    ja tn_array_bounds
    sub ecx, eax
    lea edi, [edi+eax*2]
    mov eax, [esi+8]
    sub eax, [esi+4]
    cmp eax, ecx
    ja tn_array_bounds
    mov ecx, eax
    mov eax, [esi+4]
    mov esi, [ebp+T_TDATA]
    lea esi, [esi+eax*2]
    rep movsw
    jmp tn_ok
tn_concat:
    mov eax, [esi+4]
    push esi
    call sview
    pop esi
    test eax, eax
    jnz tn_ret
    test ecx, ecx
    jz tn_self
    mov edx, [ebp+T_TLEN]
    mov eax, 7FFFFFFFh
    sub eax, edx
    cmp ecx, eax
    ja tn_oom
    lea eax, [ecx+edx]
    call salloc
    test eax, eax
    jnz tn_ret
    mov [ebp+T_RES], ecx
    mov eax, [esi]
    push esi
    call sview
    rep movsw
    pop esi
    mov eax, [esi+4]
    call sview
    rep movsw
    jmp tn_ok
tn_intern:
    push 0
    push esp
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_string_intern@12
    pop ecx
    jmp tn_value
tn_starts:
    mov eax, [esi+4]
    push esi
    call sview
    mov edx, esi                        ; edx, ecx: the prefix or suffix
    pop esi
    test eax, eax
    jnz tn_ret
    mov eax, [ebp+T_TLEN]               ; endsWith: at length - suffix length
    sub eax, ecx
    cmp edi, S_ENDS
    je @F
    xor eax, eax                        ; startsWith(prefix [, offset])
    cmp WORD PTR [ebp+T_COUNT], 3
    jne @F
    mov eax, [esi+8]
@@:
    test eax, eax
    js tn_ok
    mov edi, [ebp+T_TLEN]
    sub edi, eax
    jb tn_ok
    cmp ecx, edi
    ja tn_ok
    call tn_at
    sete al
    movzx eax, al
    jmp tn_put
tn_index:
    cmp BYTE PTR [ebp+T_KIND], 'I'
    jne tn_index_text
    mov edx, [esi+4]                    ; a code point: one or two units
    mov eax, -1
    cmp edx, 10FFFFh
    ja tn_put
    push edi
    lea edi, [ebp+T_PAIR]
    call put_codepoint
    pop edi
    mov ecx, 1
    cmp DWORD PTR [esi+4], 0FFFFh
    jbe @F
    inc ecx
@@:
    lea edx, [ebp+T_PAIR]
    jmp tn_index_go
tn_index_text:
    mov eax, [esi+4]
    push esi
    call sview
    mov edx, esi
    pop esi
    test eax, eax
    jnz tn_ret
tn_index_go:                            ; edx, ecx: the pattern
    mov eax, [ebp+T_TLEN]
    sub eax, ecx
    mov [ebp+T_END], eax                ; the last possible start
    mov eax, [ebp+T_TLEN]
    cmp edi, S_LAST_INDEX
    je @F
    xor eax, eax
@@:
    cmp WORD PTR [ebp+T_COUNT], 3
    jne @F
    mov eax, [esi+8]
@@:
    cmp edi, S_LAST_INDEX
    je tn_last
    test eax, eax
    jns @F
    xor eax, eax
@@:
    test ecx, ecx
    jnz tn_forward
    cmp eax, [ebp+T_TLEN]
    jbe tn_forward
    mov eax, [ebp+T_TLEN]
tn_forward:
    cmp eax, [ebp+T_END]
    jg tn_missing
    call tn_at
    je tn_put
    inc eax
    jmp tn_forward
tn_last:
    cmp eax, [ebp+T_END]
    jle tn_backward
    mov eax, [ebp+T_END]
tn_backward:
    test eax, eax
    js tn_missing
    call tn_at
    je tn_put
    dec eax
    jmp tn_backward
tn_missing:
    or eax, -1
    jmp tn_put
tn_self:
    mov eax, [esi]
tn_put:
    mov [ebp+T_RES], eax
tn_ok:
    xor eax, eax
tn_result:
    test eax, eax
    jnz tn_ret
    mov ecx, [ebp+T_OUT]
    mov edx, [ebp+T_RES]
    mov [ecx], edx
    mov DWORD PTR [ecx+4], 0
tn_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 16
tn_bounds:
    call bounds
    jmp tn_ret
tn_array_bounds:
    mov eax, S_BOUNDS
    jmp tn_ret
tn_oom:
    mov eax, S_OOM
    jmp tn_ret
tn_bad:
    mov eax, S_BAD_ARG
    jmp tn_ret
; ZF = the pattern edx, ecx is in the text at eax (in bounds)
tn_at:
    push esi
    push edi
    push ecx
    mov esi, [ebp+T_TDATA]
    lea esi, [esi+eax*2]
    mov edi, edx
    cmp eax, eax
    repe cmpsw
    pop ecx
    pop edi
    pop esi
    ret
@jbv_text_native@24 ENDP

; ---- the public string API (cdecl, exported)
jbv_string_new_utf16 PROC EXPORT    ; (vm, text, length, out)
    push ebx
    push esi
    push edi
    mov ebx, [esp+16]
    mov esi, [esp+20]
    mov ecx, [esp+24]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz su_ret
    cmp DWORD PTR [esp+28], 0
    je su_ret
    jecxz @F
    test esi, esi
    jz su_ret
@@:
    mov eax, ecx
    call salloc
    test eax, eax
    jnz su_ret
    push ecx
    mov ecx, [esp+28]
    rep movsw
    pop eax
su_publish:                             ; eax = the new String: retained into *out
    push eax
    push eax
    push ebx
    call jbv_retain
    add esp, 8
    pop ecx
    test eax, eax
    jnz su_ret
    mov edx, [esp+28]
    mov [edx], ecx
su_ret:
    pop edi
    pop esi
    pop ebx
    ret
jbv_string_new_utf16 ENDP
; esi = the next byte, edx = the end -> eax = a code point, CF if malformed
utf8_next:
    movzx eax, BYTE PTR [esi]
    inc esi
    cmp al, 80h
    jb un_ok
    push ecx
    push ebx
    cmp al, 0C2h
    jb un_bad
    mov ecx, 1                          ; continuation bytes
    mov ebx, 80h                        ; the smallest value for the length
    cmp al, 0DFh
    jbe un_lead
    inc ecx
    mov ebx, 800h
    cmp al, 0EFh
    jbe un_lead
    inc ecx
    mov ebx, 10000h
    cmp al, 0F4h
    ja un_bad
un_lead:
    push edx
    sub edx, esi
    cmp ecx, edx
    ja un_bad_pop
    mov edx, 3Fh                        ; the lead's payload: 5, 4 or 3 bits
    shr edx, cl
    and eax, edx
@@:
    movzx edx, BYTE PTR [esi]
    inc esi
    xor dl, 80h
    test dl, 0C0h
    jnz un_bad_pop
    shl eax, 6
    or eax, edx
    loop @B
    pop edx
    cmp eax, ebx
    jb un_bad
    cmp eax, 10FFFFh
    ja un_bad
    mov ecx, eax
    and ecx, 0FFFFF800h
    cmp ecx, 0D800h
    je un_bad
    pop ebx
    pop ecx
un_ok:
    clc
    ret
un_bad_pop:
    pop edx
un_bad:
    pop ebx
    pop ecx
    stc
    ret
jbv_string_new_utf8 PROC EXPORT     ; (vm, text, bytes, out)
    push ebx
    push esi
    push edi
    mov ebx, [esp+16]
    mov esi, [esp+20]
    mov edx, [esp+24]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz su_ret
    cmp DWORD PTR [esp+28], 0
    je su_ret
    test edx, edx
    jz @F
    test esi, esi
    jz su_ret
@@:
    add edx, esi                        ; the end
    xor ecx, ecx                        ; UTF-16 units
@@:
    cmp esi, edx
    jae @F
    call utf8_next
    jc su_bad
    inc ecx
    cmp eax, 0FFFFh
    jbe @B
    inc ecx
    jmp @B
@@:
    mov eax, ecx
    call salloc
    test eax, eax
    jnz su_ret
    push ecx
    mov esi, [esp+24]
    mov edx, esi
    add edx, [esp+28]
@@:
    cmp esi, edx
    jae @F
    call utf8_next
    push edx
    push eax
    mov edx, eax
    call put_codepoint
    pop eax
    pop edx
    add edi, 2
    cmp eax, 0FFFFh
    jbe @B
    add edi, 2
    jmp @B
@@:
    pop eax
    jmp su_publish
su_bad:
    mov eax, S_BAD_ARG
    jmp su_ret
jbv_string_new_utf8 ENDP
jbv_string_length PROC EXPORT       ; (vm, ref, out)
    push ebx
    push esi
    mov ebx, [esp+12]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz @F
    cmp DWORD PTR [esp+20], 0
    je @F
    mov eax, [esp+16]
    call sview
    test eax, eax
    jnz @F
    mov edx, [esp+20]
    mov [edx], ecx
@@:
    pop esi
    pop ebx
    ret
jbv_string_length ENDP
jbv_string_read_utf16 PROC EXPORT   ; (vm, ref, start, count, out)
    push ebx
    push esi
    push edi
    mov ebx, [esp+16]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz sr_ret
    mov edi, [esp+32]
    cmp DWORD PTR [esp+28], 0
    je @F
    test edi, edi
    jz sr_ret
@@:
    mov eax, [esp+20]
    call sview
    test eax, eax
    jnz sr_ret
    mov eax, S_BOUNDS
    mov edx, [esp+24]
    cmp edx, ecx
    ja sr_ret
    sub ecx, edx
    cmp [esp+28], ecx
    ja sr_ret
    lea esi, [esi+edx*2]
    mov ecx, [esp+28]
    rep movsw
    xor eax, eax
sr_ret:
    pop edi
    pop esi
    pop ebx
    ret
jbv_string_read_utf16 ENDP
; UTF-8 of the units esi, ecx into edi (0: only counted); unpaired surrogates as U+FFFD -> eax = bytes
utf8_encode:
    push esi
    push ebx
    xor ebx, ebx
    test ecx, ecx
    jz ue_done
ue_next:
    movzx eax, WORD PTR [esi]
    add esi, 2
    dec ecx
    mov edx, eax
    and edx, 0FFFFF800h
    cmp edx, 0D800h
    jne ue_put
    cmp eax, 0DBFFh
    ja ue_replace
    jecxz ue_replace
    movzx edx, WORD PTR [esi]
    sub edx, 0DC00h
    cmp edx, 3FFh
    ja ue_replace
    add esi, 2
    dec ecx
    sub eax, 0D800h
    shl eax, 10
    lea eax, [eax+edx+10000h]
    jmp ue_put
ue_replace:
    mov eax, 0FFFDh
ue_put:
    cmp eax, 80h
    jae @F
    test edi, edi
    jz ue_one
    mov [edi+ebx], al
ue_one:
    inc ebx
    jmp ue_more
@@:
    push ecx
    mov ecx, 2                          ; the length and the lead's marker
    mov dl, 0C0h
    cmp eax, 800h
    jb @F
    inc ecx
    mov dl, 0E0h
    cmp eax, 10000h
    jb @F
    inc ecx
    mov dl, 0F0h
@@:
    test edi, edi
    jz ue_counted
    push ecx
    lea edx, [ecx-1]                    ; continuation bytes, last first
    push eax
@@:
    mov ah, al
    and ah, 3Fh
    or ah, 80h
    push edi
    add edi, ebx
    mov [edi+edx], ah
    pop edi
    shr DWORD PTR [esp], 6
    mov eax, [esp]
    dec edx
    jnz @B
    pop eax
    pop ecx
    mov dl, 0C0h                        ; the lead
    cmp ecx, 2
    je @F
    mov dl, 0E0h
    cmp ecx, 3
    je @F
    mov dl, 0F0h
@@:
    or al, dl
    mov [edi+ebx], al
ue_counted:
    add ebx, ecx
    pop ecx
ue_more:
    test ecx, ecx
    jnz ue_next
ue_done:
    mov eax, ebx
    pop ebx
    pop esi
    ret
jbv_string_read_utf8 PROC EXPORT    ; (vm, ref, out, capacity, bytes)
    push ebx
    push esi
    push edi
    mov ebx, [esp+16]
    mov eax, S_BAD_ARG
    test ebx, ebx
    jz s8_ret
    cmp DWORD PTR [esp+32], 0
    je s8_ret
    mov edi, [esp+24]
    test edi, edi
    jnz @F
    cmp DWORD PTR [esp+28], 0
    jne s8_ret
@@:
    mov eax, [esp+20]
    call sview
    test eax, eax
    jnz s8_ret
    push esi
    push ecx
    push edi
    xor edi, edi
    call utf8_encode                    ; the size first
    pop edi
    pop ecx
    pop esi
    test edi, edi
    jz @F
    cmp eax, [esp+28]
    mov edx, eax
    mov eax, S_BAD_ARG
    ja s8_ret
    call utf8_encode
@@:
    mov edx, [esp+32]
    mov [edx], eax
    xor eax, eax
s8_ret:
    pop edi
    pop esi
    pop ebx
    ret
jbv_string_read_utf8 ENDP
END

; The embedded class library: finding
; and loading its classes, and the jbv/runtime/Support natives (hooks).
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout.inc
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_primitive_mirror@12:PROC
EXTERN SYSCALL @jbv_parse_fp@16:PROC
EXTERN SYSCALL @jbv_dynamic_native@16:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_link@12:PROC
EXTERN SYSCALL @jbv_text_bytes@12:PROC
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN jbv_jar_read:PROC
EXTERN jbv_collect:PROC
EXTERN jbv_archive_open:PROC
EXTERN jbv_archive_find:PROC
EXTERN jbv_parse_owned:PROC
EXTERN jbv_reflect_native:PROC
EXTERN jbv_library_jar:BYTE
EXTERN jbv_library_jar_size:DWORD

S_UNSUPPORTED EQU 6
S_NOT_FOUND EQU 7
OP_RESOURCE EQU 24
S_LINKAGE   EQU 8
S_NULL      EQU 12
S_BOUNDS    EQU 13
S_STORE     EQU 15
S_CAST      EQU 16
S_NATIVE    EQU 21
DATA0       EQU 4
NATIVE      EQU 100h

.const
; counted names, 0 ends; the index is the native's user value
hooks DB 9, 'primitive', 9, 'arraycopy', 12, 'newArrayLike', 12, 'identityHash', 5, 'clock', 5, 'write'
    DB 7, 'collect', 9, 'floatBits', 9, 'bitsFloat', 10, 'doubleBits', 10, 'bitsDouble', 7, 'parseFP'
    DB 4, 'sqrt', 13, 'roundIntegral', 5, 'ascii'
    DB 11, 'callerClass', 15, 'methodTypeClass', 10, 'findHandle', 12, 'invokeHandle', 11, 'staticFinal'
    DB 12, 'wrapperClass', 12, 'explicitCast', 9, 'enumValue', 17, 'captureStackTrace', 8, 'resource', 0
reflection DB 4, 'info', 5, 'flags', 6, 'invoke', 5, 'field', 6, 'access', 5, 'array', 7, 'convert'
    DB 11, 'annotations', 14, 'classSignature', 0
n_support    DB 'jbv/runtime/Support'
n_reflection DB 'jbv/runtime/Reflection'
round_cw DW 0400h, 0800h, 0         ; x87 rounding: floor, ceil, to nearest even

.code
; eax = an element kind -> eax = its bytes (1, 2, 4 or 8)
element_bytes:
    cmp al, 'Z'
    je eb_1
    cmp al, 'B'
    je eb_1
    cmp al, 'C'
    je eb_2
    cmp al, 'S'
    je eb_2
    cmp al, 'J'
    je eb_8
    cmp al, 'D'
    je eb_8
    mov eax, 4
    ret
eb_1:
    mov eax, 1
    ret
eb_2:
    mov eax, 2
    ret
eb_8:
    mov eax, 8
    ret

; System.arraycopy(src, srcPos, dst, dstPos, length): esi = the arguments, ebx = vm
A_FROM EQU -4
A_TO   EQU -8
arraycopy:
    push ebp
    mov ebp, esp
    sub esp, 8
    push edi
    mov eax, S_NULL
    cmp DWORD PTR [esi], 0
    je ac_ret
    cmp DWORD PTR [esi+8], 0
    je ac_ret
    lea eax, [ebp+A_FROM]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ac_ret
    lea eax, [ebp+A_TO]
    push eax
    mov edx, [esi+8]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ac_ret
    mov eax, [ebp+A_FROM]
    mov eax, [eax]
    mov ecx, [ebp+A_TO]
    mov ecx, [ecx]
    mov al, [eax+C_ARRAY_KIND]
    test al, al
    jz ac_store
    cmp al, [ecx+C_ARRAY_KIND]
    jne ac_store
    mov eax, [ebp+A_FROM]               ; bounds (unsigned: negatives are huge)
    mov ecx, [eax-4]
    mov edx, [esi+4]
    cmp ecx, edx
    jb ac_bounds
    sub ecx, edx
    mov edx, [esi+16]
    cmp ecx, edx
    jb ac_bounds
    mov eax, [ebp+A_TO]
    mov ecx, [eax-4]
    mov edx, [esi+12]
    cmp ecx, edx
    jb ac_bounds
    sub ecx, edx
    mov edx, [esi+16]
    cmp ecx, edx
    jb ac_bounds
    mov eax, [esi+4]
    or eax, [esi+12]
    or eax, [esi+16]
    js ac_bounds
    mov eax, [ebp+A_FROM]
    mov eax, [eax]
    movzx eax, BYTE PTR [eax+C_ARRAY_KIND]
    push eax
    call element_bytes
    mov ecx, eax
    imul ecx, [esi+16]                  ; ecx = bytes
    mov edx, eax
    imul edx, [esi+4]
    add edx, [ebp+A_FROM]
    lea edx, [edx+DATA0]                ; edx = the source
    imul eax, [esi+12]
    add eax, [ebp+A_TO]
    lea edi, [eax+DATA0]                ; edi = the target
    pop eax
    cmp al, 'L'
    jne ac_move
    push ecx
    push edx
    mov eax, [ebp+A_TO]
    mov eax, [eax]
    mov edx, [eax+C_COMPONENT]
    mov eax, [ebp+A_FROM]
    mov eax, [eax]
    mov ecx, [eax+C_COMPONENT]
    call @jbv_assignable@8
    pop edx
    pop ecx
    test eax, eax
    jnz ac_move
    push esi                            ; element by element, checking each
    mov esi, edx
    shr ecx, 2
    jz ac_checked
ac_element:
    mov edx, [esi]
    test edx, edx
    jz ac_put
    push ecx
    push eax
    push esp
    mov ecx, ebx
    call @jbv_object@12
    pop edx                             ; the element
    test eax, eax
    jnz ac_element_fail
    mov eax, [ebp+A_TO]
    mov eax, [eax]
    mov ecx, [edx]
    mov edx, [eax+C_COMPONENT]
    call @jbv_assignable@8
    test eax, eax
    mov eax, S_STORE
    jz ac_element_fail
    pop ecx
ac_put:
    movsd
    dec ecx
    jnz ac_element
ac_checked:
    pop esi
    jmp ac_barriers
ac_element_fail:
    pop ecx
    pop esi
    jmp ac_ret
ac_move:                                ; memmove: backwards when it overlaps forwards
    push esi
    mov esi, edx
    cmp edi, esi
    jbe @F
    lea eax, [esi+ecx]
    cmp edi, eax
    jae @F
    lea esi, [esi+ecx-1]
    lea edi, [edi+ecx-1]
    std
    rep movsb
    cld
    pop esi
    jmp ac_barriers
@@:
    rep movsb
    pop esi
ac_barriers:
    mov eax, [ebp+A_FROM]
    mov eax, [eax]
    cmp BYTE PTR [eax+C_ARRAY_KIND], 'L'
    jne ac_ok
    mov edi, [esi+16]                   ; each stored reference, for the generations
    mov eax, [esi+12]
    mov ecx, [ebp+A_TO]
    lea esi, [ecx+eax*4+DATA0]
    test edi, edi
    jz ac_ok
@@:
    lodsd
    push eax
    mov edx, [ebp+A_TO]
    mov ecx, ebx
    call @jbv_barrier_checked@12
    dec edi
    jnz @B
ac_ok:
    xor eax, eax
    jmp ac_ret
ac_store:
    mov eax, S_STORE
    jmp ac_ret
ac_bounds:
    mov eax, S_BOUNDS
ac_ret:
    pop edi
    mov esp, ebp
    pop ebp
    ret

; JbvStatus JBV_CALL hook(vm, user, a, count, out): the Support natives
H_VM   EQU 8
H_USER EQU 12
H_ARGS EQU 16
H_OUT  EQU 24
H_LOCAL EQU -4
hook PROC
    push ebp
    mov ebp, esp
    push ecx
    push ebx
    push esi
    push edi
    mov ebx, [ebp+H_VM]
    mov esi, [ebp+H_ARGS]
    mov edi, [ebp+H_OUT]
    xor eax, eax
    mov [edi], eax
    mov [edi+4], eax
    mov eax, [ebp+H_USER]
    cmp eax, OP_RESOURCE
    je hk_resource
    cmp eax, 14
    ja hk_dynamic
    jmp DWORD PTR [hk_table+eax*4]
hk_primitive:
    push edi
    movzx edx, BYTE PTR [esi]
    mov ecx, ebx
    call @jbv_primitive_mirror@12
    jmp hk_ret
hk_copy:
    call arraycopy
    jmp hk_ret
hk_array:
    lea eax, [ebp+H_LOCAL]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz hk_ret
    mov edx, [ebp+H_LOCAL]
    mov edx, [edx]
    mov eax, S_CAST
    cmp BYTE PTR [edx+C_ARRAY_KIND], 'L'
    jne hk_ret
    push edi
    push DWORD PTR [esi+4]
    mov ecx, ebx
    call @jbv_new@16
    jmp hk_ret
hk_long:
    mov eax, [esi+4]
    mov [edi+4], eax
hk_int:
    mov eax, [esi]
    mov [edi], eax
hk_ok:
    xor eax, eax
    jmp hk_ret
hk_clock:
    mov eax, S_NATIVE
    mov ecx, [ebx+VM_CLOCK]
    test ecx, ecx
    jz hk_ret
    xor eax, eax
    cmp [esi], eax
    setne al
    push eax
    push DWORD PTR [ebx+VM_SERVICES_USER]
    call ecx
    add esp, 8
    mov [edi], eax
    mov [edi+4], edx
    jmp hk_ok
hk_write:
    mov eax, S_NATIVE
    mov ecx, [ebx+VM_WRITE]
    test ecx, ecx
    jz hk_ret
    xor eax, eax
    cmp [esi+4], eax
    setne al
    push eax
    push DWORD PTR [esi]
    push DWORD PTR [ebx+VM_SERVICES_USER]
    push ebx
    call ecx
    add esp, 16
    jmp hk_ret
hk_collect:
    push ebx
    call jbv_collect
    pop ecx
    jmp hk_ret
hk_parse:
    push edi
    xor eax, eax
    cmp [esi+4], eax
    setne al
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_parse_fp@16
    jmp hk_ret
hk_sqrt:
    fld QWORD PTR [esi]
    fsqrt
    fstp QWORD PTR [edi]
    jmp hk_ok
hk_round:                               ; floor, ceil, rint by the x87 rounding control
    mov eax, [esi+4]
    not eax
    test eax, 7FF00000h                 ; NaN and infinities as they are (a signaling NaN stays)
    jz hk_long
    mov eax, [esi+8]
    fnstcw WORD PTR [ebp+H_LOCAL]
    movzx ecx, WORD PTR [ebp+H_LOCAL]
    and ch, 0F3h
    or cx, [round_cw+eax*2]
    mov [ebp+H_LOCAL+2], cx
    fld QWORD PTR [esi]
    fldcw WORD PTR [ebp+H_LOCAL+2]
    frndint
    fldcw WORD PTR [ebp+H_LOCAL]
    fstp QWORD PTR [edi]
    jmp hk_ok
hk_ascii:                               ; ascii(byte[] b, int off, int len, char[] out): the leading ASCII run
    mov eax, S_NULL
    cmp DWORD PTR [esi], 0
    je hk_ret
    cmp DWORD PTR [esi+12], 0
    je hk_ret
    lea eax, [ebp+H_LOCAL]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    push 0
    push esp
    mov edx, [esi+12]
    mov ecx, ebx
    call @jbv_object@12
    pop edx                             ; to
    mov eax, [ebp+H_LOCAL]              ; from
    mov ecx, [eax-4]
    sub ecx, [esi+4]
    jb hk_bounds
    cmp ecx, [esi+8]
    jb hk_bounds
    mov ecx, [esi+8]
    cmp [edx-4], ecx
    jb hk_bounds
    mov ecx, [esi+4]
    or ecx, [esi+8]
    js hk_bounds
    add eax, [esi+4]
    lea esi, [eax+DATA0]
    mov ecx, [ebp+H_ARGS]
    mov ecx, [ecx+8]
    lea eax, [edx+DATA0]
    push edi
    mov edi, eax
    xor edx, edx
    jecxz hk_ascii_done
@@:
    movsx eax, BYTE PTR [esi+edx]
    test eax, eax
    js hk_ascii_done
    stosw
    inc edx
    cmp edx, ecx
    jb @B
hk_ascii_done:
    pop edi
    mov [edi], edx
    jmp hk_ok
hk_bounds:
    mov eax, S_BOUNDS
    jmp hk_ret
hk_dynamic:
    push edi
    push esi
    lea edx, [eax-15]
    mov ecx, ebx
    call @jbv_dynamic_native@16
    jmp hk_ret
hk_resource:
    call resource
hk_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
hook ENDP
.const
hk_table DD hk_primitive, hk_copy, hk_array, hk_int, hk_clock, hk_write, hk_collect
    DD hk_int, hk_int, hk_long, hk_long, hk_parse, hk_sqrt, hk_round, hk_ascii
.code

; Support.resource(name): an entry of the application JAR as a new byte[], or null
; (ebx = vm, esi = the arguments, edi = out -> eax status)
R_NAME  EQU -8        ; JbvText (freed)
R_DATA  EQU -12       ; the entry (freed)
R_SIZE  EQU -16
R_CLASS EQU -20
resource:
    push ebp
    mov ebp, esp
    sub esp, 20
    push esi
    push edi
    xor eax, eax
    mov [ebp+R_NAME], eax
    mov [ebp+R_DATA], eax
    cmp DWORD PTR [ebx+VM_APP_JAR], 0   ; no resources: null
    je rs_ret
    mov eax, S_NULL
    mov edx, [esi]
    test edx, edx
    jz rs_ret
    lea eax, [ebp+R_NAME]
    push eax
    mov ecx, ebx
    call @jbv_text_bytes@12
    test eax, eax
    jnz rs_ret
    push 1                              ; verify: the host's JAR
    lea eax, [ebp+R_SIZE]
    push eax
    lea eax, [ebp+R_DATA]
    push eax
    push OFFSET rs_none
    movzx eax, WORD PTR [ebp+R_NAME+4]
    push eax
    push DWORD PTR [ebp+R_NAME]
    push DWORD PTR [ebx+VM_APP_JAR_SIZE]
    push DWORD PTR [ebx+VM_APP_JAR]
    push ebx
    call jbv_jar_read
    add esp, 36
    cmp eax, S_NOT_FOUND
    je rs_null
    test eax, eax
    jnz rs_free
    lea eax, [ebp+R_CLASS]              ; a byte[] of it
    push eax
    push 'B'
    xor edx, edx
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz rs_free
    push edi
    push DWORD PTR [ebp+R_SIZE]
    mov edx, [ebp+R_CLASS]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz rs_free
    push 0
    push esp
    mov edx, [edi]
    mov ecx, ebx
    call @jbv_object@12
    pop edi
    add edi, DATA0
    mov esi, [ebp+R_DATA]
    mov ecx, [ebp+R_SIZE]
    rep movsb
rs_null:
    xor eax, eax
rs_free:
    push eax
    mov edx, [ebp+R_DATA]
    mov ecx, ebx
    call @jbv_free@8
    mov edx, [ebp+R_NAME]
    mov ecx, ebx
    call @jbv_free@8
    pop eax
rs_ret:
    pop edi
    pop esi
    mov esp, ebp
    pop ebp
    ret
.const
rs_none DB 0
.code

; JbvStatus jbv_classpath_find(vm, name, data, size): a class file of the library (opened once)
@jbv_classpath_find@20 PROC SYSCALL ; ecx vm, edx data, [esp+4] name, [esp+12] size
    push ebx
    push esi
    mov ebx, ecx
    mov esi, edx
    cmp DWORD PTR [ebx+VM_LIBRARY], 0
    jne @F
    push 0
    push jbv_library_jar_size
    push OFFSET jbv_library_jar
    lea eax, [ebx+VM_LIBRARY]
    push eax
    push ebx
    call jbv_archive_open
    add esp, 20
    test eax, eax
    jnz cf_ret
@@:
    push DWORD PTR [esp+20]
    push esi
    push DWORD PTR [esp+24]
    push DWORD PTR [esp+24]
    lea eax, [ebx+VM_LIBRARY]
    push eax
    call jbv_archive_find
    add esp, 20
cf_ret:
    pop esi
    pop ebx
    ret 12
@jbv_classpath_find@20 ENDP

; esi = the class, edx = a name table, eax = the native entry: binds its native methods by name
bind_natives:
    push ebp
    push edi
    mov ebp, eax
    mov edi, [esi+C_METHODS]
    movzx ecx, WORD PTR [esi+C_METHOD_COUNT]
    test ecx, ecx
    jz bn_ok
bn_method:
    test WORD PTR [edi+M_FLAGS], NATIVE
    jz bn_next
    push ecx
    push esi
    push edi
    mov ebx, edx
    xor eax, eax                        ; the index
bn_name:
    movzx ecx, BYTE PTR [ebx]
    jecxz bn_missing
    inc ebx
    cmp cx, WORD PTR [edi+M_NAME+TEXT_SIZE]
    jne bn_skip
    mov esi, [edi+M_NAME+TEXT_DATA]
    push edi
    mov edi, ebx
    push ecx
    repe cmpsb
    pop ecx
    pop edi
    je bn_found
bn_skip:
    add ebx, ecx
    inc eax
    jmp bn_name
bn_missing:
    pop edi
    pop esi
    pop ecx
    mov eax, S_LINKAGE
    jmp bn_ret
bn_found:
    pop edi
    pop esi
    pop ecx
    mov [edi+M_NATIVE_SLOTS], ebp
    mov [edi+M_NATIVE_USER], eax
    mov BYTE PTR [edi+M_INTRINSIC], 4
bn_next:
    add edi, M_SIZEOF
    dec ecx
    jnz bn_method
bn_ok:
    xor eax, eax
bn_ret:
    pop edi
    pop ebp
    ret

; JbvStatus jbv_classpath_load(vm, name, out): a library class, parsed (adopting its slice) and linked
L_IMAGE EQU -4
L_SIZE  EQU -8
L_CLASS EQU -12
@jbv_classpath_load@16 PROC SYSCALL ; ecx vm, edx out, [ebp+8] name
    push ebp
    mov ebp, esp
    sub esp, 12
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    lea eax, [ebp+L_SIZE]
    push eax
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    lea edx, [ebp+L_IMAGE]
    call @jbv_classpath_find@20
    test eax, eax
    jnz cl_ret
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    mov ecx, ebx
    call @jbv_find_class@12
    mov esi, eax
    test eax, eax
    jnz cl_link
    lea eax, [ebp+L_CLASS]
    push eax
    push DWORD PTR [ebp+L_SIZE]
    push DWORD PTR [ebp+L_IMAGE]
    push ebx
    call jbv_parse_owned
    add esp, 16
    test eax, eax
    jnz cl_ret
    mov esi, [ebp+L_CLASS]
    mov eax, [ebx+VM_CLASSES]
    mov [esi+C_NEXT], eax
    mov [ebx+VM_CLASSES], esi
    mov ecx, [ebp+12]                   ; the runtime classes with built-in natives
    and ecx, 0FFFFh
    mov edx, OFFSET hooks
    mov eax, OFFSET hook
    cmp ecx, 19
    je @F
    mov edx, OFFSET reflection
    mov eax, OFFSET jbv_reflect_native
    cmp ecx, 22
    jne cl_link
@@:
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, OFFSET n_support
    cmp edx, OFFSET hooks
    je @F
    mov edi, OFFSET n_reflection
@@:
    repe cmpsb
    pop edi
    pop esi
    jne cl_link
    push ebx
    call bind_natives
    pop ebx
    test eax, eax
    jnz cl_ret
cl_link:
    mov [edi], esi
    push 0
    mov edx, esi
    mov ecx, ebx
    call @jbv_link@12
cl_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_classpath_load@16 ENDP
END

; Exceptions for x86 (exceptions.c and trace.c are the reference and serve x64): the
; built-in Throwable classes made on first use, their natives, throwing by name with a
; captured stack trace, status -> exception. Same fastcall names as the C functions.
; Every allocation may move objects: refs are kept, pointers fetched again after it.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_free_class@8:PROC
EXTERN SYSCALL @jbv_prepare_method@4:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_link@12:PROC
EXTERN SYSCALL @jbv_classpath_find@20:PROC
EXTERN SYSCALL @jbv_classpath_load@16:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_array_class@16:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC
EXTERN SYSCALL @jbv_string_mutf@16:PROC
EXTERN SYSCALL @jbv_string_view@12:PROC
EXTERN SYSCALL @jbv_execute@28:PROC

S_OK          EQU 0
S_BAD_ARG     EQU 1
S_OOM         EQU 2
S_UNSUPPORTED EQU 6
S_NOT_FOUND   EQU 7
S_DIVIDE      EQU 9
S_NULL        EQU 12
S_ILLEGAL     EQU 19
NATIVE        EQU 100h

.const
INCLUDE exception_types.inc
s_object     DB 16, 'java/lang/Object'
s_support    DB 19, 'jbv/runtime/Support'
s_init       DB 6, '<init>'
s_fill       DB 16, 'fillInStackTrace'
s_element    DB 27, 'java/lang/StackTraceElement'
s_by_zero    DB 9, '/ by zero'
; Throwable's methods: counted name, counted descriptor (ids as exception_native's)
methods LABEL BYTE
    DB 6, '<init>', 3, '()V'
    DB 6, '<init>', 21, '(Ljava/lang/String;)V'
    DB 6, '<init>', 24, '(Ljava/lang/Throwable;)V'
    DB 6, '<init>', 42, '(Ljava/lang/String;Ljava/lang/Throwable;)V'
    DB 6, '<init>', 44, '(Ljava/lang/String;Ljava/lang/Throwable;ZZ)V'
    DB 10, 'getMessage', 20, '()Ljava/lang/String;'
    DB 8, 'getCause', 23, '()Ljava/lang/Throwable;'
    DB 9, 'initCause', 46, '(Ljava/lang/Throwable;)Ljava/lang/Throwable;'
    DB 13, 'addSuppressed', 24, '(Ljava/lang/Throwable;)V'
    DB 13, 'getSuppressed', 24, '()[Ljava/lang/Throwable;'
fields LABEL BYTE
    DB 13, 'detailMessage', 18, 'Ljava/lang/String;'
    DB 5, 'cause', 21, 'Ljava/lang/Throwable;'
    DB 10, 'suppressed', 22, '[Ljava/lang/Throwable;'

.code
; ZF = the JbvText at eax equals the counted string at ecx
lit_eq:
    push esi
    push edi
    push ecx
    movzx edi, BYTE PTR [ecx]
    cmp di, WORD PTR [eax+TEXT_SIZE]
    jne le_done
    mov esi, [eax+TEXT_DATA]
    lea edi, [ecx+1]
    movzx ecx, BYTE PTR [ecx]
    repe cmpsb
le_done:
    pop ecx
    pop edi
    pop esi
    ret
; ecx = counted string -> eax = its chars, edx = its length; ecx -> after it
counted:
    movzx edx, BYTE PTR [ecx]
    lea eax, [ecx+1]
    lea ecx, [eax+edx]
    ret
; ecx = C string -> eax = ecx, edx = its length
c_text:
    push edi
    push ecx
    mov edi, ecx
    xor eax, eax
    or ecx, -1
    repne scasb
    not ecx
    lea edx, [ecx-1]
    pop eax
    pop edi
    ret
; eax = an object pointer -> eax = its first data word's address
DATA0 EQU 4

; ---- the stack trace: StackTraceElement[] of the frames below the throw machinery
T_VM    EQU -4
T_OUT   EQU -8
T_FIRST EQU -12
T_ARRT  EQU -16
T_AREF  EQU -20
T_LEN   EQU -24
T_REF   EQU -28
T_TEXT  EQU -32
T_OBJ   EQU -36
T_VIEW  EQU -44       ; JbvTextView: data, length
T_STAT  EQU -48
T_LOCALS EQU 48

internal_frame:         ; esi = frame -> ZF = 0 if it is internal (Support, or a Throwable's <init>/fillInStackTrace)
    mov eax, [esi+FR_OWNER]
    add eax, C_NAME
    mov ecx, OFFSET s_support
    call lit_eq
    je if_yes
    mov edx, [ebx+VM_THROWABLE]
    mov ecx, [esi+FR_OWNER]
    call @jbv_assignable@8
    test eax, eax
    jz if_no
    mov eax, [esi+FR_METHOD]
    add eax, M_NAME
    mov ecx, OFFSET s_init
    call lit_eq
    je if_yes
    mov ecx, OFFSET s_fill
    call lit_eq
    je if_yes
if_no:
    xor eax, eax
    ret
if_yes:
    or eax, 1
    ret

@jbv_capture_trace@8 PROC SYSCALL
    push ebp
    mov ebp, esp
    sub esp, T_LOCALS
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov [ebp+T_OUT], edx
    cmp DWORD PTR [ebx+VM_THROWABLE], 0
    jne @F
    push 19
    push OFFSET t_Throwable+1
    lea edx, [ebx+VM_THROWABLE]
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz ct_return
@@:
    mov esi, [ebx+VM_FRAMES]
ct_skip:
    test esi, esi
    jz ct_first
    call internal_frame
    jz ct_first
    mov esi, [esi+FR_PREVIOUS]
    jmp ct_skip
ct_first:
    mov [ebp+T_FIRST], esi
    xor eax, eax
@@:
    test esi, esi
    jz @F
    inc eax
    mov esi, [esi+FR_PREVIOUS]
    jmp @B
@@:
    mov [ebp+T_LEN], eax
    xor eax, eax
    cmp DWORD PTR [ebx+VM_TRACE_ELEMENT], 0
    jne @F
    push 27
    push OFFSET s_element+1
    lea edx, [ebx+VM_TRACE_ELEMENT]
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz ct_return
@@:
    lea eax, [ebp+T_ARRT]
    push eax
    push 'L'
    mov edx, [ebx+VM_TRACE_ELEMENT]
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz ct_return
    lea eax, [ebp+T_AREF]
    push eax
    push DWORD PTR [ebp+T_LEN]
    mov edx, [ebp+T_ARRT]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz ct_return
    push DWORD PTR [ebp+T_AREF]
    push ebx
    call jbv_retain
    add esp, 8
    mov DWORD PTR [ebp+T_STAT], S_OK
    mov esi, [ebp+T_FIRST]
    xor edi, edi                        ; element index
ct_frame:
    test esi, esi
    jz ct_done
    lea eax, [ebp+T_REF]
    push eax
    push 0
    mov edx, [ebx+VM_TRACE_ELEMENT]
    mov ecx, ebx
    call @jbv_new@16
    mov [ebp+T_STAT], eax
    test eax, eax
    jnz ct_done
    mov eax, [ebp+T_AREF]
    call obj_of
    mov edx, [ebp+T_REF]
    mov [eax+edi*4+DATA0], edx
    inc edi
    call store_barrier                  ; eax = the array, edx = the element
    ; declaring class (dots), method name, source file
    mov eax, [esi+FR_OWNER]
    lea eax, [eax+C_NAME]
    xor ecx, ecx
    call element_text
    jnz ct_done
    mov eax, [esi+FR_METHOD]
    lea eax, [eax+M_NAME]
    mov ecx, 1
    call element_text
    jnz ct_done
    mov eax, [esi+FR_OWNER]
    lea eax, [eax+C_SOURCE_FILE]
    mov ecx, 2
    call element_text
    jnz ct_done
    mov eax, [esi+FR_METHOD]            ; the line: -2 native, -1 unknown
    mov DWORD PTR [ebp+T_TEXT], -2
    test WORD PTR [eax+M_FLAGS], NATIVE
    jnz ct_line
    mov DWORD PTR [ebp+T_TEXT], -1
    movzx edx, WORD PTR [eax+M_LINE_COUNT]
    mov eax, [eax+M_LINES]
ct_lines:
    dec edx
    js ct_line
    movzx ecx, WORD PTR [eax]           ; start pc, big-endian
    xchg cl, ch
    cmp ecx, [esi+FR_PC]
    ja @F
    movzx ecx, WORD PTR [eax+2]
    xchg cl, ch
    mov [ebp+T_TEXT], ecx
@@:
    add eax, 4
    jmp ct_lines
ct_line:
    mov eax, [ebp+T_REF]
    call obj_of
    mov ecx, [ebp+T_TEXT]
    mov [eax+3*4+DATA0], ecx
    mov esi, [esi+FR_PREVIOUS]
    jmp ct_frame
ct_done:
    cmp DWORD PTR [ebp+T_STAT], S_OK
    jne @F
    mov eax, [ebp+T_OUT]
    mov edx, [ebp+T_AREF]
    mov [eax], edx
@@:
    push DWORD PTR [ebp+T_AREF]
    push ebx
    call jbv_release
    add esp, 8
    mov eax, [ebp+T_STAT]
ct_return:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
@jbv_capture_trace@8 ENDP
; eax = ref -> eax = its object (ebx = vm, in a T frame)
obj_of:
    lea ecx, [ebp+T_OBJ]
    push ecx
    mov edx, eax
    mov ecx, ebx
    call @jbv_object@12
    mov eax, [ebp+T_OBJ]
    ret
; eax = an object, edx = the reference stored into it
store_barrier:
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    ret
; eax = &JbvText, ecx = the field (0 also turns '/' into '.') -> ZF = ok (else T_STAT set)
element_text:
    cmp WORD PTR [eax+TEXT_SIZE], 0
    je et_ok
    push ecx
    lea edx, [ebp+T_TEXT]
    push DWORD PTR [eax+TEXT_SIZE]
    push DWORD PTR [eax+TEXT_DATA]
    mov ecx, ebx
    call @jbv_string_mutf@16
    pop ecx
    mov [ebp+T_STAT], eax
    test eax, eax
    jnz et_ret
    test ecx, ecx
    jnz et_store
    push ecx
    lea eax, [ebp+T_VIEW]
    push eax
    mov edx, [ebp+T_TEXT]
    mov ecx, ebx
    call @jbv_string_view@12
    mov eax, [ebp+T_VIEW]
    mov ecx, [ebp+T_VIEW+4]
    jecxz et_dotted
@@:
    cmp WORD PTR [eax], '/'
    jne et_char
    mov WORD PTR [eax], '.'
et_char:
    add eax, 2
    loop @B
et_dotted:
    pop ecx
et_store:
    push ecx
    mov eax, [ebp+T_REF]
    call obj_of
    pop ecx
    mov edx, [ebp+T_TEXT]
    mov [eax+ecx*4+DATA0], edx
    call store_barrier
et_ok:
    xor eax, eax
et_ret:
    ret

; ---- built-in exception classes
; ZF = the name (JbvText at eax) is a built-in exception; ecx = its record
find_type:
    mov ecx, OFFSET types
ft_loop:
    cmp ecx, OFFSET types_end
    jae ft_none
    call lit_eq
    je ft_ret
    movzx edx, BYTE PTR [ecx]
    lea ecx, [ecx+edx+4]
    jmp ft_loop
ft_none:
    or ecx, ecx                         ; ZF = 0 (the table address is not 0)
ft_ret:
    ret

@jbv_exception_name@8 PROC SYSCALL
    lea eax, [esp+4]
    call find_type
    setz al
    movzx eax, al
    ret 8
@jbv_exception_name@8 ENDP

E_VM     EQU -4
E_OUT    EQU -8
E_TYPE   EQU -12       ; the record
E_PARENT EQU -16
E_CLASS  EQU -20
E_STAT   EQU -24
E_LOCALS EQU 24
@jbv_exception_class@16 PROC SYSCALL   ; ecx vm, edx out, [ebp+8] name
    push ebp
    mov ebp, esp
    sub esp, E_LOCALS
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov [ebp+E_OUT], edx
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call @jbv_find_class@12
    test eax, eax
    jz ec_classpath
    mov ecx, [ebp+E_OUT]
    mov [ecx], eax
    push 0
    mov edx, eax
    mov ecx, ebx
    call @jbv_link@12
    jmp ec_return
ec_classpath:
    push 0
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    xor edx, edx
    mov ecx, ebx
    call @jbv_classpath_find@20
    test eax, eax
    jnz @F
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    mov edx, [ebp+E_OUT]
    mov ecx, ebx
    call @jbv_classpath_load@16
    jmp ec_return
@@:
    cmp eax, S_NOT_FOUND
    jne ec_return
    lea eax, [ebp+8]
    call find_type
    mov eax, S_NOT_FOUND
    jne ec_return
    mov [ebp+E_TYPE], ecx
    movzx edx, BYTE PTR [ecx]
    movzx eax, WORD PTR [ecx+edx+2]     ; the parent
    mov ecx, OFFSET s_object
    cmp eax, 0FFFFh
    je @F
    lea ecx, [eax+types]
@@:
    call counted
    push edx
    push eax
    lea edx, [ebp+E_PARENT]
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz ec_return
    mov edx, C_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz ec_oom
    mov esi, eax                        ; esi = the class
    mov ecx, [ebp+E_TYPE]
    call counted
    mov [esi+C_NAME+TEXT_DATA], eax
    mov [esi+C_NAME+TEXT_SIZE], dx
    mov eax, [ebp+E_PARENT]
    mov [esi+C_SUPER], eax
    mov WORD PTR [esi+C_FLAGS], 1
    mov eax, [eax+C_INSTANCE_SLOTS]
    cmp eax, 3
    jae @F
    mov eax, 3
@@:
    mov [esi+C_INSTANCE_SLOTS], eax
    mov BYTE PTR [esi+C_INIT_STATE], 2
    mov BYTE PTR [esi+C_LINK_STATE], 2
    mov eax, [ebx+VM_CLASSES]
    mov [esi+C_NEXT], eax
    mov [ebx+VM_CLASSES], esi
    mov edx, 10*M_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz ec_fail_oom
    mov [esi+C_METHODS], eax
    mov edi, eax                        ; edi = the method
    mov ecx, 10                         ; a Throwable compiled from the library: its constructors only
    cmp DWORD PTR [esi+C_INSTANCE_SLOTS], 3
    jbe @F
    mov ecx, 5
@@:
    mov [esi+C_METHOD_COUNT], cx
    mov ecx, OFFSET methods
    xor edx, edx                        ; id
ec_method:
    cmp dx, WORD PTR [esi+C_METHOD_COUNT]
    jae ec_methods_done
    push edx
    call counted
    mov [edi+M_NAME+TEXT_DATA], eax
    mov [edi+M_NAME+TEXT_SIZE], dx
    call counted
    mov [edi+M_DESCRIPTOR+TEXT_DATA], eax
    mov [edi+M_DESCRIPTOR+TEXT_SIZE], dx
    pop edx
    mov eax, NATIVE or 1
    cmp edx, 4
    jne @F
    mov eax, NATIVE or 4
@@:
    mov [edi+M_FLAGS], ax
    mov BYTE PTR [edi+M_INTRINSIC], 2
    mov DWORD PTR [edi+M_NATIVE], OFFSET exception_native
    mov [edi+M_NATIVE_USER], edx
    push ecx
    push edx
    mov ecx, edi
    call @jbv_prepare_method@4
    pop edx
    pop ecx
    inc edx
    add edi, M_SIZEOF
    jmp ec_method
ec_methods_done:
    mov eax, [ebp+E_TYPE]
    cmp eax, OFFSET types               ; Throwable itself: its three fields
    jne ec_done
    mov edx, 3*FIELD_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz ec_fail_oom
    mov [esi+C_FIELDS], eax
    mov WORD PTR [esi+C_FIELD_COUNT], 3
    mov edi, eax
    mov ecx, OFFSET fields
    xor edx, edx
@@:
    push edx
    call counted
    mov [edi+FIELD_NAME+TEXT_DATA], eax
    mov [edi+FIELD_NAME+TEXT_SIZE], dx
    call counted
    mov [edi+FIELD_DESCRIPTOR+TEXT_DATA], eax
    mov [edi+FIELD_DESCRIPTOR+TEXT_SIZE], dx
    pop edx
    mov [edi+FIELD_SLOT], edx
    add edi, FIELD_SIZEOF
    inc edx
    cmp edx, 3
    jb @B
ec_done:
    mov eax, [ebp+E_OUT]
    mov [eax], esi
    xor eax, eax
    jmp ec_return
ec_fail_oom:                            ; unlink and free the class
    mov eax, [esi+C_NEXT]
    mov [ebx+VM_CLASSES], eax
    mov edx, esi
    mov ecx, ebx
    call @jbv_free_class@8
ec_oom:
    mov eax, S_OOM
ec_return:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_exception_class@16 ENDP

; ---- natives of the built-in Throwable: JbvStatus exception_native(vm, user = id, a, count, out), cdecl
N_VM    EQU 8
N_ID    EQU 12
N_ARGS  EQU 16
N_COUNT EQU 20
N_OUT   EQU 24
N_OBJ   EQU -4
N_TYPE  EQU -8
N_ARRT  EQU -12
N_REF   EQU -16
N_OLD   EQU -20
N_LEN   EQU -24
N_IGN   EQU -32       ; uint64_t
N_LOCALS EQU 32
exception_native PROC
    push ebp
    mov ebp, esp
    sub esp, N_LOCALS
    push ebx
    push esi
    push edi
    mov ebx, [ebp+N_VM]
    mov esi, [ebp+N_ARGS]
    lea eax, [ebp+N_OBJ]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz en_return
    mov eax, [ebx+VM_THROWABLE]
    test eax, eax
    jnz @F
    push 19
    push OFFSET t_Throwable+1
    mov ecx, ebx
    call @jbv_find_class@12
    mov [ebx+VM_THROWABLE], eax
@@:
    mov edi, [ebp+N_ID]
    test eax, eax
    jz en_builtin
    cmp DWORD PTR [eax+C_INSTANCE_SLOTS], 3
    jbe en_builtin
    cmp edi, 4
    ja en_builtin
    ; a Throwable from the library: its own constructor
    mov edx, [ebx+edi*4+VM_THROWABLE_INIT]
    test edx, edx
    jnz en_ctor
    push eax
    mov ecx, OFFSET methods             ; descriptor of method id edi
    mov edx, edi
@@:
    push edx
    call counted
    call counted
    pop edx
    dec edx
    jns @B
    movzx edx, BYTE PTR [eax-1]         ; eax = the last descriptor's chars
    push edx
    push eax
    push 6
    push OFFSET s_init+1
    mov ecx, [esp+16]
    call @jbv_find_method@20
    pop ecx                             ; the class
    mov [ebx+edi*4+VM_THROWABLE_INIT], eax
    mov edx, eax
    mov eax, ecx
    test edx, edx
    jnz en_ctor
    mov eax, S_NOT_FOUND
    jmp en_return
en_ctor:                                ; jbv_execute(vm, throwable, ctor, a, 0, count, &ignored)
    lea ecx, [ebp+N_IGN]
    push ecx
    push DWORD PTR [ebp+N_COUNT]
    push 0
    push esi
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_execute@28
    jmp en_return
en_builtin:
    mov eax, [ebp+N_OBJ]
    lea edx, [eax+DATA0]                ; edx = the fields: message, cause, suppressed
    cmp edi, 4
    ja en_get
    xor eax, eax                        ; constructors
    cmp edi, 1
    je en_msg
    cmp edi, 3
    jb @F
en_msg:
    mov eax, [esi+4]
@@:
    mov [edx], eax
    mov eax, [esi]                      ; cause: the receiver itself means none yet
    cmp edi, 2
    jne @F
    mov eax, [esi+4]
@@:
    cmp edi, 3
    jb @F
    mov eax, [esi+8]
@@:
    mov [edx+4], eax
    mov DWORD PTR [edx+8], 0
    push edx
    push DWORD PTR [edx]
    mov edx, [ebp+N_OBJ]
    mov ecx, ebx
    call @jbv_barrier_checked@12
    pop edx
    push DWORD PTR [edx+4]
    mov edx, [ebp+N_OBJ]
    mov ecx, ebx
    call @jbv_barrier_checked@12
    xor eax, eax
    jmp en_return
en_get:
    mov ecx, [ebp+N_OUT]
    cmp edi, 5
    jne @F
    mov eax, [edx]                      ; getMessage
    mov [ecx], eax
    xor eax, eax
    jmp en_return
@@:
    cmp edi, 6
    jne @F
    mov eax, [edx+4]                    ; getCause
    cmp eax, [esi]
    jne en_put
    xor eax, eax
en_put:
    mov [ecx], eax
    xor eax, eax
    jmp en_return
@@:
    cmp edi, 7
    jne @F
    mov eax, S_ILLEGAL                  ; initCause
    mov ecx, [esi]
    cmp [edx+4], ecx
    jne en_return
    mov eax, S_BAD_ARG
    cmp [esi+4], ecx
    je en_return
    mov eax, [esi+4]
    mov [edx+4], eax
    push eax
    mov edx, [ebp+N_OBJ]
    mov ecx, ebx
    call @jbv_barrier_checked@12
    mov eax, [esi]
    mov ecx, [ebp+N_OUT]
    jmp en_put
@@:
    cmp edi, 8
    jne @F
    mov eax, S_NULL                     ; addSuppressed
    cmp DWORD PTR [esi+4], 0
    je en_return
    mov eax, S_BAD_ARG
    mov ecx, [esi]
    cmp [esi+4], ecx
    je en_return
    jmp en_array
@@:
    mov eax, S_UNSUPPORTED
    cmp edi, 9
    jne en_return
en_array:                               ; the suppressed array, one longer for addSuppressed
    mov DWORD PTR [ebp+N_LEN], 0
    mov eax, [edx+8]
    test eax, eax
    jz @F
    lea ecx, [ebp+N_OLD]
    push ecx
    mov edx, eax
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz en_return
    mov eax, [ebp+N_OLD]
    mov eax, [eax-4]
    mov [ebp+N_LEN], eax
@@:
    push 19
    push OFFSET t_Throwable+1
    lea edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_exception_class@16
    test eax, eax
    jnz en_return
    lea eax, [ebp+N_ARRT]
    push eax
    push 'L'
    mov edx, [ebp+N_TYPE]
    mov ecx, ebx
    call @jbv_array_class@16
    test eax, eax
    jnz en_return
    lea eax, [ebp+N_REF]
    push eax
    mov eax, [ebp+N_LEN]
    cmp edi, 8
    jne @F
    inc eax
@@:
    push eax
    mov edx, [ebp+N_ARRT]
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz en_return
    ; jbv_new may have moved everything: the receiver, the old array and the new one again
    lea eax, [ebp+N_OBJ]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    lea eax, [ebp+N_ARRT]               ; reused: the new array
    push eax
    mov edx, [ebp+N_REF]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz en_return
    mov ecx, [ebp+N_LEN]
    jecxz en_copied
    mov eax, [ebp+N_OBJ]
    lea eax, [ebp+N_OLD]
    push eax
    mov eax, [ebp+N_OBJ]
    mov edx, [eax+DATA0+8]
    mov ecx, ebx
    call @jbv_object@12
    push esi
    mov esi, [ebp+N_OLD]
    add esi, DATA0
    mov eax, [ebp+N_ARRT]
    lea edi, [eax+DATA0]
    mov ecx, [ebp+N_LEN]
    rep movsd
    pop esi
    mov edi, [ebp+N_ID]
en_copied:
    cmp edi, 8
    je en_add
    mov eax, [ebp+N_REF]
    mov ecx, [ebp+N_OUT]
    jmp en_put
en_add:
    mov eax, [ebp+N_ARRT]
    mov ecx, [ebp+N_LEN]
    mov edx, [esi+4]
    mov [eax+ecx*4+DATA0], edx
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    mov eax, [ebp+N_OBJ]
    mov edx, [ebp+N_REF]
    mov [eax+DATA0+8], edx
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    xor eax, eax
en_return:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
exception_native ENDP

; ---- throwing
H_TYPE  EQU -4
H_OBJ   EQU -8
H_REF   EQU -12
H_LIMIT EQU -16
H_EMERG EQU -20
H_TRACE EQU -24
H_LOCALS EQU 24
@jbv_throw_named@16 PROC SYSCALL     ; ecx vm, edx name; [ebp+8] cause, [ebp+12] status
    push ebp
    mov ebp, esp
    sub esp, H_LOCALS
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov esi, edx
    mov edi, OFFSET t_OutOfMemoryError+1              ; the emergency OutOfMemoryError
    mov ecx, 27
    push esi
    repe cmpsb
    pop esi
    sete al
    movzx eax, al
    mov [ebp+H_EMERG], eax
    test eax, eax
    jz tn_class
    lea eax, [ebp+H_OBJ]
    push eax
    mov edx, [ebx+VM_EMERGENCY_OOM]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz tn_class
    mov eax, [ebx+VM_EMERGENCY_OOM]
    mov [ebx+VM_EXCEPTION], eax
    mov eax, [ebp+12]
    mov [ebx+VM_EXCEPTION_STATUS], eax
    jmp tn_status
tn_class:
    mov ecx, esi
    call c_text
    push edx
    push eax
    lea edx, [ebp+H_TYPE]
    mov ecx, ebx
    call @jbv_exception_class@16
    test eax, eax
    jnz tn_status
    mov eax, [ebx+VM_HEAP_LIMIT]        ; an OutOfMemoryError may exceed the heap limit
    mov [ebp+H_LIMIT], eax
    cmp DWORD PTR [ebp+H_EMERG], 0
    je @F
    mov DWORD PTR [ebx+VM_HEAP_LIMIT], -1
@@:
    lea eax, [ebp+H_REF]
    push eax
    push 0
    mov edx, [ebp+H_TYPE]
    mov ecx, ebx
    call @jbv_new@16
    mov edx, [ebp+H_LIMIT]
    mov [ebx+VM_HEAP_LIMIT], edx
    test eax, eax
    jnz tn_status
    mov eax, [ebp+H_REF]
    mov [ebx+VM_EXCEPTION], eax
    mov edx, [ebp+12]
    mov [ebx+VM_EXCEPTION_STATUS], edx
    cmp DWORD PTR [ebp+H_EMERG], 0
    je @F
    mov [ebx+VM_EMERGENCY_OOM], eax
@@:
    lea eax, [ebp+H_OBJ]
    push eax
    mov edx, [ebp+H_REF]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz tn_status
    mov eax, [ebp+H_OBJ]
    mov edx, [ebp+8]                    ; cause: none is the exception itself
    test edx, edx
    jnz @F
    mov edx, [ebp+H_REF]
@@:
    mov [eax+DATA0+4], edx
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    mov eax, [ebp+H_TYPE]
    cmp DWORD PTR [eax+C_INSTANCE_SLOTS], 3
    jbe tn_status
    mov eax, [ebp+H_OBJ]
    mov DWORD PTR [eax+DATA0+16], 1
    mov DWORD PTR [eax+DATA0+20], 1
    ; capturing allocates (the exception stays rooted in vm->exception): store afterwards
    lea edx, [ebp+H_TRACE]
    mov ecx, ebx
    call @jbv_capture_trace@8
    test eax, eax
    jnz tn_status
    lea eax, [ebp+H_OBJ]
    push eax
    mov edx, [ebp+H_REF]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz tn_status
    mov eax, [ebp+H_OBJ]
    mov edx, [ebp+H_TRACE]
    mov [eax+DATA0+12], edx
    push edx
    mov edx, eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
tn_status:
    mov eax, [ebp+12]
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_throw_named@16 ENDP

; jbv_throw_named with the detail message owner[.member]descriptor ('/' -> '.' with dots)
D_OWNER EQU 8
D_MEMBER EQU 16
D_DESC  EQU 24
D_DOTS  EQU 32
D_STAT  EQU 36
D_BUF   EQU -4
D_MSG   EQU -8
D_OBJ   EQU -12
D_LOCALS EQU 12
@jbv_throw_detail@40 PROC SYSCALL
    push ebp
    mov ebp, esp
    sub esp, D_LOCALS
    push ebx
    push esi
    push edi
    mov ebx, ecx
    push DWORD PTR [ebp+D_STAT]
    push 0
    call @jbv_throw_named@16
    mov [ebp+D_STAT], eax
    IF JBV_PROFILE_FULL OR (JBV_PROFILE_CORE EQ 0)
    mov eax, [ebx+VM_EXCEPTION]
    test eax, eax
    jz td_done
    cmp eax, [ebx+VM_EMERGENCY_OOM]
    je td_done
    movzx edx, WORD PTR [ebp+D_OWNER+TEXT_SIZE]
    movzx eax, WORD PTR [ebp+D_MEMBER+TEXT_SIZE]
    add edx, eax
    movzx eax, WORD PTR [ebp+D_DESC+TEXT_SIZE]
    lea edx, [edx+eax+1]
    cmp edx, 0FFFFh
    ja td_done
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz td_done
    mov [ebp+D_BUF], eax
    mov edi, eax
    mov esi, [ebp+D_OWNER+TEXT_DATA]
    movzx ecx, WORD PTR [ebp+D_OWNER+TEXT_SIZE]
    jecxz td_member
@@:
    lodsb
    cmp DWORD PTR [ebp+D_DOTS], 0
    je td_char
    cmp al, '/'
    jne td_char
    mov al, '.'
td_char:
    stosb
    loop @B
td_member:
    movzx ecx, WORD PTR [ebp+D_MEMBER+TEXT_SIZE]
    jecxz td_desc
    mov al, '.'
    stosb
    mov esi, [ebp+D_MEMBER+TEXT_DATA]
    rep movsb
td_desc:
    movzx ecx, WORD PTR [ebp+D_DESC+TEXT_SIZE]
    mov esi, [ebp+D_DESC+TEXT_DATA]
    rep movsb
    sub edi, [ebp+D_BUF]
    lea edx, [ebp+D_MSG]
    push edi
    push DWORD PTR [ebp+D_BUF]
    mov ecx, ebx
    call @jbv_string_mutf@16
    test eax, eax
    jnz td_free
    lea eax, [ebp+D_OBJ]
    push eax
    mov edx, [ebx+VM_EXCEPTION]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz td_free
    mov eax, [ebp+D_OBJ]
    mov edx, [ebp+D_MSG]
    mov [eax+DATA0], edx
td_free:
    mov edx, [ebp+D_BUF]
    mov ecx, ebx
    call @jbv_free@8
td_done:
    ENDIF
    mov eax, [ebp+D_STAT]
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 32
@jbv_throw_detail@40 ENDP

; a C status becomes the Java exception for it (already pending: kept)
@jbv_raise@8 PROC SYSCALL
    mov eax, edx
    cmp DWORD PTR [ecx+VM_EXCEPTION], 0
    je @F
    cmp [ecx+VM_EXCEPTION_STATUS], eax
    je r_done
@@:
    mov DWORD PTR [ecx+VM_EXCEPTION], 0
    mov DWORD PTR [ecx+VM_EXCEPTION_STATUS], 0
    mov edx, OFFSET t_OutOfMemoryError+1
    cmp eax, S_OOM
    je r_throw
    cmp eax, S_DIVIDE
    je r_divide
    mov edx, OFFSET t_NullPointerException+1
    cmp eax, S_NULL
    je r_throw
    mov edx, OFFSET t_ArrayIndexOutOfBoundsException+1
    cmp eax, 13
    je r_throw
    mov edx, OFFSET t_NegativeArraySizeException+1
    cmp eax, 14
    je r_throw
    mov edx, OFFSET t_ArrayStoreException+1
    cmp eax, 15
    je r_throw
    mov edx, OFFSET t_ClassCastException+1
    cmp eax, 16
    je r_throw
    mov edx, OFFSET t_IllegalMonitorStateException+1
    cmp eax, 18
    je r_throw
    mov edx, OFFSET t_IllegalArgumentException+1
    cmp eax, S_BAD_ARG
    je r_throw
    mov edx, OFFSET t_IllegalStateException+1
    cmp eax, S_ILLEGAL
    je r_throw
    cmp eax, 11                         ; busy
    je r_throw
    mov edx, OFFSET t_UnsatisfiedLinkError+1
    cmp eax, 21
    je r_throw
r_done:
    ret
r_throw:
    push eax
    push 0
    call @jbv_throw_named@16
    ret
r_divide:                               ; ArithmeticException "/ by zero"
    push eax
    push 0
    push 0
    push 0
    push 0
    push 0
    push 9
    push OFFSET s_by_zero+1
    mov edx, OFFSET t_ArithmeticException+1
    call @jbv_throw_detail@40
    ret
@jbv_raise@8 ENDP
END

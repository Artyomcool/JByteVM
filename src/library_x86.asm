; The built-in library for x86 (library.c is the reference and serves x64): Object, Class,
; String, StringBuilder and the wrappers as VM classes with native method tables, Class
; mirrors, primitive classes and string/class literals.
.686
.model flat, C
option casemap:none
option noscoped
INCLUDE layout_x86.inc
EXTERN SYSCALL @jbv_alloc@8:PROC
EXTERN SYSCALL @jbv_free@8:PROC
EXTERN SYSCALL @jbv_free_class@8:PROC
EXTERN SYSCALL @jbv_object@12:PROC
EXTERN SYSCALL @jbv_new@16:PROC
EXTERN SYSCALL @jbv_object_bytes@4:PROC
EXTERN SYSCALL @jbv_assignable@8:PROC
EXTERN SYSCALL @jbv_find_class@12:PROC
EXTERN SYSCALL @jbv_find_method@20:PROC
EXTERN SYSCALL @jbv_lookup_method@20:PROC
EXTERN SYSCALL @jbv_resolve_class@16:PROC
EXTERN SYSCALL @jbv_class_constant@16:PROC
EXTERN SYSCALL @jbv_classpath_load@16:PROC
EXTERN SYSCALL @jbv_initialize@8:PROC
EXTERN SYSCALL @jbv_execute@28:PROC
EXTERN SYSCALL @jbv_prepare_method@4:PROC
EXTERN SYSCALL @jbv_monitor@16:PROC
EXTERN SYSCALL @jbv_throw_named@16:PROC
EXTERN SYSCALL @jbv_barrier_checked@12:PROC
EXTERN SYSCALL @jbv_string_mutf@16:PROC
EXTERN SYSCALL @jbv_string_view@12:PROC
EXTERN SYSCALL @jbv_string_alloc@16:PROC
EXTERN SYSCALL @jbv_string_intern@12:PROC
EXTERN SYSCALL @jbv_integer_text@20:PROC
EXTERN SYSCALL @jbv_text_native@24:PROC
IF JBV_PROFILE_FULL
EXTERN SYSCALL @jbv_reflect_class@16:PROC
ENDIF
EXTERN jbv_retain:PROC
EXTERN jbv_release:PROC
EXTERN jbv_invoke:PROC

S_OOM       EQU 2
S_BAD_CLASS EQU 3
S_UNSUPPORTED EQU 6
S_NOT_FOUND EQU 7
S_LINKAGE   EQU 8
S_CAST      EQU 16
S_BAD_REF   EQU 17
S_EXCEPTION EQU 22
DATA0       EQU 4
ACC_STATIC  EQU 8
ACC_INTERFACE EQU 200h
ACC_ABSTRACT EQU 400h
NATIVE      EQU 100h
; built-in ids (library.h)
B_OBJECT    EQU 1
B_CLASS     EQU 2
B_STRING    EQU 3
B_BUILDER   EQU 4
B_ABUILDER  EQU 5
B_NUMBER    EQU 6
B_SEQUENCE  EQU 7
B_COMPARABLE EQU 8
B_APPENDABLE EQU 9
B_BOOLEAN   EQU 10
B_CHAR      EQU 12
B_DOUBLE    EQU 17
; native ops (library.h; class ops renamed: the C_ prefix is taken by the class layout)
OP_INIT     EQU 0
OP_JAVA     EQU 18
OP_TEXT_OPS EQU 19                      ; S_INIT and later: text natives
OP_REFLECT  EQU 17

.const
; the one-character reference types of the method tables (expand), counted
x_string  DB 18, 'Ljava/lang/String;'
x_object  DB 18, 'Ljava/lang/Object;'
x_class   DB 17, 'Ljava/lang/Class;'
x_seq     DB 24, 'Ljava/lang/CharSequence;'
x_builder DB 25, 'Ljava/lang/StringBuilder;'
ALIGN 4
expansions DD x_string, x_object, x_class, x_seq, x_builder
; the built-in classes by id (from 1), counted, 0 ends
names DB 16, 'java/lang/Object'
n_class DB 15, 'java/lang/Class'
    DB 16, 'java/lang/String', 23, 'java/lang/StringBuilder'
    DB 31, 'java/lang/AbstractStringBuilder', 16, 'java/lang/Number'
n_sequence DB 22, 'java/lang/CharSequence'
n_comparable DB 20, 'java/lang/Comparable'
n_appendable DB 20, 'java/lang/Appendable'
    DB 17, 'java/lang/Boolean', 14, 'java/lang/Byte'
    DB 19, 'java/lang/Character', 15, 'java/lang/Short', 17, 'java/lang/Integer', 14, 'java/lang/Long'
    DB 15, 'java/lang/Float', 16, 'java/lang/Double', 14, 'java/lang/Void', 0
primitive_codes DB 'ZBCSIJFDV'
primitive_names DB 7, 'boolean', 4, 'byte', 4, 'char', 5, 'short', 3, 'int', 4, 'long', 5, 'float', 6, 'double', 4, 'void'
n_serializable DB 20, 'java/io/Serializable'
IF JBV_PROFILE_FULL
n_face1 DB 34, 'java/lang/reflect/AnnotatedElement'
n_face2 DB 36, 'java/lang/reflect/GenericDeclaration'
n_face3 DB 22, 'java/lang/reflect/Type'
n_strings   DB 'jbv/runtime/Strings'
s_init_name DB 'init'
ENDIF
n_cloneable DB 'java/lang/Cloneable'
n_clone_error DB 'java/lang/CloneNotSupportedException', 0
s_hashcode  DB 'hashCode'
s_int_desc  DB '()I'
s_class_    DB 'class '
s_interface DB 'interface '
s_type      DB 'TYPE'
s_value     DB 'value'
s_long      DB 'J'
s_chars     DB '[C'
; method tables: counted name, counted table descriptor, op, kind, flags; 0 ends
object_methods LABEL BYTE
    DB 6, '<init>', 3, '()V', 0, 0, 0
    DB 6, 'equals', 4, '(#)Z', 1, 0, 0
    DB 8, 'hashCode', 3, '()I', 2, 0, 0
    DB 8, 'getClass', 3, '()$', 3, 0, 0
    DB 8, 'toString', 3, '()!', 4, 0, 0
    DB 6, 'notify', 3, '()V', 5, 0, 0
    DB 9, 'notifyAll', 3, '()V', 5, 0, 0
    DB 5, 'clone', 3, '()#', 6, 0, 4
    DB 0
class_methods LABEL BYTE
    DB 7, 'getName', 3, '()!', 7, 0, 0
    DB 7, 'isArray', 3, '()Z', 8, 0, 0
    DB 11, 'isPrimitive', 3, '()Z', 9, 0, 0
    DB 11, 'isInterface', 3, '()Z', 10, 0, 0
    DB 13, 'getSuperclass', 3, '()$', 11, 0, 0
    DB 16, 'getComponentType', 3, '()$', 12, 0, 0
    DB 16, 'isAssignableFrom', 4, '($)Z', 13, 0, 0
    DB 10, 'isInstance', 4, '(#)Z', 14, 0, 0
    DB 4, 'cast', 4, '(#)#', 15, 0, 0
    DB 8, 'toString', 3, '()!', 16, 0, 0
IF JBV_PROFILE_FULL
    DB 12, 'getModifiers', 3, '()I', 17, 0, 0
    DB 13, 'getInterfaces', 4, '()[$', 17, 1, 0
    DB 7, 'forName', 4, '(!)$', 17, 2, 8
    DB 7, 'forName', 28, '(!ZLjava/lang/ClassLoader;)$', 17, 3, 8
    DB 18, 'getDeclaredMethods', 29, '()[Ljava/lang/reflect/Method;', 17, 4, 0
    DB 10, 'getMethods', 29, '()[Ljava/lang/reflect/Method;', 17, 5, 0
    DB 17, 'getDeclaredMethod', 31, '(![$)Ljava/lang/reflect/Method;', 17, 6, 0
    DB 9, 'getMethod', 31, '(![$)Ljava/lang/reflect/Method;', 17, 7, 0
    DB 17, 'getDeclaredFields', 28, '()[Ljava/lang/reflect/Field;', 17, 8, 0
    DB 9, 'getFields', 28, '()[Ljava/lang/reflect/Field;', 17, 9, 0
    DB 16, 'getDeclaredField', 28, '(!)Ljava/lang/reflect/Field;', 17, 10, 0
    DB 8, 'getField', 28, '(!)Ljava/lang/reflect/Field;', 17, 11, 0
    DB 23, 'getDeclaredConstructors', 34, '()[Ljava/lang/reflect/Constructor;', 17, 12, 0
    DB 15, 'getConstructors', 34, '()[Ljava/lang/reflect/Constructor;', 17, 13, 0
    DB 22, 'getDeclaredConstructor', 35, '([$)Ljava/lang/reflect/Constructor;', 17, 14, 0
    DB 14, 'getConstructor', 35, '([$)Ljava/lang/reflect/Constructor;', 17, 15, 0
    DB 12, 'isAnnotation', 3, '()Z', 17, 16, 0
    DB 11, 'isSynthetic', 3, '()Z', 17, 17, 0
    DB 6, 'isEnum', 3, '()Z', 17, 18, 0
    DB 14, 'getClassLoader', 25, '()Ljava/lang/ClassLoader;', 17, 19, 0
    DB 22, 'getDeclaredAnnotations', 36, '()[Ljava/lang/annotation/Annotation;', 17, 20, 0
    DB 20, 'getGenericSuperclass', 26, '()Ljava/lang/reflect/Type;', 17, 22, 0
    DB 20, 'getGenericInterfaces', 27, '()[Ljava/lang/reflect/Type;', 17, 23, 0
    DB 17, 'getTypeParameters', 35, '()[Ljava/lang/reflect/TypeVariable;', 17, 24, 0
    DB 11, 'getTypeName', 3, '()!', 17, 25, 0
    DB 13, 'getSimpleName', 3, '()!', 17, 26, 0
    DB 14, 'getPackageName', 3, '()!', 17, 27, 0
    DB 16, 'getEnumConstants', 4, '()[#', 17, 28, 0
    DB 16, 'getCanonicalName', 3, '()!', 17, 29, 0
    DB 13, 'isMemberClass', 3, '()Z', 17, 30, 0
    DB 16, 'isAnonymousClass', 3, '()Z', 17, 31, 0
    DB 8, 'isRecord', 3, '()Z', 17, 32, 0
    DB 11, 'getNestHost', 3, '()$', 17, 33, 0
    DB 17, 'getDeclaringClass', 3, '()$', 17, 34, 0
    DB 17, 'getEnclosingClass', 3, '()$', 17, 35, 0
ENDIF
    DB 0
string_methods LABEL BYTE
    DB 6, '<init>', 3, '()V', 19, 0, 0
    DB 6, '<init>', 4, '(!)V', 19, 76, 0
    DB 6, '<init>', 5, '([C)V', 19, 67, 0
    DB 6, '<init>', 7, '([CII)V', 19, 67, 0
    DB 6, 'length', 3, '()I', 20, 0, 0
    DB 7, 'isEmpty', 3, '()Z', 21, 0, 0
    DB 6, 'charAt', 4, '(I)C', 22, 0, 0
    DB 6, 'equals', 4, '(#)Z', 23, 0, 0
    DB 8, 'hashCode', 3, '()I', 24, 0, 0
    DB 8, 'toString', 3, '()!', 25, 0, 0
    DB 9, 'compareTo', 4, '(!)I', 26, 0, 0
    DB 9, 'compareTo', 4, '(#)I', 26, 0, 0
    DB 9, 'substring', 4, '(I)!', 27, 0, 0
    DB 9, 'substring', 5, '(II)!', 27, 0, 0
    DB 11, 'subSequence', 5, '(II)%', 27, 0, 0
    DB 11, 'toCharArray', 4, '()[C', 28, 0, 0
    DB 8, 'getChars', 8, '(II[CI)V', 29, 0, 0
    DB 6, 'concat', 4, '(!)!', 30, 0, 0
    DB 6, 'intern', 3, '()!', 31, 0, 0
    DB 10, 'startsWith', 4, '(!)Z', 32, 0, 0
    DB 4, 'trim', 3, '()!', 37, 0, 0
    DB 7, 'replace', 5, '(CC)!', 38, 67, 0
    DB 7, 'replace', 5, '(%%)!', 38, 0, 0
    DB 8, 'contains', 4, '(%)Z', 39, 0, 0
    DB 6, 'repeat', 4, '(I)!', 40, 0, 0
    DB 10, 'startsWith', 5, '(!I)Z', 32, 0, 0
    DB 8, 'endsWith', 4, '(!)Z', 33, 0, 0
    DB 7, 'indexOf', 4, '(I)I', 34, 73, 0
    DB 7, 'indexOf', 5, '(II)I', 34, 73, 0
    DB 11, 'lastIndexOf', 4, '(I)I', 35, 73, 0
    DB 11, 'lastIndexOf', 5, '(II)I', 35, 73, 0
    DB 7, 'indexOf', 4, '(!)I', 34, 0, 0
    DB 7, 'indexOf', 5, '(!I)I', 34, 0, 0
    DB 11, 'lastIndexOf', 4, '(!)I', 35, 0, 0
    DB 11, 'lastIndexOf', 5, '(!I)I', 35, 0, 0
    DB 7, 'valueOf', 4, '(#)!', 36, 76, 8
    DB 7, 'valueOf', 5, '([C)!', 36, 91, 8
    DB 7, 'valueOf', 7, '([CII)!', 36, 91, 8
    DB 7, 'valueOf', 4, '(Z)!', 36, 90, 8
    DB 7, 'valueOf', 4, '(C)!', 36, 67, 8
    DB 7, 'valueOf', 4, '(I)!', 36, 73, 8
    DB 7, 'valueOf', 4, '(J)!', 36, 74, 8
    DB 7, 'valueOf', 4, '(F)!', 36, 70, 8
    DB 7, 'valueOf', 4, '(D)!', 36, 68, 8
IF JBV_PROFILE_FULL
    DB 11, 'toLowerCase', 3, '()!', 18, 0, 0
    DB 11, 'toUpperCase', 3, '()!', 18, 0, 0
    DB 16, 'equalsIgnoreCase', 4, '(!)Z', 18, 0, 0
    DB 19, 'compareToIgnoreCase', 4, '(!)I', 18, 0, 0
    DB 13, 'regionMatches', 7, '(I!II)Z', 18, 0, 0
    DB 13, 'regionMatches', 8, '(ZI!II)Z', 18, 0, 0
    DB 5, 'split', 5, '(!)[!', 18, 0, 0
    DB 5, 'split', 6, '(!I)[!', 18, 0, 0
    DB 7, 'matches', 4, '(!)Z', 18, 0, 0
    DB 10, 'replaceAll', 5, '(!!)!', 18, 0, 0
    DB 12, 'replaceFirst', 5, '(!!)!', 18, 0, 0
    DB 5, 'strip', 3, '()!', 18, 0, 0
    DB 12, 'stripLeading', 3, '()!', 18, 0, 0
    DB 13, 'stripTrailing', 3, '()!', 18, 0, 0
    DB 7, 'isBlank', 3, '()Z', 18, 0, 0
    DB 11, 'codePointAt', 4, '(I)I', 18, 0, 0
    DB 15, 'codePointBefore', 4, '(I)I', 18, 0, 0
    DB 14, 'codePointCount', 5, '(II)I', 18, 0, 0
    DB 13, 'contentEquals', 4, '(%)Z', 18, 0, 0
    DB 8, 'getBytes', 4, '()[B', 18, 0, 0
    DB 8, 'getBytes', 5, '(!)[B', 18, 0, 0
    DB 8, 'getBytes', 30, '(Ljava/nio/charset/Charset;)[B', 18, 0, 0
    DB 9, 'formatted', 5, '([#)!', 18, 0, 0
    DB 6, 'indent', 4, '(I)!', 18, 0, 0
    DB 5, 'chars', 30, '()Ljava/util/stream/IntStream;', 18, 0, 0
    DB 10, 'codePoints', 30, '()Ljava/util/stream/IntStream;', 18, 0, 0
    DB 11, 'toLowerCase', 21, '(Ljava/util/Locale;)!', 18, 0, 0
    DB 11, 'toUpperCase', 21, '(Ljava/util/Locale;)!', 18, 0, 0
    DB 6, 'format', 24, '(Ljava/util/Locale;![#)!', 18, 0, 8
    DB 4, 'join', 6, '(%[%)!', 18, 0, 8
    DB 4, 'join', 24, '(%Ljava/lang/Iterable;)!', 18, 0, 8
    DB 6, 'format', 6, '(![#)!', 18, 0, 8
    DB 11, 'copyValueOf', 5, '([C)!', 18, 0, 8
    DB 6, '<init>', 5, '([B)V', 18, 0, 0
    DB 6, '<init>', 7, '([BII)V', 18, 0, 0
    DB 6, '<init>', 6, '([B!)V', 18, 0, 0
    DB 6, '<init>', 31, '([BLjava/nio/charset/Charset;)V', 18, 0, 0
    DB 6, '<init>', 33, '([BIILjava/nio/charset/Charset;)V', 18, 0, 0
    DB 6, '<init>', 4, '(&)V', 18, 0, 0
    DB 6, '<init>', 7, '([III)V', 18, 0, 0
ENDIF
    DB 0
builder_methods LABEL BYTE
    DB 6, '<init>', 3, '()V', 41, 0, 0
    DB 6, '<init>', 4, '(I)V', 41, 73, 0
    DB 6, '<init>', 4, '(!)V', 41, 76, 0
    DB 6, '<init>', 4, '(%)V', 41, 81, 0
    DB 6, 'append', 4, '(!)&', 42, 76, 0
    DB 6, 'append', 4, '(#)&', 42, 79, 0
    DB 6, 'append', 4, '(%)&', 42, 81, 0
    DB 6, 'append', 6, '(%II)&', 42, 81, 0
    DB 6, 'append', 5, '([C)&', 42, 91, 0
    DB 6, 'append', 7, '([CII)&', 42, 91, 0
    DB 6, 'append', 4, '(Z)&', 42, 90, 0
    DB 6, 'append', 4, '(C)&', 42, 67, 0
    DB 6, 'append', 4, '(I)&', 42, 73, 0
    DB 6, 'append', 4, '(J)&', 42, 74, 0
    DB 6, 'append', 4, '(F)&', 42, 70, 0
    DB 6, 'append', 4, '(D)&', 42, 68, 0
    DB 6, 'append', 25, '(C)Ljava/lang/Appendable;', 42, 67, 0
    DB 6, 'append', 25, '(%)Ljava/lang/Appendable;', 42, 81, 0
    DB 6, 'append', 27, '(%II)Ljava/lang/Appendable;', 42, 81, 0
    DB 6, 'length', 3, '()I', 43, 0, 0
    DB 8, 'capacity', 3, '()I', 44, 0, 0
    DB 6, 'insert', 5, '(I!)&', 53, 76, 0
    DB 6, 'insert', 5, '(I#)&', 53, 79, 0
    DB 6, 'insert', 5, '(I%)&', 53, 81, 0
    DB 6, 'insert', 7, '(I%II)&', 53, 81, 0
    DB 6, 'insert', 6, '(I[C)&', 53, 91, 0
    DB 6, 'insert', 8, '(I[CII)&', 53, 91, 0
IF JBV_PROFILE_FULL
    DB 7, 'indexOf', 4, '(!)I', 18, 66, 0
    DB 7, 'indexOf', 5, '(!I)I', 18, 66, 0
    DB 11, 'lastIndexOf', 4, '(!)I', 18, 66, 0
    DB 11, 'lastIndexOf', 5, '(!I)I', 18, 66, 0
ENDIF
    DB 6, 'insert', 5, '(IZ)&', 53, 90, 0
    DB 6, 'insert', 5, '(IC)&', 53, 67, 0
    DB 6, 'insert', 5, '(II)&', 53, 73, 0
    DB 6, 'insert', 5, '(IJ)&', 53, 74, 0
    DB 6, 'insert', 5, '(IF)&', 53, 70, 0
    DB 6, 'insert', 5, '(ID)&', 53, 68, 0
    DB 6, 'delete', 5, '(II)&', 54, 0, 0
    DB 12, 'deleteCharAt', 4, '(I)&', 55, 0, 0
    DB 7, 'replace', 6, '(II!)&', 56, 0, 0
    DB 15, 'appendCodePoint', 4, '(I)&', 57, 0, 0
    DB 10, 'trimToSize', 3, '()V', 58, 0, 0
    DB 14, 'ensureCapacity', 4, '(I)V', 45, 0, 0
    DB 9, 'setLength', 4, '(I)V', 46, 0, 0
    DB 6, 'charAt', 4, '(I)C', 47, 0, 0
    DB 9, 'setCharAt', 5, '(IC)V', 48, 0, 0
    DB 8, 'toString', 3, '()!', 49, 0, 0
    DB 9, 'substring', 4, '(I)!', 50, 0, 0
    DB 9, 'substring', 5, '(II)!', 50, 0, 0
    DB 11, 'subSequence', 5, '(II)%', 50, 0, 0
    DB 7, 'reverse', 3, '()&', 51, 0, 0
    DB 9, 'compareTo', 4, '(&)I', 52, 0, 0
    DB 9, 'compareTo', 4, '(#)I', 52, 0, 0
    DB 0
sequence_methods LABEL BYTE
    DB 6, 'length', 3, '()I', 20, 0, 0
    DB 6, 'charAt', 4, '(I)C', 22, 0, 0
    DB 11, 'subSequence', 5, '(II)%', 27, 0, 0
    DB 8, 'toString', 3, '()!', 25, 0, 0
    DB 0
comparable_methods LABEL BYTE
    DB 9, 'compareTo', 4, '(#)I', 26, 0, 0
    DB 0
appendable_methods LABEL BYTE
    DB 6, 'append', 25, '(C)Ljava/lang/Appendable;', 42, 67, 0
    DB 6, 'append', 25, '(%)Ljava/lang/Appendable;', 42, 81, 0
    DB 6, 'append', 27, '(%II)Ljava/lang/Appendable;', 42, 81, 0
    DB 0

.code
; ---- method tables
; esi = table descriptor chars, ecx = their count, edi = out (0: measure) -> eax = the expanded
; length (esi and edi advanced)
expand:
    push ebx
    xor eax, eax
ex_char:
    test ecx, ecx
    jz ex_ret
    movzx edx, BYTE PTR [esi]
    inc esi
    dec ecx
    lea ebx, [edx-'!']                  ; ! # $ % &: the expansions (" is not one)
    cmp ebx, 6
    jae ex_plain
    cmp dl, '"'
    je ex_plain
    jb @F
    dec ebx
@@:
    mov ebx, [expansions+ebx*4]
    push ecx
    push esi
    movzx ecx, BYTE PTR [ebx]
    lea esi, [ebx+1]
    add eax, ecx
    test edi, edi
    jz @F
    rep movsb
@@:
    pop esi
    pop ecx
    jmp ex_char
ex_plain:
    inc eax
    test edi, edi
    jz ex_char
    mov [edi], dl
    inc edi
    jmp ex_char
ex_ret:
    pop ebx
    ret
; ebx = vm, edi = the class, eax = a method table -> eax status: one block, the methods then
; their expanded descriptors (freed with c->methods)
T_TABLE EQU -4
T_M     EQU -8        ; the count, then the method being filled
T_TEXT  EQU -12       ; the bytes, then the next descriptor
install:
    push ebp
    mov ebp, esp
    push eax
    push 0
    push 0
    push esi
    mov esi, eax
in_measure:
    movzx ecx, BYTE PTR [esi]
    jecxz in_measured
    lea esi, [esi+ecx+1]
    movzx ecx, BYTE PTR [esi]
    inc esi
    push edi
    xor edi, edi
    call expand
    pop edi
    add [ebp+T_TEXT], eax
    inc DWORD PTR [ebp+T_M]
    add esi, 3
    jmp in_measure
in_measured:
    imul edx, DWORD PTR [ebp+T_M], M_SIZEOF
    add edx, [ebp+T_TEXT]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [edi+C_METHODS], eax
    test eax, eax
    jz in_oom
    mov ecx, [ebp+T_M]
    mov [edi+C_METHOD_COUNT], cx
    imul edx, ecx, M_SIZEOF
    add edx, eax
    mov [ebp+T_TEXT], edx
    mov [ebp+T_M], eax
    mov esi, [ebp+T_TABLE]
in_method:
    movzx ecx, BYTE PTR [esi]
    test ecx, ecx
    jz in_ok
    mov edx, [ebp+T_M]
    inc esi
    mov [edx+M_NAME+TEXT_DATA], esi
    mov [edx+M_NAME+TEXT_SIZE], cx
    add esi, ecx
    movzx ecx, BYTE PTR [esi]
    inc esi
    push edi
    mov edi, [ebp+T_TEXT]
    mov [edx+M_DESCRIPTOR+TEXT_DATA], edi
    call expand
    mov [ebp+T_TEXT], edi
    pop edi
    mov edx, [ebp+T_M]
    mov [edx+M_DESCRIPTOR+TEXT_SIZE], ax
    movzx eax, BYTE PTR [esi+2]         ; public unless an access flag is given; abstract in interfaces
    test al, 7
    jnz @F
    or al, 1
@@:
    mov ecx, ACC_ABSTRACT
    test WORD PTR [edi+C_FLAGS], ACC_INTERFACE
    jnz @F
    mov ecx, NATIVE
@@:
    or eax, ecx
    mov [edx+M_FLAGS], ax
    movzx eax, BYTE PTR [esi]           ; op
    mov cl, 3
    test eax, eax
    jnz @F
    mov cl, 1
@@:
    mov [edx+M_INTRINSIC], cl
    mov DWORD PTR [edx+M_NATIVE_SLOTS], OFFSET library_native
    movzx ecx, BYTE PTR [esi+1]
    shl ecx, 8
    or ecx, eax
    mov [edx+M_NATIVE_USER], ecx
    IF JBV_PROFILE_FULL
    cmp al, OP_JAVA
    jne @F
    mov DWORD PTR [edx+M_NATIVE_SLOTS], OFFSET java_native
    mov [edx+M_NATIVE_USER], edx
    movzx ecx, BYTE PTR [esi+1]
    mov [edx+M_LINE_COUNT], cx
@@:
    ENDIF
    mov ecx, edx
    call @jbv_prepare_method@4
    add esi, 3
    add DWORD PTR [ebp+T_M], M_SIZEOF
    jmp in_method
in_ok:
    xor eax, eax
    jmp in_ret
in_oom:
    mov eax, S_OOM
in_ret:
    pop esi
    mov esp, ebp
    pop ebp
    ret

; ---- classes
@jbv_library_id@8 PROC SYSCALL      ; name on the stack -> its built-in id, or 0
    push esi
    push edi
    mov edx, OFFSET names
    mov eax, B_OBJECT
li_name:
    movzx ecx, BYTE PTR [edx]
    jecxz li_none
    cmp cx, WORD PTR [esp+16]
    jne li_next
    mov esi, [esp+12]
    lea edi, [edx+1]
    push ecx
    repe cmpsb
    pop ecx
    je li_ret
li_next:
    lea edx, [edx+ecx+1]
    inc eax
    jmp li_name
li_none:
    xor eax, eax
li_ret:
    pop edi
    pop esi
    ret 8
@jbv_library_id@8 ENDP
; ecx = an index, edx = a counted list -> edx = its entry
counted_entry:
    jecxz @F
    push eax
    movzx eax, BYTE PTR [edx]
    lea edx, [edx+eax+1]
    pop eax
    dec ecx
    jmp counted_entry
@@:
    ret
; ebx = vm, eax = a counted name, edx = out -> eax status
resolve_counted:
    movzx ecx, BYTE PTR [eax]
    push ecx
    inc eax
    push eax
    mov ecx, ebx
    call @jbv_resolve_class@16
    ret
; ebx = vm, al = a primitive code -> eax status, edx = its class (made once)
primitive_class:
    push edi
    mov edi, OFFSET primitive_codes
    mov ecx, 9
    repne scasb
    jne pc_bad
    sub edi, OFFSET primitive_codes+1
    mov edx, [ebx+VM_CLASSES]
pc_find:
    test edx, edx
    jz pc_new
    cmp [edx+C_PRIMITIVE], al
    je pc_ok
    mov edx, [edx+C_NEXT]
    jmp pc_find
pc_new:
    push eax
    mov edx, C_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    mov ecx, eax
    pop eax
    test ecx, ecx
    jz pc_oom
    mov [ecx+C_PRIMITIVE], al
    mov WORD PTR [ecx+C_FLAGS], 1 or 10h or ACC_ABSTRACT
    mov BYTE PTR [ecx+C_INIT_STATE], 2
    mov BYTE PTR [ecx+C_LINK_STATE], 2
    mov eax, [ebx+VM_CLASSES]
    mov [ecx+C_NEXT], eax
    mov [ebx+VM_CLASSES], ecx
    mov edx, OFFSET primitive_names
    xchg ecx, edi
    call counted_entry
    movzx eax, BYTE PTR [edx]
    inc edx
    mov [edi+C_NAME+TEXT_DATA], edx
    mov [edi+C_NAME+TEXT_SIZE], ax
    mov edx, edi
pc_ok:
    xor eax, eax
    pop edi
    ret
pc_bad:
    mov eax, S_BAD_CLASS
    pop edi
    ret
pc_oom:
    mov eax, S_OOM
    pop edi
    ret
@jbv_mirror@12 PROC SYSCALL         ; ecx vm, edx type, [esp+4] out: its Class object (made once)
    push ebx
    push esi
    mov ebx, ecx
    mov esi, edx
    cmp DWORD PTR [esi+C_MIRROR], 0
    jne mi_done
    push 0
    mov edx, esp
    push 15
    push OFFSET n_class+1                ; java/lang/Class
    mov ecx, ebx
    call @jbv_resolve_class@16
    pop edx
    test eax, eax
    jnz mi_ret
    lea eax, [esi+C_MIRROR]
    push eax
    push 0
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz mi_ret
    push 0
    push esp
    mov edx, [esi+C_MIRROR]
    mov ecx, ebx
    call @jbv_object@12
    pop eax
    mov [eax+DATA0], esi
    mov DWORD PTR [eax+DATA0+4], 0
mi_done:
    mov eax, [esi+C_MIRROR]
    mov ecx, [esp+12]
    mov [ecx], eax
    xor eax, eax
mi_ret:
    pop esi
    pop ebx
    ret 4
@jbv_mirror@12 ENDP
@jbv_primitive_mirror@12 PROC SYSCALL ; ecx vm, dl code, [esp+4] out
    push ebx
    mov ebx, ecx
    mov eax, edx
    call primitive_class
    test eax, eax
    jnz @F
    push DWORD PTR [esp+8]
    mov ecx, ebx
    call @jbv_mirror@12
@@:
    pop ebx
    ret 4
@jbv_primitive_mirror@12 ENDP
@jbv_library_initialize@8 PROC SYSCALL ; ecx vm, edx type: a wrapper's TYPE
    push ebx
    push esi
    mov ebx, ecx
    mov esi, edx
    xor eax, eax
    movzx ecx, BYTE PTR [esi+C_BUILTIN]
    sub ecx, B_BOOLEAN
    jb @F
    mov al, [primitive_codes+ecx]
    call primitive_class
    test eax, eax
    jnz @F
    mov eax, [esi+C_FIELDS]
    add eax, FIELD_VALUE
    push eax
    mov ecx, ebx
    call @jbv_mirror@12
@@:
    pop esi
    pop ebx
    ret
@jbv_library_initialize@8 ENDP
@jbv_literal@16 PROC SYSCALL        ; ecx vm, edx owner, [esp+4] index, [esp+8] out
    push ebx
    push esi
    mov ebx, ecx
    movzx eax, WORD PTR [esp+12]
    imul esi, eax, CP_SIZEOF
    add esi, [edx+C_POOL]
    cmp BYTE PTR [esi+CP_TAG], 7
    jne lt_string
    push 0                              ; a class: its mirror
    push esp
    push eax
    mov ecx, ebx
    call @jbv_class_constant@16
    pop edx
    test eax, eax
    jnz lt_ret
    push DWORD PTR [esp+16]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp lt_ret
lt_string:
    mov eax, S_UNSUPPORTED
    cmp BYTE PTR [esi+CP_TAG], 8
    jne lt_ret
    cmp DWORD PTR [esi+CP_BITS], 0      ; made and interned once
    jne lt_done
    movzx eax, WORD PTR [esi+CP_A]
    imul eax, eax, CP_SIZEOF
    add eax, [edx+C_POOL]
    push 0
    mov edx, esp
    push DWORD PTR [eax+CP_TEXT+TEXT_SIZE]
    push DWORD PTR [eax+CP_TEXT+TEXT_DATA]
    mov ecx, ebx
    call @jbv_string_mutf@16
    pop edx
    test eax, eax
    jnz lt_ret
    lea eax, [esi+CP_BITS]
    push eax
    mov ecx, ebx
    call @jbv_string_intern@12
    test eax, eax
    jnz lt_ret
lt_done:
    mov eax, [esi+CP_BITS]
    mov ecx, [esp+16]
    mov [ecx], eax
    xor eax, eax
lt_ret:
    pop esi
    pop ebx
    ret 8
@jbv_literal@16 ENDP
@jbv_library_object@8 PROC SYSCALL  ; ecx vm, edx class: java/lang/Object's natives
    push ebx
    push edi
    mov ebx, ecx
    mov edi, edx
    mov edx, [edi+C_METHODS]
    call @jbv_free@8
    xor eax, eax
    mov [edi+C_METHODS], eax
    mov [edi+C_METHOD_COUNT], ax
    mov BYTE PTR [edi+C_BUILTIN], B_OBJECT
    mov eax, OFFSET object_methods
    call install
    pop edi
    pop ebx
    ret
@jbv_library_object@8 ENDP

; JbvStatus jbv_library_class(vm, name, out): a library class from the JAR, else a built-in one
L_ID     EQU -4
L_PARENT EQU -8
L_COUNT  EQU -12
L_FACES  EQU -28      ; four interfaces
@jbv_library_class@16 PROC SYSCALL  ; ecx vm, edx out, [ebp+8] name
    push ebp
    mov ebp, esp
    sub esp, 28
    push ebx
    push esi
    push edi
    mov ebx, ecx
    mov edi, edx
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call @jbv_classpath_load@16
    cmp eax, S_NOT_FOUND
    jne lc_ret
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    call @jbv_library_id@8
    mov [ebp+L_ID], eax
    test eax, eax
    mov eax, S_NOT_FOUND
    jz lc_ret
    push DWORD PTR [ebp+12]
    push DWORD PTR [ebp+8]
    mov ecx, ebx
    call @jbv_find_class@12
    test eax, eax
    jz @F
    mov [edi], eax
    xor eax, eax
    jmp lc_ret
@@:
    mov DWORD PTR [ebp+L_COUNT], 0
    mov eax, [ebp+L_ID]                 ; the superclass
    mov ecx, B_ABUILDER
    cmp eax, B_BUILDER
    je lc_parent
    mov ecx, B_OBJECT
    cmp eax, B_BOOLEAN+1
    jb lc_parent
    cmp eax, B_DOUBLE
    ja lc_parent
    cmp eax, B_CHAR
    je lc_parent
    mov ecx, B_NUMBER
lc_parent:
    dec ecx
    mov edx, OFFSET names
    call counted_entry
    mov eax, edx
    lea edx, [ebp+L_PARENT]
    call resolve_counted
    test eax, eax
    jnz lc_ret
    mov esi, [ebp+L_ID]                 ; the interfaces
    cmp esi, B_STRING
    je @F
    cmp esi, B_BUILDER
    jne lc_serializable
@@:
    mov eax, OFFSET n_sequence         ; java/lang/CharSequence
    call face
    jnz lc_ret
    mov eax, OFFSET n_serializable
    call face
    jnz lc_ret
    mov eax, OFFSET n_appendable   ; java/lang/Appendable
    cmp esi, B_STRING
    jne @F
    mov eax, OFFSET n_comparable      ; java/lang/Comparable
@@:
    call face
    jnz lc_ret
lc_serializable:
    cmp esi, B_CLASS
    je @F
    cmp esi, B_NUMBER
    je @F
    cmp esi, B_BOOLEAN
    je @F
    cmp esi, B_CHAR
    jne lc_comparable
@@:
    mov eax, OFFSET n_serializable
    call face
    jnz lc_ret
lc_comparable:
    cmp esi, B_BUILDER
    je @F
    cmp esi, B_BOOLEAN
    jb lc_reflect
    cmp esi, B_DOUBLE
    ja lc_reflect
@@:
    mov eax, OFFSET n_comparable      ; java/lang/Comparable
    call face
    jnz lc_ret
lc_reflect:
    IF JBV_PROFILE_FULL
    cmp esi, B_CLASS
    jne lc_make
    mov eax, OFFSET n_face1
    call face
    jnz lc_ret
    mov eax, OFFSET n_face2
    call face
    jnz lc_ret
    mov eax, OFFSET n_face3
    call face
    jnz lc_ret
lc_make:
    ENDIF
    mov edx, C_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz lc_oom
    push edi                            ; out
    mov edi, eax                        ; the class
    lea ecx, [esi-1]
    mov edx, OFFSET names
    call counted_entry
    movzx eax, BYTE PTR [edx]
    inc edx
    mov [edi+C_NAME+TEXT_DATA], edx
    mov [edi+C_NAME+TEXT_SIZE], ax
    mov eax, [ebp+L_PARENT]
    mov [edi+C_SUPER], eax
    mov eax, [eax+C_INSTANCE_SLOTS]
    mov [edi+C_INSTANCE_SLOTS], eax
    mov eax, esi
    mov [edi+C_BUILTIN], al
    mov ecx, 11h                        ; public final; the interfaces and abstract classes
    cmp eax, B_SEQUENCE
    jb @F
    cmp eax, B_APPENDABLE
    ja @F
    mov ecx, 1 or ACC_INTERFACE or ACC_ABSTRACT
@@:
    cmp eax, B_ABUILDER
    jne @F
    mov ecx, ACC_ABSTRACT
@@:
    cmp eax, B_NUMBER
    jne @F
    mov ecx, 1 or ACC_ABSTRACT
@@:
    mov [edi+C_FLAGS], cx
    mov BYTE PTR [edi+C_LINK_STATE], 2
    mov cl, 2
    cmp eax, B_BOOLEAN
    jb @F
    xor cl, cl
@@:
    mov [edi+C_INIT_STATE], cl
    mov ecx, [ebp+L_COUNT]
    jecxz lc_methods
    lea edx, [ecx*4]
    mov ecx, ebx
    call @jbv_alloc@8
    mov [edi+C_INTERFACES], eax
    test eax, eax
    jz lc_fail_oom
    mov ecx, [ebp+L_COUNT]
    mov [edi+C_INTERFACE_COUNT], cx
    push esi
    push edi
    lea esi, [ebp+L_FACES]
    mov edi, eax
    rep movsd
    pop edi
    pop esi
lc_methods:
    xor eax, eax
    cmp esi, B_CLASS
    jne @F
    mov DWORD PTR [edi+C_INSTANCE_SLOTS], 2
    mov eax, OFFSET class_methods
@@:
    cmp esi, B_STRING
    jne @F
    mov DWORD PTR [edi+C_INSTANCE_SLOTS], 1
    mov eax, OFFSET string_methods
@@:
    cmp esi, B_BUILDER
    jne @F
    mov eax, OFFSET builder_methods
@@:
    cmp esi, B_ABUILDER
    jne @F
    mov DWORD PTR [edi+C_INSTANCE_SLOTS], 2
@@:
    cmp esi, B_SEQUENCE
    jne @F
    mov eax, OFFSET sequence_methods
@@:
    cmp esi, B_COMPARABLE
    jne @F
    mov eax, OFFSET comparable_methods
@@:
    cmp esi, B_APPENDABLE
    jne @F
    mov eax, OFFSET appendable_methods
@@:
    test eax, eax
    jz lc_fields
    call install
    test eax, eax
    jnz lc_fail
lc_fields:                              ; String/AbstractStringBuilder/Class "value"; the wrappers' TYPE
    cmp esi, B_STRING
    je @F
    cmp esi, B_ABUILDER
    je @F
    cmp esi, B_CLASS
    je @F
    cmp esi, B_BOOLEAN
    jb lc_link
@@:
    mov edx, FIELD_SIZEOF
    mov ecx, ebx
    call @jbv_alloc@8
    mov [edi+C_FIELDS], eax
    test eax, eax
    jz lc_fail_oom
    mov WORD PTR [edi+C_FIELD_COUNT], 1
    cmp esi, B_BOOLEAN
    jb @F
    mov DWORD PTR [eax+FIELD_NAME+TEXT_DATA], OFFSET s_type
    mov WORD PTR [eax+FIELD_NAME+TEXT_SIZE], 4
    mov DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA], OFFSET x_class+1
    mov WORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE], 17
    mov WORD PTR [eax+FIELD_FLAGS], 1 or ACC_STATIC or 10h
    jmp lc_link
@@:
    mov DWORD PTR [eax+FIELD_NAME+TEXT_DATA], OFFSET s_value
    mov WORD PTR [eax+FIELD_NAME+TEXT_SIZE], 5
    mov WORD PTR [eax+FIELD_FLAGS], 2
    mov DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA], OFFSET s_chars
    mov WORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE], 2
    cmp esi, B_CLASS
    jne lc_link
    mov DWORD PTR [eax+FIELD_DESCRIPTOR+TEXT_DATA], OFFSET s_long
    mov WORD PTR [eax+FIELD_DESCRIPTOR+TEXT_SIZE], 1
lc_link:
    mov eax, [ebx+VM_CLASSES]
    mov [edi+C_NEXT], eax
    mov [ebx+VM_CLASSES], edi
    pop eax
    mov [eax], edi
    xor eax, eax
    jmp lc_ret
lc_fail_oom:
    mov eax, S_OOM
lc_fail:
    push eax
    mov edx, edi
    mov ecx, ebx
    call @jbv_free_class@8
    pop eax
    pop ecx
    jmp lc_ret
lc_oom:
    mov eax, S_OOM
lc_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret 8
@jbv_library_class@16 ENDP
; eax = a counted interface name: resolved into the next L_FACES slot -> eax status, ZF = ok
face:
    mov ecx, [ebp+L_COUNT]
    lea edx, [ebp+L_FACES+ecx*4]
    inc DWORD PTR [ebp+L_COUNT]
    call resolve_counted
    test eax, eax
    ret

; ---- natives of Object and Class (text ops go to jbv_text_native)
; ebx = vm, esi = class, eax = prefix ("class "/"interface " unless primitive), edi = &out -> eax
N_PREFIX EQU -4
N_N      EQU -8
N_REF    EQU -12
N_DATA   EQU -16
N_VIEW   EQU -24
class_name_string:
    push ebp
    mov ebp, esp
    sub esp, 24
    xor ecx, ecx
    test eax, eax
    jz @F
    cmp BYTE PTR [esi+C_PRIMITIVE], 0
    jne @F
    mov ecx, 6
    mov edx, OFFSET s_class_
    test WORD PTR [esi+C_FLAGS], ACC_INTERFACE
    jz @F
    mov ecx, 10
    mov edx, OFFSET s_interface
@@:
    mov [ebp+N_PREFIX], edx
    mov [ebp+N_N], ecx
    push DWORD PTR [esi+C_NAME+TEXT_SIZE]
    push DWORD PTR [esi+C_NAME+TEXT_DATA]
    lea edx, [ebp+N_REF]
    mov ecx, ebx
    call @jbv_string_mutf@16
    test eax, eax
    jnz cn_ret
    call cn_view
    mov ecx, [ebp+N_VIEW+4]             ; '/' as '.'
    mov edx, [ebp+N_VIEW]
    jecxz cn_dotted
@@:
    cmp WORD PTR [edx], '/'
    jne cn_char
    mov WORD PTR [edx], '.'
cn_char:
    add edx, 2
    loop @B
cn_dotted:
    mov eax, [ebp+N_REF]
    cmp DWORD PTR [ebp+N_N], 0
    je cn_store
    push eax
    push ebx
    call jbv_retain
    add esp, 8
    lea eax, [ebp+N_DATA]
    push eax
    push edi
    mov edx, [ebp+N_N]
    add edx, [ebp+N_VIEW+4]
    mov ecx, ebx
    call @jbv_string_alloc@16
    test eax, eax
    jnz cn_release
    call cn_view                        ; the allocation may have moved it
    push esi
    push edi
    mov edi, [ebp+N_DATA]
    mov esi, [ebp+N_PREFIX]
    mov ecx, [ebp+N_N]
    xor eax, eax
@@:
    lodsb
    stosw
    loop @B
    mov esi, [ebp+N_VIEW]
    mov ecx, [ebp+N_VIEW+4]
    rep movsw
    pop edi
    pop esi
    xor eax, eax
cn_release:
    push eax
    push DWORD PTR [ebp+N_REF]
    push ebx
    call jbv_release
    add esp, 8
    pop eax
    jmp cn_ret
cn_store:
    mov [edi], eax
    xor eax, eax
cn_ret:
    mov esp, ebp
    pop ebp
    ret
cn_view:
    lea eax, [ebp+N_VIEW]
    push eax
    mov edx, [ebp+N_REF]
    mov ecx, ebx
    call @jbv_string_view@12
    ret

; JbvStatus JBV_CALL library_native(vm, user = op | kind << 8, a, count, out)
Q_OBJ    EQU -4
Q_REF    EQU -8
Q_OWNER  EQU -12
Q_TYPE   EQU -16
Q_ID     EQU -24      ; JbvMethodId {owner, method}
Q_HASH   EQU -32
Q_DIGITS EQU -48      ; eight UTF-16 digits
Q_N      EQU -52
Q_NAME   EQU -56
Q_VIEW   EQU -64
Q_DATA   EQU -68
library_native PROC
    push ebp
    mov ebp, esp
    sub esp, 68
    push ebx
    push esi
    push edi
    mov ebx, [ebp+8]
    mov esi, [ebp+16]
    mov eax, [ebp+12]
    movzx edi, al
    cmp edi, OP_TEXT_OPS
    jb @F
    push DWORD PTR [ebp+24]
    movzx ecx, WORD PTR [ebp+20]
    push ecx
    push esi
    movzx ecx, ah
    push ecx
    mov edx, edi
    mov ecx, ebx
    call @jbv_text_native@24
    jmp ln_ret
@@:
    IF JBV_PROFILE_FULL
    cmp edi, OP_REFLECT
    jne @F
    push DWORD PTR [ebp+24]
    push esi
    mov edx, [ebp+12]
    shr edx, 8
    mov ecx, ebx
    call @jbv_reflect_class@16
    jmp ln_ret
@@:
    ENDIF
    lea eax, [ebp+Q_OBJ]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz ln_ret
    mov ecx, [ebp+24]
    mov [ecx], eax
    mov [ecx+4], eax
    mov DWORD PTR [ebp+Q_REF], 0
    cmp edi, 17
    jae ln_unsupported
    cmp edi, 7                          ; the Class ops: the represented class
    jb @F
    mov eax, [ebp+Q_OBJ]
    mov edx, [eax+DATA0]
    mov eax, S_BAD_REF
    test edx, edx
    jz ln_ret
@@:
    jmp DWORD PTR [ln_ops+edi*4]
ln_init:
    xor eax, eax
    jmp ln_ret
ln_notify:
    push 0
    push DWORD PTR [esi]
    xor edx, edx
    mov ecx, ebx
    call @jbv_monitor@16
    jmp ln_ret
ln_equals:
    mov eax, [esi]
    cmp eax, [esi+4]
    sete al
    movzx eax, al
ln_put:                                 ; eax = the int result
    mov ecx, [ebp+24]
    mov [ecx], eax
    xor eax, eax
    jmp ln_ret
ln_hash:
    mov eax, [esi]
    jmp ln_put
ln_clone:
    push 19
    push OFFSET n_cloneable
    mov ecx, ebx
    call @jbv_find_class@12
    mov edx, eax
    mov ecx, [ebp+Q_OBJ]
    mov ecx, [ecx]
    call @jbv_assignable@8
    test eax, eax
    jnz @F
    push S_EXCEPTION
    push 0
    mov edx, OFFSET n_clone_error
    mov ecx, ebx
    call @jbv_throw_named@16
    jmp ln_ret
@@:
    mov eax, [ebp+Q_OBJ]
    mov edx, [eax]
    xor ecx, ecx
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    je @F
    mov ecx, [eax-4]
@@:
    lea eax, [ebp+Q_REF]
    push eax
    push ecx
    mov ecx, ebx
    call @jbv_new@16
    test eax, eax
    jnz ln_ret
    lea eax, [ebp+Q_OBJ]
    push eax
    mov edx, [esi]
    mov ecx, ebx
    call @jbv_object@12
    push 0
    push esp
    mov edx, [ebp+Q_REF]
    mov ecx, ebx
    call @jbv_object@12
    pop edi                             ; the copy
    mov ecx, [ebp+Q_OBJ]
    call @jbv_object_bytes@4
    mov ecx, eax
    mov esi, [ebp+Q_OBJ]
    add esi, DATA0
    add edi, DATA0
    rep movsb
    xor eax, eax
    jmp ln_ref
ln_class:
    lea eax, [ebp+Q_REF]
    push eax
    mov edx, [ebp+Q_OBJ]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_mirror@12
    jmp ln_ref
ln_text:                                ; getClass().getName() + "@" + hex(hashCode())
    mov eax, [ebp+Q_OBJ]
    mov eax, [eax]
    mov [ebp+Q_OWNER], eax
    mov [ebp+Q_TYPE], eax
    push 3
    push OFFSET s_int_desc
    push 8
    push OFFSET s_hashcode
    lea ecx, [ebp+Q_OWNER]
    call @jbv_lookup_method@20
    test eax, eax
    jnz @F
    mov eax, S_NOT_FOUND
    jmp ln_ret
@@:
    mov [ebp+Q_ID+4], eax
    mov eax, [ebp+Q_OWNER]
    mov [ebp+Q_ID], eax
    lea eax, [ebp+Q_HASH]
    push eax
    push 1
    push esi
    lea eax, [ebp+Q_ID]
    push eax
    push ebx
    call jbv_invoke                     ; Java code: the object is stale after this
    add esp, 20
    test eax, eax
    jnz ln_ret
    lea eax, [ebp+Q_DIGITS]
    push eax
    push 0
    push DWORD PTR [ebp+Q_HASH]
    mov edx, 16
    xor ecx, ecx
    call @jbv_integer_text@20
    mov [ebp+Q_N], eax
    mov eax, [ebp+Q_TYPE]
    push DWORD PTR [eax+C_NAME+TEXT_SIZE]
    push DWORD PTR [eax+C_NAME+TEXT_DATA]
    lea edx, [ebp+Q_NAME]
    mov ecx, ebx
    call @jbv_string_mutf@16
    test eax, eax
    jnz ln_ret
    push DWORD PTR [ebp+Q_NAME]
    push ebx
    call jbv_retain
    add esp, 8
    call ln_view
    lea eax, [ebp+Q_DATA]
    push eax
    lea eax, [ebp+Q_REF]
    push eax
    mov edx, [ebp+Q_VIEW+4]
    add edx, [ebp+Q_N]
    inc edx
    mov ecx, ebx
    call @jbv_string_alloc@16
    mov esi, eax                        ; the status
    call ln_view
    test esi, esi
    jnz ln_text_done
    mov edi, [ebp+Q_DATA]
    mov edx, [ebp+Q_VIEW]
    mov ecx, [ebp+Q_VIEW+4]
    jecxz ln_at
@@:
    mov ax, [edx]
    add edx, 2
    cmp ax, '/'
    jne ln_char
    mov ax, '.'
ln_char:
    stosw
    loop @B
ln_at:
    mov ax, '@'
    stosw
    push esi
    lea esi, [ebp+Q_DIGITS]
    mov ecx, [ebp+Q_N]
    rep movsw
    pop esi
ln_text_done:
    push DWORD PTR [ebp+Q_NAME]
    push ebx
    call jbv_release
    add esp, 8
    mov eax, esi
    jmp ln_ref
ln_view:
    lea eax, [ebp+Q_VIEW]
    push eax
    mov edx, [ebp+Q_NAME]
    mov ecx, ebx
    call @jbv_string_view@12
    ret
ln_name:                                ; edx = the class from here on
    mov esi, edx
    xor eax, eax
    cmp edi, 16                         ; toString: "class "/"interface " first
    sete al
    lea edi, [ebp+Q_REF]
    call class_name_string
    jmp ln_ref
ln_array:
    cmp BYTE PTR [edx+C_ARRAY_KIND], 0
    jmp ln_bool
ln_primitive:
    cmp BYTE PTR [edx+C_PRIMITIVE], 0
    jmp ln_bool
ln_interface:
    test WORD PTR [edx+C_FLAGS], ACC_INTERFACE
ln_bool:
    setne al
    movzx eax, al
    jmp ln_put
ln_super:
    xor eax, eax
    test WORD PTR [edx+C_FLAGS], ACC_INTERFACE
    jnz ln_ret
    mov edx, [edx+C_SUPER]
    test edx, edx
    jz ln_ret
    jmp ln_mirror
ln_component:
    xor eax, eax
    mov al, [edx+C_ARRAY_KIND]
    test al, al
    jz ln_ret
    mov ecx, [edx+C_COMPONENT]
    mov edx, ecx
    test ecx, ecx
    jnz ln_mirror
    call primitive_class
    test eax, eax
    jnz ln_ret
ln_mirror:
    lea eax, [ebp+Q_REF]
    push eax
    mov ecx, ebx
    call @jbv_mirror@12
    jmp ln_ref
ln_assign:
    push edx
    push 0
    push esp
    mov edx, [esi+4]
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    pop edx
    test eax, eax
    jnz ln_ret
    mov ecx, [ecx+DATA0]
    mov eax, S_BAD_REF
    test ecx, ecx
    jz ln_ret
    call @jbv_assignable@8
    jmp ln_put
ln_instance:                            ; isInstance and cast
    xor eax, eax
    cmp DWORD PTR [esi+4], 0
    je ln_ret
    push edx
    push 0
    push esp
    mov edx, [esi+4]
    mov ecx, ebx
    call @jbv_object@12
    pop ecx
    pop edx
    test eax, eax
    jnz ln_ret
    mov ecx, [ecx]
    call @jbv_assignable@8
    cmp edi, 14
    je ln_put
    test eax, eax
    mov eax, S_CAST
    jz ln_ret
    mov eax, [esi+4]
    jmp ln_put
ln_unsupported:
    mov eax, S_UNSUPPORTED
    jmp ln_ret
ln_ref:                                 ; eax status, [Q_REF] the result
    test eax, eax
    jnz ln_ret
    mov ecx, [ebp+24]
    mov edx, [ebp+Q_REF]
    mov [ecx], edx
ln_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
library_native ENDP
.const
ALIGN 4
ln_ops DD ln_init, ln_equals, ln_hash, ln_class, ln_text, ln_notify, ln_clone
    DD ln_name, ln_array, ln_primitive, ln_interface, ln_super, ln_component, ln_assign
    DD ln_instance, ln_instance, ln_name
.code

IF JBV_PROFILE_FULL
; JbvStatus JBV_CALL java_native(vm, method, a, count, out): a member written in Java, a static
; method of jbv.runtime.Strings taking the receiver first (constructors: a static "init" whose
; result's fields are copied into this). The helper is cached in the native's `lines`.
J_HELPER EQU -4
J_TEXT   EQU -8
J_SELF   EQU -12
J_MADE   EQU -16
java_native PROC
    push ebp
    mov ebp, esp
    sub esp, 16
    push ebx
    push esi
    push edi
    mov ebx, [ebp+8]
    mov esi, [ebp+12]
    push 19
    push OFFSET n_strings
    lea edx, [ebp+J_HELPER]
    mov ecx, ebx
    call @jbv_resolve_class@16
    test eax, eax
    jnz jn_ret
    mov edx, [ebp+J_HELPER]
    mov ecx, ebx
    call @jbv_initialize@8
    test eax, eax
    jnz jn_ret
    mov edi, [esi+M_LINES]
    test edi, edi
    jnz jn_call
    movzx edx, WORD PTR [esi+M_DESCRIPTOR+TEXT_SIZE]
    mov eax, S_LINKAGE
    cmp edx, 0FF00h
    ja jn_ret
    add edx, 26
    mov ecx, ebx
    call @jbv_alloc@8
    test eax, eax
    jz jn_oom
    mov [ebp+J_TEXT], eax
    mov edi, eax
    mov BYTE PTR [edi], '('
    inc edi
    push esi
    mov edx, esi                        ; edx = the method
    mov eax, [edx+M_NAME+TEXT_DATA]
    cmp BYTE PTR [eax], '<'
    je jn_parameters
    test WORD PTR [edx+M_FLAGS], ACC_STATIC
    jnz jn_parameters
    mov eax, OFFSET x_string            ; the receiver: String, or StringBuilder
    cmp WORD PTR [edx+M_LINE_COUNT], 'B'
    jne @F
    mov eax, OFFSET x_builder
@@:
    movzx ecx, BYTE PTR [eax]
    lea esi, [eax+1]
    rep movsb
jn_parameters:
    mov esi, [edx+M_DESCRIPTOR+TEXT_DATA]
    inc esi
@@:
    lodsb
    cmp al, ')'
    je @F
    stosb
    jmp @B
@@:
    mov eax, [edx+M_NAME+TEXT_DATA]
    cmp BYTE PTR [eax], '<'
    jne jn_result
    mov al, ')'                         ; init returns the new String
    stosb
    mov esi, OFFSET x_string+1
    mov ecx, 18
    rep movsb
    jmp jn_described
jn_result:
    dec esi
    movzx ecx, WORD PTR [edx+M_DESCRIPTOR+TEXT_SIZE]
    add ecx, [edx+M_DESCRIPTOR+TEXT_DATA]
    sub ecx, esi
    rep movsb
jn_described:
    pop esi
    sub edi, [ebp+J_TEXT]
    push edi                            ; the helper's descriptor
    push DWORD PTR [ebp+J_TEXT]
    mov eax, [esi+M_NAME+TEXT_DATA]
    cmp BYTE PTR [eax], '<'
    jne @F
    push 4
    push OFFSET s_init_name
    jmp jn_find
@@:
    push DWORD PTR [esi+M_NAME+TEXT_SIZE]
    push DWORD PTR [esi+M_NAME+TEXT_DATA]
jn_find:
    mov ecx, [ebp+J_HELPER]
    call @jbv_find_method@20
    mov edi, eax
    mov edx, [ebp+J_TEXT]
    mov ecx, ebx
    call @jbv_free@8
    mov eax, S_LINKAGE
    test edi, edi
    jz jn_ret
    test WORD PTR [edi+M_FLAGS], ACC_STATIC
    jz jn_ret
    mov [esi+M_LINES], edi
jn_call:
    movzx eax, WORD PTR [ebp+20]
    mov ecx, [ebp+16]
    mov edx, [esi+M_NAME+TEXT_DATA]
    cmp BYTE PTR [edx], '<'
    jne @F
    dec eax                             ; init: without the receiver
    add ecx, 4
@@:
    push DWORD PTR [ebp+24]
    push eax
    push 0
    push ecx
    push edi
    mov edx, [ebp+J_HELPER]
    mov ecx, ebx
    call @jbv_execute@28
    mov edx, [esi+M_NAME+TEXT_DATA]
    cmp BYTE PTR [edx], '<'
    jne jn_ret
    test eax, eax                       ; copy the made String's fields into this
    jnz jn_cleared
    lea eax, [ebp+J_SELF]
    push eax
    mov edx, [ebp+16]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz jn_cleared
    lea eax, [ebp+J_MADE]
    push eax
    mov edx, [ebp+24]
    mov edx, [edx]
    mov ecx, ebx
    call @jbv_object@12
    test eax, eax
    jnz jn_cleared
    xor esi, esi
@@:
    mov edx, [ebp+J_SELF]
    mov ecx, [edx]
    cmp esi, [ecx+C_INSTANCE_SLOTS]
    jae jn_copied
    mov eax, [ebp+J_MADE]
    mov eax, [eax+esi*4+DATA0]
    mov [edx+esi*4+DATA0], eax
    push eax
    mov ecx, ebx
    call @jbv_barrier_checked@12
    inc esi
    jmp @B
jn_copied:
    xor eax, eax
jn_cleared:
    mov ecx, [ebp+24]
    mov DWORD PTR [ecx], 0
    mov DWORD PTR [ecx+4], 0
    jmp jn_ret
jn_oom:
    mov eax, S_OOM
jn_ret:
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
java_native ENDP
ENDIF
END

#include "library.h"
#include "classpath.h"
#if !defined(_M_IX86)   /* library_x86.asm; this is the reference */
#define L "java/lang/"
/* In the method tables the common reference types are one character each; install_methods
 * expands them (STR..SB below, in order of the expansions table). */
#define STR "!"
#define OBJ "#"
#define CLS "$"
#define SEQ "%"
#define SB "&"
static const char *const expansions[] = {"Ljava/lang/String;", "Ljava/lang/Object;", "Ljava/lang/Class;", "Ljava/lang/CharSequence;", "Ljava/lang/StringBuilder;"};
/* Writes the expansion of a table descriptor to out (if not 0); returns its length. */
static uint32_t expand(const char *d, char *out) {
    uint32_t n = 0;
    for (; *d; ++d) {
        const char *x = (uint8_t)(*d - '!') < 6 && *d != '"' ? expansions[*d - '!' - (*d > '"')] : 0;
        if (!x) { if (out) out[n] = *d; ++n; continue; }
        for (; *x; ++x) { if (out) out[n] = *x; ++n; }
    }
    return n;
}
typedef struct MethodSpec {
    const char *name, *descriptor;
    uint8_t op, kind, flags;
} MethodSpec;
#define M(n,d,o) {n,d,o,0,0}
#define K(n,d,o,k) {n,d,o,k,0}
#define V(d,k) {"valueOf",d,S_VALUE,k,JBV_STATIC}
#define A(d,k) K("append",d,A_APPEND,k)
#define J(n,d) {n,d,O_JAVA,0,0}
#define JB(n,d) {n,d,O_JAVA,'B',0} /* receiver is a StringBuilder */
static const MethodSpec object_methods[] = {
    M("<init>","()V",O_INIT), M("equals","(" OBJ ")Z",O_EQUALS),
    M("hashCode","()I",O_HASH), M("getClass","()" CLS,O_CLASS), M("toString","()" STR,O_TEXT),
    M("notify","()V",O_NOTIFY), M("notifyAll","()V",O_NOTIFY),
    {"clone","()" OBJ,O_CLONE,0,4}
};
static const MethodSpec class_methods[] = {
    M("getName","()" STR,C_NAME), M("isArray","()Z",C_ARRAY),
    M("isPrimitive","()Z",C_PRIMITIVE), M("isInterface","()Z",C_INTERFACE),
    M("getSuperclass","()" CLS,C_SUPER), M("getComponentType","()" CLS,C_COMPONENT),
    M("isAssignableFrom","(" CLS ")Z",C_ASSIGN), M("isInstance","(" OBJ ")Z",C_INSTANCE),
    M("cast","(" OBJ ")" OBJ,C_CAST), M("toString","()" STR,C_TEXT)
#if JBV_PROFILE_FULL
    ,K("getModifiers","()I",C_REFLECT,0), K("getInterfaces","()[" CLS,C_REFLECT,1),
    {"forName","(" STR ")" CLS,C_REFLECT,2,JBV_STATIC},
    {"forName","(" STR "ZLjava/lang/ClassLoader;)" CLS,C_REFLECT,3,JBV_STATIC},
    K("getDeclaredMethods","()[Ljava/lang/reflect/Method;",C_REFLECT,4),
    K("getMethods","()[Ljava/lang/reflect/Method;",C_REFLECT,5),
    K("getDeclaredMethod","(" STR "[" CLS ")Ljava/lang/reflect/Method;",C_REFLECT,6),
    K("getMethod","(" STR "[" CLS ")Ljava/lang/reflect/Method;",C_REFLECT,7),
    K("getDeclaredFields","()[Ljava/lang/reflect/Field;",C_REFLECT,8),
    K("getFields","()[Ljava/lang/reflect/Field;",C_REFLECT,9),
    K("getDeclaredField","(" STR ")Ljava/lang/reflect/Field;",C_REFLECT,10),
    K("getField","(" STR ")Ljava/lang/reflect/Field;",C_REFLECT,11),
    K("getDeclaredConstructors","()[Ljava/lang/reflect/Constructor;",C_REFLECT,12),
    K("getConstructors","()[Ljava/lang/reflect/Constructor;",C_REFLECT,13),
    K("getDeclaredConstructor","([" CLS ")Ljava/lang/reflect/Constructor;",C_REFLECT,14),
    K("getConstructor","([" CLS ")Ljava/lang/reflect/Constructor;",C_REFLECT,15),
    K("isAnnotation","()Z",C_REFLECT,16), K("isSynthetic","()Z",C_REFLECT,17),
    K("isEnum","()Z",C_REFLECT,18), K("getClassLoader","()Ljava/lang/ClassLoader;",C_REFLECT,19), K("getDeclaredAnnotations","()[Ljava/lang/annotation/Annotation;",C_REFLECT,20),
    K("getGenericSuperclass","()Ljava/lang/reflect/Type;",C_REFLECT,22), K("getGenericInterfaces","()[Ljava/lang/reflect/Type;",C_REFLECT,23),
    K("getTypeParameters","()[Ljava/lang/reflect/TypeVariable;",C_REFLECT,24), K("getTypeName","()" STR,C_REFLECT,25),
    K("getSimpleName","()" STR,C_REFLECT,26), K("getPackageName","()" STR,C_REFLECT,27), K("getEnumConstants","()[" OBJ,C_REFLECT,28),
    K("getCanonicalName","()" STR,C_REFLECT,29), K("isMemberClass","()Z",C_REFLECT,30), K("isAnonymousClass","()Z",C_REFLECT,31),
    K("isRecord","()Z",C_REFLECT,32), K("getNestHost","()" CLS,C_REFLECT,33), K("getDeclaringClass","()" CLS,C_REFLECT,34), K("getEnclosingClass","()" CLS,C_REFLECT,35)
#endif
};
static const MethodSpec string_methods[] = {
    M("<init>","()V",S_INIT), K("<init>","(" STR ")V",S_INIT,'L'),
    K("<init>","([C)V",S_INIT,'C'), K("<init>","([CII)V",S_INIT,'C'),
    M("length","()I",S_LENGTH), M("isEmpty","()Z",S_EMPTY), M("charAt","(I)C",S_CHAR),
    M("equals","(" OBJ ")Z",S_EQUALS), M("hashCode","()I",S_HASH), M("toString","()" STR,S_TEXT),
    M("compareTo","(" STR ")I",S_COMPARE), M("compareTo","(" OBJ ")I",S_COMPARE),
    M("substring","(I)" STR,S_SUBSTRING), M("substring","(II)" STR,S_SUBSTRING),
    M("subSequence","(II)" SEQ,S_SUBSTRING), M("toCharArray","()[C",S_CHARS),
    M("getChars","(II[CI)V",S_GET_CHARS), M("concat","(" STR ")" STR,S_CONCAT),
    M("intern","()" STR,S_INTERN), M("startsWith","(" STR ")Z",S_STARTS),
    M("trim","()" STR,S_TRIM), K("replace","(CC)" STR,S_REPLACE,'C'),
    M("replace","(" SEQ SEQ ")" STR,S_REPLACE), M("contains","(" SEQ ")Z",S_CONTAINS),
    M("repeat","(I)" STR,S_REPEAT),
    M("startsWith","(" STR "I)Z",S_STARTS), M("endsWith","(" STR ")Z",S_ENDS),
    K("indexOf","(I)I",S_INDEX,'I'), K("indexOf","(II)I",S_INDEX,'I'),
    K("lastIndexOf","(I)I",S_LAST_INDEX,'I'), K("lastIndexOf","(II)I",S_LAST_INDEX,'I'),
    M("indexOf","(" STR ")I",S_INDEX), M("indexOf","(" STR "I)I",S_INDEX),
    M("lastIndexOf","(" STR ")I",S_LAST_INDEX), M("lastIndexOf","(" STR "I)I",S_LAST_INDEX),
    V("(" OBJ ")" STR,'L'), V("([C)" STR,'['), V("([CII)" STR,'['),
    V("(Z)" STR,'Z'), V("(C)" STR,'C'), V("(I)" STR,'I'), V("(J)" STR,'J'),
    V("(F)" STR,'F'), V("(D)" STR,'D')
#if JBV_PROFILE_FULL
    /* Implemented in Java by jbv.runtime.Strings (receiver first, see java_native). */
    ,J("toLowerCase","()" STR), J("toUpperCase","()" STR), J("equalsIgnoreCase","(" STR ")Z"),
    J("compareToIgnoreCase","(" STR ")I"), J("regionMatches","(I" STR "II)Z"), J("regionMatches","(ZI" STR "II)Z"),
    J("split","(" STR ")[" STR), J("split","(" STR "I)[" STR), J("matches","(" STR ")Z"),
    J("replaceAll","(" STR STR ")" STR), J("replaceFirst","(" STR STR ")" STR),
    J("strip","()" STR), J("stripLeading","()" STR), J("stripTrailing","()" STR), J("isBlank","()Z"),
    J("codePointAt","(I)I"), J("codePointBefore","(I)I"), J("codePointCount","(II)I"), J("contentEquals","(" SEQ ")Z"),
    J("getBytes","()[B"), J("getBytes","(" STR ")[B"), J("getBytes","(Ljava/nio/charset/Charset;)[B"),
    J("formatted","([" OBJ ")" STR), J("indent","(I)" STR), J("chars","()Ljava/util/stream/IntStream;"), J("codePoints","()Ljava/util/stream/IntStream;"),
    J("toLowerCase","(Ljava/util/Locale;)" STR), J("toUpperCase","(Ljava/util/Locale;)" STR),
    {"format","(Ljava/util/Locale;" STR "[" OBJ ")" STR,O_JAVA,0,JBV_STATIC},
    {"join","(" SEQ "[" SEQ ")" STR,O_JAVA,0,JBV_STATIC}, {"join","(" SEQ "Ljava/lang/Iterable;)" STR,O_JAVA,0,JBV_STATIC},
    {"format","(" STR "[" OBJ ")" STR,O_JAVA,0,JBV_STATIC}, {"copyValueOf","([C)" STR,O_JAVA,0,JBV_STATIC},
    J("<init>","([B)V"), J("<init>","([BII)V"), J("<init>","([B" STR ")V"), J("<init>","([BLjava/nio/charset/Charset;)V"),
    J("<init>","([BIILjava/nio/charset/Charset;)V"), J("<init>","(" SB ")V"), J("<init>","([III)V")
#endif
};
static const MethodSpec builder_methods[] = {
    M("<init>","()V",A_INIT), K("<init>","(I)V",A_INIT,'I'),
    K("<init>","(" STR ")V",A_INIT,'L'), K("<init>","(" SEQ ")V",A_INIT,'Q'),
    A("(" STR ")" SB,'L'), A("(" OBJ ")" SB,'O'),
    A("(" SEQ ")" SB,'Q'), A("(" SEQ "II)" SB,'Q'),
    A("([C)" SB,'['), A("([CII)" SB,'['), A("(Z)" SB,'Z'), A("(C)" SB,'C'),
    A("(I)" SB,'I'), A("(J)" SB,'J'), A("(F)" SB,'F'), A("(D)" SB,'D'),
    A("(C)Ljava/lang/Appendable;",'C'), A("(" SEQ ")Ljava/lang/Appendable;",'Q'),
    A("(" SEQ "II)Ljava/lang/Appendable;",'Q'),
    M("length","()I",A_LENGTH), M("capacity","()I",A_CAPACITY),
    K("insert","(I" STR ")" SB,A_INSERT,'L'), K("insert","(I" OBJ ")" SB,A_INSERT,'O'),
    K("insert","(I" SEQ ")" SB,A_INSERT,'Q'), K("insert","(I" SEQ "II)" SB,A_INSERT,'Q'),
    K("insert","(I[C)" SB,A_INSERT,'['), K("insert","(I[CII)" SB,A_INSERT,'['),
#if JBV_PROFILE_FULL
    JB("indexOf","(" STR ")I"), JB("indexOf","(" STR "I)I"), JB("lastIndexOf","(" STR ")I"), JB("lastIndexOf","(" STR "I)I"),
#endif
    K("insert","(IZ)" SB,A_INSERT,'Z'), K("insert","(IC)" SB,A_INSERT,'C'),
    K("insert","(II)" SB,A_INSERT,'I'), K("insert","(IJ)" SB,A_INSERT,'J'),
    K("insert","(IF)" SB,A_INSERT,'F'), K("insert","(ID)" SB,A_INSERT,'D'),
    M("delete","(II)" SB,A_DELETE), M("deleteCharAt","(I)" SB,A_DELETE_CHAR),
    M("replace","(II" STR ")" SB,A_REPLACE), M("appendCodePoint","(I)" SB,A_CODEPOINT),
    M("trimToSize","()V",A_TRIM),
    M("ensureCapacity","(I)V",A_ENSURE), M("setLength","(I)V",A_SET_LENGTH),
    M("charAt","(I)C",A_CHAR), M("setCharAt","(IC)V",A_SET_CHAR),
    M("toString","()" STR,A_TEXT), M("substring","(I)" STR,A_SUBSTRING),
    M("substring","(II)" STR,A_SUBSTRING), M("subSequence","(II)" SEQ,A_SUBSTRING),
    M("reverse","()" SB,A_REVERSE), M("compareTo","(" SB ")I",A_COMPARE), M("compareTo","(" OBJ ")I",A_COMPARE)
};
static const MethodSpec sequence_methods[] = {
    M("length","()I",S_LENGTH), M("charAt","(I)C",S_CHAR),
    M("subSequence","(II)" SEQ,S_SUBSTRING), M("toString","()" STR,S_TEXT)
};
static const MethodSpec comparable_methods[] = {M("compareTo","(" OBJ ")I",S_COMPARE)};
static const MethodSpec appendable_methods[] = {
    A("(C)Ljava/lang/Appendable;",'C'), A("(" SEQ ")Ljava/lang/Appendable;",'Q'),
    A("(" SEQ "II)Ljava/lang/Appendable;",'Q')
};
static const char *const names[] = {"", L "Object", L "Class", L "String", L "StringBuilder",
    L "AbstractStringBuilder", L "Number", L "CharSequence", L "Comparable", L "Appendable",
    L "Boolean", L "Byte", L "Character", L "Short", L "Integer", L "Long", L "Float", L "Double", L "Void"};
static const char primitive_codes[] = "ZBCSIJFDV";
static const char *const primitive_names[] = {"boolean","byte","char","short","int","long","float","double","void"};
uint8_t jbv_library_id(JbvText name) {
    uint32_t id;
    for (id = B_OBJECT; id < sizeof(names)/sizeof(names[0]); ++id)
        if (jbv_text_is(name, names[id])) return (uint8_t)id;
    return 0;
}

static JbvStatus primitive_class(JbvVM *vm, uint8_t kind, JbvClass **out) {
    uint32_t i;
    JbvClass *c;
    for (i = 0; primitive_codes[i] && primitive_codes[i] != kind; ++i) {}
    if (!primitive_codes[i]) return JBV_BAD_CLASS;
    for (c = vm->classes; c && c->primitive != kind; c = c->next) {}
    if (!c) {
        c = (JbvClass *)jbv_alloc(vm, sizeof(*c));
        if (!c) return JBV_OUT_OF_MEMORY;
        c->name = jbv_text(primitive_names[i]); c->primitive = kind;
        c->flags = 1 | JBV_FINAL | JBV_ABSTRACT; c->init_state = c->link_state = 2;
        c->next = vm->classes; vm->classes = c;
    }
    *out = c; return JBV_OK;
}
JbvStatus jbv_mirror(JbvVM *vm, JbvClass *type, int32_t *out) {
    JbvClass *mirror;
    JbvObject *o = 0;
    JbvStatus status;
    if (!type->mirror) {
        status = jbv_resolve_class(vm, jbv_text(L "Class"), &mirror);
        if (status != JBV_OK) return status;
        status = jbv_new(vm, mirror, 0, &type->mirror);
        if (status != JBV_OK) return status;
        (void)jbv_object(vm, type->mirror, &o);
        jbv_put_bits(jbv_data(o), (uint64_t)(uintptr_t)type, JBV_LONG);
    }
    *out = type->mirror; return JBV_OK;
}
static JbvClass *represented(JbvObject *o) {
    return (JbvClass *)(uintptr_t)jbv_slot_bits(jbv_data(o), JBV_LONG);
}
JBV_GC static JbvStatus class_name_string(JbvVM *vm, JbvClass *c, int prefix, int32_t *out) {
    uint16_t *data;
    uint32_t i, n = 0;
    int32_t ref;
    JbvTextView name;
    const char *p = prefix && !c->primitive ? (c->flags & JBV_INTERFACE ? "interface " : "class ") : "";
    JbvStatus status;
    while (p[n]) ++n;
    status = jbv_string_mutf(vm, c->name, &ref);
    if (status != JBV_OK) return status;
    (void)jbv_string_view(vm, ref, &name);
    for (i = 0; i < name.length; ++i) if (name.data[i] == '/') name.data[i] = '.';
    if (!n) { *out = ref; return JBV_OK; }
    (void)jbv_retain(vm, ref);
    status = jbv_string_alloc(vm, n + name.length, out, &data);
    if (status != JBV_OK) { (void)jbv_release(vm, ref); return status; }
    (void)jbv_string_view(vm, ref, &name);   /* the allocation may have moved it */
    for (i = 0; i < n; ++i) data[i] = p[i];
    for (i = 0; i < name.length; ++i) data[n+i] = name.data[i];
    (void)jbv_release(vm, ref);
    return JBV_OK;
}
/* The only scalar stack buffer is the bounded eight-digit hexadecimal hash. */
JBV_GC __declspec(safebuffers)
static JbvStatus JBV_CALL library_native(JbvVM *vm, void *user, const int32_t *a, uint16_t count, uint64_t *out) {
    uint32_t packed = (uint32_t)(uintptr_t)user, op = packed & 255;
    JbvObject *o = 0, *other = 0;
    JbvClass *c, *target;
    JbvStatus status;
    int32_t ref = 0;
    if (op >= S_INIT) return jbv_text_native(vm, op, (uint8_t)(packed >> 8), a, count, out);
#if JBV_PROFILE_FULL
    if (op == C_REFLECT) return jbv_reflect_class(vm, packed >> 8, a, out);
#endif
    status = jbv_object(vm, a[0], &o);
    if (status != JBV_OK) return status;
    *out = 0;
    if (op == O_INIT) return JBV_OK;
    if (op == O_NOTIFY) return jbv_monitor(vm, 0, a[0], 0);
    if (op == O_EQUALS) { *out = a[0] == a[1]; return JBV_OK; }
    if (op == O_HASH) { *out = (uint32_t)a[0]; return JBV_OK; }
    if (op == O_CLONE) {
        size_t i, bytes;
        if (!jbv_assignable(o->type, jbv_find_class(vm, jbv_text("java/lang/Cloneable"))))
            return jbv_throw_named(vm, "java/lang/CloneNotSupportedException", 0, JBV_EXCEPTION);
        status = jbv_new(vm, o->type, o->type->array_kind ? (int32_t)jbv_length(o) : 0, &ref);
        if (status != JBV_OK) return status;
        (void)jbv_object(vm, a[0], &o); (void)jbv_object(vm, ref, &other);
        bytes = jbv_object_bytes(o);
        for (i = 0; i < bytes; ++i) ((volatile uint8_t *)(other+1))[i] = ((uint8_t *)(o+1))[i];
        *out = (uint32_t)ref; return JBV_OK;
    }
    if (op == O_CLASS) status = jbv_mirror(vm, o->type, &ref);
    else if (op == O_TEXT) {
        JbvTextView name;
        uint16_t hash[8], *data;
        int32_t name_ref;
        uint32_t n, i;
        uint64_t hash_result;
        JbvMethodId method;
        JbvClass *owner = o->type, *type = o->type;
        method.method = jbv_lookup_method(&owner, jbv_text("hashCode"), jbv_text("()I")); method.owner = owner;
        if (!method.method) return JBV_NOT_FOUND;
        status = jbv_invoke(vm, &method, a, 1, &hash_result);   /* Java code: `o` is stale after this */
        if (status != JBV_OK) return status;
        n = jbv_integer_text((uint32_t)hash_result, 0, 16, hash);
        status = jbv_string_mutf(vm, type->name, &name_ref);
        if (status != JBV_OK) return status;
        (void)jbv_retain(vm, name_ref);
        (void)jbv_string_view(vm, name_ref, &name);
        status = jbv_string_alloc(vm, name.length + 1 + n, &ref, &data);
        (void)jbv_string_view(vm, name_ref, &name);
        if (status == JBV_OK) {
            for (i = 0; i < name.length; ++i) data[i] = name.data[i] == '/' ? '.' : name.data[i];
            data[i++] = '@';
            { uint32_t j; for (j = 0; j < n; ++j) data[i + j] = hash[j]; }
        }
        (void)jbv_release(vm, name_ref);
    } else {
        c = represented(o);
        if (!c) return JBV_BAD_REFERENCE;
        switch (op) {
        case C_NAME: case C_TEXT: status = class_name_string(vm, c, op == C_TEXT, &ref); break;
        case C_ARRAY: *out = c->array_kind != 0; return JBV_OK;
        case C_PRIMITIVE: *out = c->primitive != 0; return JBV_OK;
        case C_INTERFACE: *out = (c->flags & JBV_INTERFACE) != 0; return JBV_OK;
        case C_SUPER:
            if (!c->super || (c->flags & JBV_INTERFACE)) return JBV_OK;
            status = jbv_mirror(vm, c->super, &ref); break;
        case C_COMPONENT:
            if (!c->array_kind) return JBV_OK;
            target = c->component;
            if (!target) { status = primitive_class(vm, c->array_kind, &target); if (status != JBV_OK) return status; }
            status = jbv_mirror(vm, target, &ref); break;
        case C_ASSIGN:
            status = jbv_object(vm, a[1], &other); if (status != JBV_OK) return status;
            target = represented(other); if (!target) return JBV_BAD_REFERENCE;
            *out = jbv_assignable(target, c); return JBV_OK;
        case C_INSTANCE: case C_CAST:
            if (!a[1]) return JBV_OK;
            status = jbv_object(vm, a[1], &other); if (status != JBV_OK) return status;
            *out = jbv_assignable(other->type, c);
            if (op == C_INSTANCE) return JBV_OK;
            if (!*out) return JBV_CLASS_CAST;
            ref = a[1]; break;
        default: return JBV_UNSUPPORTED_FEATURE;
        }
    }
    if (status == JBV_OK) *out = (uint32_t)ref;
    return status;
}
#if JBV_PROFILE_FULL
/* Built-in members written in Java: a static method of the same name in
 * jbv.runtime.Strings whose descriptor prepends the receiver; constructors map to
 * a static "init" returning a new instance whose fields are copied into this.
 * Native methods never use line tables, so `lines` caches the resolved helper. */
JBV_GC static JbvStatus JBV_CALL java_native(JbvVM *vm, void *user, const int32_t *a, uint16_t count, uint64_t *out) {
    JbvMethod *m = (JbvMethod *)user, *h = (JbvMethod *)(uintptr_t)m->lines;
    JbvClass *helper;
    JbvObject *self = 0, *made = 0;
    JbvStatus status = jbv_resolve_class(vm, jbv_text("jbv/runtime/Strings"), &helper);
    int init = m->name.data[0] == '<';
    uint32_t i;
    if (status == JBV_OK) status = jbv_initialize(vm, helper);
    if (status != JBV_OK) return status;
    if (!h) {
        JbvText name, descriptor;
        uint8_t *text;
        uint32_t n = 0, close;
        if (m->descriptor.size > 0xff00) return JBV_LINKAGE_ERROR;
        text = (uint8_t *)jbv_alloc(vm, (size_t)m->descriptor.size + sizeof("Ljava/lang/StringBuilder;"));
        if (!text) return JBV_OUT_OF_MEMORY;
        text[n++] = '(';
        if (!(m->flags & JBV_STATIC) && !init) { const char *receiver = expansions[m->line_count == 'B' ? 4 : 0]; while (*receiver) text[n++] = (uint8_t)*receiver++; }
        for (close = 1; m->descriptor.data[close] != ')'; ++close) text[n++] = m->descriptor.data[close];
        if (init) { text[n++] = ')'; { const char *r = expansions[0]; while (*r) text[n++] = (uint8_t)*r++; } }
        else for (i = close; i < m->descriptor.size; ++i) text[n++] = m->descriptor.data[i];
        descriptor.data = text; descriptor.size = (uint16_t)n;
        name = init ? jbv_text("init") : m->name;
        h = jbv_find_method(helper, name, descriptor);
        jbv_free(vm, text);
        if (!h || !(h->flags & JBV_STATIC)) return JBV_LINKAGE_ERROR;
        m->lines = (const uint8_t *)(uintptr_t)h;
    }
    if (!init) return jbv_execute(vm, helper, h, a, 0, count, out);
    status = jbv_execute(vm, helper, h, a + 1, 0, (uint16_t)(count - 1), out);
    if (status == JBV_OK) status = jbv_object(vm, a[0], &self);
    if (status == JBV_OK) status = jbv_object(vm, (int32_t)(uint32_t)*out, &made);
    if (status == JBV_OK) for (i = 0; i < self->type->instance_slots; ++i) { jbv_data(self)[i] = jbv_data(made)[i]; jbv_barrier_checked(vm, self, jbv_data(self)[i]); }
    *out = 0;
    return status;
}
#endif
static JbvStatus install_methods(JbvVM *vm, JbvClass *c, const MethodSpec *spec, uint32_t count) {
    uint32_t i, bytes = 0;
    char *text;
    for (i = 0; i < count; ++i) bytes += expand(spec[i].descriptor, 0);
    /* one block: the methods, then their expanded descriptors (freed with c->methods) */
    c->methods = (JbvMethod *)jbv_alloc(vm, count * sizeof(*c->methods) + bytes);
    if (!c->methods) return JBV_OUT_OF_MEMORY;
    c->method_count = (uint16_t)count;
    text = (char *)(c->methods + count);
    for (i = 0; i < count; ++i) {
        JbvMethod *m = &c->methods[i];
        m->name = jbv_text(spec[i].name);
        m->descriptor.data = (const uint8_t *)text; m->descriptor.size = (uint16_t)expand(spec[i].descriptor, text); text += m->descriptor.size;
        m->flags = (uint16_t)((spec[i].flags & 7 ? 0 : 1) | spec[i].flags | (c->flags & JBV_INTERFACE ? JBV_ABSTRACT : JBV_NATIVE));
        m->intrinsic = spec[i].op == O_INIT ? 1 : 3;
        m->native_slots = library_native; m->native_user = (void *)(uintptr_t)(spec[i].op | ((uint32_t)spec[i].kind << 8));
#if JBV_PROFILE_FULL
        if (spec[i].op == O_JAVA) { m->native_slots = java_native; m->native_user = m; m->intrinsic = 3; m->line_count = spec[i].kind; }
#endif
        jbv_prepare_method(m);
    }
    return JBV_OK;
}
#define INSTALL(a) install_methods(vm, c, a, sizeof(a)/sizeof(a[0]))
JbvStatus jbv_library_object(JbvVM *vm, JbvClass *c) {
    jbv_free(vm, c->methods); c->methods = 0; c->method_count = 0; c->builtin = B_OBJECT;
    return INSTALL(object_methods);
}
/* At most four interface writes, followed by a count-bounded copy. */
__declspec(safebuffers)
JbvStatus jbv_library_class(JbvVM *vm, JbvText name, JbvClass **out) {
    uint32_t id, i, count = 0;
    JbvClass *c, *parent, *interfaces[4];
    JbvStatus status;
    status = jbv_classpath_load(vm, name, out);
    if (status != JBV_NOT_FOUND) return status;
    id = jbv_library_id(name);
    if (!id) return JBV_NOT_FOUND;
    c = jbv_find_class(vm, name);
    if (c) { *out = c; return JBV_OK; }
    i = id == B_BUILDER ? B_ABUILDER :
        (id >= B_BYTE && id <= B_DOUBLE && id != B_CHAR) ? B_NUMBER : B_OBJECT;
    status = jbv_resolve_class(vm, jbv_text(names[i]), &parent);
    if (status != JBV_OK) return status;
    if (id == B_STRING || id == B_BUILDER) {
        status = jbv_resolve_class(vm, jbv_text(L "CharSequence"), &interfaces[count++]);
        if (status != JBV_OK) return status;
        status = jbv_resolve_class(vm, jbv_text("java/io/Serializable"), &interfaces[count++]);
        if (status != JBV_OK) return status;
        status = jbv_resolve_class(vm, jbv_text(id == B_STRING ? L "Comparable" : L "Appendable"), &interfaces[count++]);
        if (status != JBV_OK) return status;
    }
    if (id == B_CLASS || id == B_NUMBER || id == B_BOOLEAN || id == B_CHAR) {
        status = jbv_resolve_class(vm, jbv_text("java/io/Serializable"), &interfaces[count++]);
        if (status != JBV_OK) return status;
    }
    if (id == B_BUILDER || (id >= B_BOOLEAN && id <= B_DOUBLE)) {
        status = jbv_resolve_class(vm, jbv_text(L "Comparable"), &interfaces[count++]);
        if (status != JBV_OK) return status;
    }
#if JBV_PROFILE_FULL
    if (id == B_CLASS) {
        static const char *const faces[] = {"java/lang/reflect/AnnotatedElement","java/lang/reflect/GenericDeclaration","java/lang/reflect/Type"};
        for (i = 0; i < 3; ++i) {
            status = jbv_resolve_class(vm, jbv_text(faces[i]), &interfaces[count++]);
            if (status != JBV_OK) return status;
        }
    }
#endif
    c = (JbvClass *)jbv_alloc(vm, sizeof(*c));
    if (!c) return JBV_OUT_OF_MEMORY;
    c->name = jbv_text(names[id]); c->super = parent; c->builtin = (uint8_t)id;
    c->flags = 1 | JBV_FINAL;
    if (id >= B_SEQUENCE && id <= B_APPENDABLE) c->flags = 1 | JBV_INTERFACE | JBV_ABSTRACT;
    if (id == B_ABUILDER) c->flags = JBV_ABSTRACT;
    if (id == B_NUMBER) c->flags = 1 | JBV_ABSTRACT;
    c->init_state = id >= B_BOOLEAN ? 0 : 2; c->link_state = 2;
    c->instance_slots = parent->instance_slots;
    if (count) {
        c->interfaces = (JbvClass **)jbv_alloc(vm, count * sizeof(*c->interfaces));
        if (!c->interfaces) { status = JBV_OUT_OF_MEMORY; goto fail; }
        c->interface_count = (uint16_t)count;
        for (i = 0; i < count; ++i) c->interfaces[i] = interfaces[i];
    }
    switch (id) {
    case B_CLASS: status = INSTALL(class_methods); c->instance_slots = 2; break;
    case B_STRING: status = INSTALL(string_methods); c->instance_slots = 1; break;
    case B_BUILDER: status = INSTALL(builder_methods); break;
    case B_ABUILDER: c->instance_slots = 2; break;
    case B_SEQUENCE: status = INSTALL(sequence_methods); break;
    case B_COMPARABLE: status = INSTALL(comparable_methods); break;
    case B_APPENDABLE: status = INSTALL(appendable_methods); break;
    default: break;
    }
    if (status != JBV_OK) goto fail;
    if (id == B_STRING || id == B_ABUILDER || id == B_CLASS || id >= B_BOOLEAN) {
        c->fields = (JbvField *)jbv_alloc(vm, sizeof(*c->fields));
        if (!c->fields) { status = JBV_OUT_OF_MEMORY; goto fail; }
        c->field_count = 1;
        c->fields[0].name = jbv_text(id >= B_BOOLEAN ? "TYPE" : "value");
        c->fields[0].descriptor = jbv_text(id >= B_BOOLEAN ? expansions[2] : id == B_CLASS ? "J" : "[C");
        c->fields[0].flags = id >= B_BOOLEAN ? 1 | JBV_STATIC | JBV_FINAL : 0x0002;
    }
    c->next = vm->classes; vm->classes = c; *out = c; return JBV_OK;
fail:
    jbv_free_class(vm, c); return status;
}
JbvStatus jbv_library_initialize(JbvVM *vm, JbvClass *type) {
    JbvClass *primitive;
    JbvStatus status;
    if (type->builtin < B_BOOLEAN) return JBV_OK;
    status = primitive_class(vm, (uint8_t)primitive_codes[type->builtin - B_BOOLEAN], &primitive);
    if (status == JBV_OK) status = jbv_mirror(vm, primitive, &type->fields[0].value);
    return status;
}
JbvStatus jbv_primitive_mirror(JbvVM *vm, uint8_t kind, int32_t *out) {
    JbvClass *type;
    JbvStatus status = primitive_class(vm, kind, &type);
    return status == JBV_OK ? jbv_mirror(vm, type, out) : status;
}
JbvStatus jbv_literal(JbvVM *vm, JbvClass *owner, uint16_t index, int32_t *out) {
    JbvConstant *p = &owner->pool[index];
    JbvClass *type;
    JbvStatus status;
    int32_t ref;
    if (p->tag == 7) {
        status = jbv_class_constant(vm, owner, index, &type);
        return status == JBV_OK ? jbv_mirror(vm, type, out) : status;
    }
    if (p->tag != 8) return JBV_UNSUPPORTED_FEATURE;
    if (!p->bits) {
        status = jbv_string_mutf(vm, owner->pool[p->a].text, &ref);
        if (status != JBV_OK) return status;
        status = jbv_string_intern(vm, ref, &ref);
        if (status != JBV_OK) return status;
        p->bits = (uint32_t)ref;
    }
    *out = jbv_i32(p->bits); return JBV_OK;
}
#endif

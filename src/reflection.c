#include "classpath.h"

#define R "java/lang/reflect/"
typedef struct Member { JbvClass *owner; void *target; uint8_t kind; } Member;
typedef struct Members { Member *data; uint32_t size, capacity; } Members;
static const char *const member_names[] = {R "Field", R "Method", R "Constructor"};
static uint16_t flags(Member m) { return m.kind ? ((JbvMethod *)m.target)->flags & 0x1dff : ((JbvField *)m.target)->flags; }
static JbvText name(Member m) { return m.kind ? ((JbvMethod *)m.target)->name : ((JbvField *)m.target)->name; }
static JbvText descriptor(Member m) { return m.kind ? ((JbvMethod *)m.target)->descriptor : ((JbvField *)m.target)->descriptor; }
static const uint8_t *attributes(Member m) { return m.kind ? ((JbvMethod *)m.target)->attributes : ((JbvField *)m.target)->attributes; }
const uint8_t *jbv_attribute(JbvClass *owner, const uint8_t *p, const char *key) {
    uint32_t n;
    if (!p) return 0;
    n = jbv_u16(p); p += 2;
    while (n--) {
        if (jbv_text_is(owner->pool[jbv_u16(p)].text, key)) return p + 6;
        p += 6 + jbv_u32(p+2);
    }
    return 0;
}
static JbvStatus error(JbvVM *vm, const char *type) { return jbv_throw_named(vm, type, 0, JBV_EXCEPTION); }
static JbvStatus array(JbvVM *vm, const char *component, uint32_t count, int32_t *ref, JbvObject **object) {
    JbvClass *c = 0;
    JbvStatus status = jbv_resolve_class(vm, jbv_text(component), &c);
    if (status == JBV_OK) status = jbv_array_class(vm, c, 'L', &c);
    if (status == JBV_OK) status = jbv_new(vm, c, (int32_t)count, ref);
    if (status == JBV_OK) (void)jbv_object(vm, *ref, object);
    return status;
}
static JbvStatus unpack(JbvVM *vm, int32_t ref, Member *m, JbvObject **o) {
    JbvStatus status = jbv_object(vm, ref, o);
    if (status != JBV_OK) return status;
    m->owner = jbv_mirror_type(vm, jbv_data(*o)[2]);
    m->target = (void *)(uintptr_t)jbv_slot_bits(jbv_data(*o), JBV_LONG);
    m->kind = (uint8_t)jbv_data(*o)[4];
    return m->target && m->owner ? JBV_OK : JBV_BAD_ARGUMENT;
}
static JbvStatus wrap(JbvVM *vm, Member m, int32_t *out) {
    JbvClass *c = 0;
    JbvObject *o;
    int32_t owner;
    JbvStatus status = jbv_mirror(vm, m.owner, &owner);
    if (status == JBV_OK) status = jbv_resolve_class(vm, jbv_text(member_names[m.kind]), &c);
    if (status == JBV_OK) status = jbv_new(vm, c, 0, out);
    if (status == JBV_OK) {
        (void)jbv_object(vm, *out, &o);
        jbv_put_bits(jbv_data(o), (uint64_t)(uintptr_t)m.target, JBV_LONG);
        jbv_data(o)[2] = owner; jbv_data(o)[4] = m.kind;
    }
    return status;
}
static JbvStatus add(JbvVM *vm, Members *list, Member m) {
    uint32_t i;
    for (i = 0; i < list->size; ++i) {
        Member old = list->data[i];
        if (m.target == old.target) return JBV_OK;
        if (m.kind == 1 && jbv_text_eq(name(m), name(old)) && jbv_text_eq(descriptor(m), descriptor(old))) {
            if ((old.owner->flags & JBV_INTERFACE) && !(m.owner->flags & JBV_INTERFACE)) list->data[i] = m;
            else if (!((m.owner->flags & JBV_INTERFACE) && !(old.owner->flags & JBV_INTERFACE)) && jbv_assignable(m.owner, old.owner)) list->data[i] = m;
            return JBV_OK;
        }
    }
    if (list->size == list->capacity) {
        uint32_t capacity = list->capacity ? list->capacity * 2 : 8;
        Member *data = (Member *)jbv_alloc(vm, capacity * sizeof(*data));
        if (!data) return JBV_OUT_OF_MEMORY;
        for (i = 0; i < list->size; ++i) data[i] = list->data[i];
        jbv_free(vm, list->data); list->data = data; list->capacity = capacity;
    }
    list->data[list->size++] = m; return JBV_OK;
}
static JbvStatus members(JbvVM *vm, Members *list, JbvClass *c, uint8_t kind, int inherited, int root, uint32_t depth) {
    uint32_t i;
    JbvStatus status;
    Member m;
    if (depth > vm->config.max_depth) return JBV_LIMIT_EXCEEDED;
    if (c->array_kind && inherited && kind == 1) return members(vm,list,c->super,kind,1,0,depth+1);
    if (c->primitive || c->array_kind) return JBV_OK;
    m.owner = c; m.kind = kind;
    for (i = 0; i < (uint32_t)(kind ? c->method_count : c->field_count); ++i) {
        m.target = kind ? (void *)&c->methods[i] : (void *)&c->fields[i];
        if (kind && (jbv_text_is(name(m), "<clinit>") || (jbv_text_is(name(m), "<init>") != (kind == 2)))) continue;
        if (inherited && !(flags(m) & 1)) continue;
        if (!root && kind && (c->flags & JBV_INTERFACE) && (flags(m) & JBV_STATIC)) continue;
        status = add(vm, list, m); if (status != JBV_OK) return status;
    }
    if (inherited && kind != 2) {
        /* Field lookup searches interfaces before the superclass. Methods are
         * subsequently filtered by overriding, including class/default priority. */
        for (i = 0; i < c->interface_count; ++i) {
            status = members(vm, list, c->interfaces[i], kind, 1, 0, depth+1);
            if (status != JBV_OK) return status;
        }
        if (c->super && !(c->flags & JBV_INTERFACE)) return members(vm, list, c->super, kind, 1, 0, depth+1);
    }
    return JBV_OK;
}
static JbvStatus parameters_match(JbvVM *vm, JbvText d, JbvObject *params, int *match) {
    uint32_t pos = 1, i = 0, width;
    *match = 0;
    while (d.data[pos] != ')') {
        uint32_t begin = pos;
        JbvClass *c = 0; JbvText t;
        JbvStatus status;
        if (!params || i == params->length) return JBV_OK;
        (void)jbv_descriptor_type(d, &pos, &width); t.data = d.data+begin; t.size = (uint16_t)(pos-begin);
        status = jbv_type_class(vm, t, &c); if (status != JBV_OK) return status;
        if (c != jbv_mirror_type(vm, jbv_data(params)[i++])) return JBV_OK;
    }
    *match = i == (params ? params->length : 0); return JBV_OK;
}
JbvStatus jbv_reflect_class(JbvVM *vm, uint32_t op, const int32_t *a, uint64_t *out) {
    JbvClass *c = 0;
    JbvStatus status = JBV_OK;
    JbvObject *o, *params = 0;
    int32_t ref = 0;
    uint32_t i;
    JbvText text = {0,0};
    *out = 0;
    if (op == 2 || op == 3) {
        status = jbv_text_bytes(vm, a[0], &text);
        if (status != JBV_OK) return status;
        for (i = 0; i < text.size; ++i) {
            if (text.data[i] == '/') { status = JBV_NOT_FOUND; break; }
            if (text.data[i] == '.') ((uint8_t *)text.data)[i] = '/';
        }
        if (status == JBV_OK) status = jbv_resolve_class(vm, text, &c);
        jbv_free(vm, (void *)text.data);
        if (status == JBV_NOT_FOUND || status == JBV_BAD_CLASS) return error(vm, "java/lang/ClassNotFoundException");
        if (status == JBV_OK && c->primitive) return error(vm, "java/lang/ClassNotFoundException");
        if (status == JBV_OK && (op == 2 || a[1])) status = jbv_initialize(vm, c);
        if (status == JBV_OK) status = jbv_mirror(vm, c, &ref);
    } else {
        c = jbv_mirror_type(vm, a[0]); if (!c) return JBV_NULL_REFERENCE;
        if (op == 0) {
            const uint8_t *inner = jbv_attribute(c, c->attributes, "InnerClasses");
            uint16_t f = c->flags & ~0x20;
            if (c->array_kind) { JbvClass *base=c; while(base->component)base=base->component; *out=(base->flags&1)|JBV_FINAL|JBV_ABSTRACT;return JBV_OK; }
            if (inner) for (i = 0; i < jbv_u16(inner); ++i) {
                const uint8_t *p = inner+2+8*i;
                if (jbv_text_eq(c->pool[c->pool[jbv_u16(p)].a].text,c->name)) { f = jbv_u16(p+6); break; }
            }
            *out = f; return JBV_OK;
        }
        if (op == 20) { status=jbv_annotations(vm,c,jbv_attribute(c,c->attributes,"RuntimeVisibleAnnotations"),&ref);if(status==JBV_OK)*out=(uint32_t)ref;return status; }
        if (op == 19) return JBV_OK;
        if (op >= 16) { *out = op == 16 ? !!(c->flags & 0x2000) : op == 17 ? !!(c->flags & 0x1000) : !!(c->flags & 0x4000) && c->super && jbv_text_is(c->super->name,"java/lang/Enum"); return JBV_OK; }
        if (op == 1) {
            status = array(vm, "java/lang/Class", c->array_kind ? 2 : c->interface_count, &ref, &o);
            if (status != JBV_OK) return status;
            (void)jbv_retain(vm, ref);
            for (i = 0; i < (uint32_t)(c->array_kind ? 2 : c->interface_count) && status == JBV_OK; ++i) {
                JbvClass *face;
                if (c->array_kind) status=jbv_resolve_class(vm,jbv_text(i?"java/io/Serializable":"java/lang/Cloneable"),&face);
                else face=c->interfaces[i];
                if(status==JBV_OK)status=jbv_mirror(vm,face,&jbv_data(o)[i]);
            }
            (void)jbv_release(vm, ref);
        } else {
            Members list = {0,0,0};
            uint8_t kind = op < 8 ? 1 : op < 12 ? 0 : 2;
            int lookup = (op & 2) != 0, match;
            Member *found = 0;
            if (lookup) {
                if (kind != 2) { status = jbv_text_bytes(vm, a[1], &text); if (status != JBV_OK) return status; }
                if (kind && a[kind == 2 ? 1 : 2]) {
                    status = jbv_object(vm, a[kind == 2 ? 1 : 2], &params);
                    if (status != JBV_OK) goto done;
                }
            }
            status = members(vm, &list, c, kind, op & 1, 1, 0);
            if (status != JBV_OK) goto done;
            if (lookup) {
                for (i = 0; i < list.size; ++i) {
                    Member *m = &list.data[i];
                    if (kind != 2 && !jbv_text_eq(text, name(*m))) continue;
                    if (kind) { status = parameters_match(vm, descriptor(*m), params, &match); if (status != JBV_OK) goto done; if (!match) continue; }
                    if (found && kind == 1) {
                        JbvClass *old = 0, *next = 0;
                        status = jbv_type_class(vm, jbv_return_type(descriptor(*found)), &old);
                        if (status == JBV_OK) status = jbv_type_class(vm, jbv_return_type(descriptor(*m)), &next);
                        if (status != JBV_OK) goto done;
                        if (old == next || !jbv_assignable(next,old)) continue;
                    }
                    found = m;
                    if (!kind) break;
                }
                status = found ? wrap(vm, *found, &ref) : error(vm, kind ? "java/lang/NoSuchMethodException" : "java/lang/NoSuchFieldException");
            } else {
                status = array(vm, member_names[kind], list.size, &ref, &o);
                if (status != JBV_OK) goto done;
                (void)jbv_retain(vm, ref);
                for (i = 0; i < list.size && status == JBV_OK; ++i) status = wrap(vm, list.data[i], &jbv_data(o)[i]);
                (void)jbv_release(vm, ref);
            }
done:
            jbv_free(vm, list.data); jbv_free(vm, (void *)text.data);
        }
    }
    if (status == JBV_OK) *out = (uint32_t)ref; return status;
}
static JbvClass *caller(JbvVM *vm) {
    JbvFrame *f;
    for (f = vm->frames; f; f = f->previous) {
        JbvText n = f->owner->name;
        if (jbv_text_is(n,"jbv/runtime/Reflection")) continue;
        if (n.size >= 18) { n.size = 18; if (jbv_text_is(n,"java/lang/reflect/")) continue; }
        return f->owner;
    }
    return 0;
}
static JbvStatus access(JbvVM *vm, Member m, JbvObject *member, int32_t receiver, int query) {
    JbvObject *o = 0;
    JbvClass *from;
    JbvStatus status;
    if (m.kind == 2 || (flags(m) & JBV_STATIC)) {
        if (query && receiver) return JBV_BAD_ARGUMENT;
    } else {
        if (!receiver) return query ? JBV_BAD_ARGUMENT : JBV_NULL_REFERENCE;
        status = jbv_object(vm, receiver, &o); if (status != JBV_OK) return status;
        if (!jbv_assignable(o->type,m.owner)) return JBV_BAD_ARGUMENT;
    }
    if (jbv_data(member)[3]) return JBV_OK;
    from = caller(vm);
    if (!from) return flags(m) & m.owner->flags & 1 ? JBV_OK : error(vm,"java/lang/IllegalAccessException");
    status = jbv_class_access(vm, from, m.owner);
    if (status == JBV_OK) status = jbv_member_access(vm, from, m.owner, flags(m), o ? o->type : 0);
    if (status == JBV_LINKAGE_ERROR) { vm->exception = 0; return error(vm,"java/lang/IllegalAccessException"); }
    return status;
}
static JbvStatus info(JbvVM *vm, Member m, uint32_t op, int32_t *ref) {
    JbvText d = descriptor(m);
    JbvClass *c = 0;
    JbvObject *o;
    uint32_t i, pos = 1, width, count = 0;
    const uint8_t *p = 0;
    JbvStatus status;
    if (op == 4) { const uint8_t *value=jbv_attribute(m.owner,attributes(m),"AnnotationDefault");*ref=0;return value?jbv_annotation_value(vm,m.owner,&value,jbv_return_type(d),ref):JBV_OK; }
    if (op == 0) return jbv_string_mutf(vm, name(m), ref);
    if (op == 1) { status = jbv_type_class(vm, m.kind ? jbv_return_type(d) : d, &c); return status == JBV_OK ? jbv_mirror(vm,c,ref) : status; }
    if (op == 3) { p = jbv_attribute(m.owner,attributes(m),"Exceptions"); count = p ? jbv_u16(p) : 0; }
    else while (d.data[pos] != ')') { (void)jbv_descriptor_type(d,&pos,&width); ++count; }
    status = array(vm,"java/lang/Class",count,ref,&o); if (status != JBV_OK) return status;
    (void)jbv_retain(vm,*ref); pos = 1;
    for (i = 0; i < count && status == JBV_OK; ++i) {
        if (p) status = jbv_resolve_class(vm,m.owner->pool[m.owner->pool[jbv_u16(p+2+2*i)].a].text,&c);
        else { JbvText t; uint32_t begin = pos; (void)jbv_descriptor_type(d,&pos,&width); t.data=d.data+begin;t.size=(uint16_t)(pos-begin);status=jbv_type_class(vm,t,&c); }
        if (status == JBV_OK) status = jbv_mirror(vm,c,&jbv_data(o)[i]);
    }
    (void)jbv_release(vm,*ref); return status;
}
static JbvStatus convert(JbvVM *vm, int32_t value, JbvText type, uint64_t *bits) {
    JbvStatus status = jbv_from_object(vm,value,type,bits);
    return status == JBV_CLASS_CAST || status == JBV_NULL_REFERENCE ? JBV_BAD_ARGUMENT : status;
}
static JbvStatus invoke(JbvVM *vm, Member m, JbvObject *member, int32_t receiver, int32_t arguments, int32_t *out) {
    JbvMethod *method = (JbvMethod *)m.target;
    JbvObject *args = 0, *o;
    JbvText d = method->descriptor, result = jbv_return_type(d);
    JbvStatus status = access(vm,m,member,receiver,0);
    int32_t *slots = 0, created = 0;
    uint8_t *refs = 0;
    uint32_t pos = 1, used = !(method->flags & JBV_STATIC), i = 0, width;
    uint64_t bits = 0;
    if (status != JBV_OK) return status;
    if (arguments) { status = jbv_object(vm,arguments,&args); if (status != JBV_OK) return status; }
    if (m.kind == 2 && (m.owner->flags & 0x4000)) return JBV_BAD_ARGUMENT;
    if (m.kind == 2 && (m.owner->flags & (JBV_ABSTRACT|JBV_INTERFACE))) return error(vm,"java/lang/InstantiationException");
    slots = (int32_t *)jbv_alloc(vm,(method->argument_slots+1)*sizeof(*slots));
    refs = (uint8_t *)jbv_alloc(vm,method->argument_slots+1);
    if (!slots || !refs) { status=JBV_OUT_OF_MEMORY;goto done; }
    if (used) { slots[0]=receiver;refs[0]=1; }
    while (d.data[pos] != ')') {
        JbvText t; uint32_t begin = pos;
        if (!args || i == args->length) { status=JBV_BAD_ARGUMENT;goto done; }
        (void)jbv_descriptor_type(d,&pos,&width);t.data=d.data+begin;t.size=(uint16_t)(pos-begin);
        status=convert(vm,jbv_data(args)[i++],t,&bits);if(status!=JBV_OK)goto done;
        refs[used]=(uint8_t)jbv_reference_type(t);jbv_put_bits(slots+used,bits,jbv_kind(t.data[0]));used+=width;
    }
    if (i != (args ? args->length : 0)) { status=JBV_BAD_ARGUMENT;goto done; }
    /* Initialization errors are not target exceptions and must not be wrapped. */
    if (m.kind == 2 || (method->flags & JBV_STATIC)) { status=jbv_initialize(vm,m.owner);if(status!=JBV_OK)goto done; }
    if (m.kind == 2) {
        status=jbv_new(vm,m.owner,0,&created);if(status!=JBV_OK)goto done;
        (void)jbv_retain(vm,created);slots[0]=created;
    } else if (!(method->flags & JBV_STATIC)) {
        JbvClass *actual;
        (void)jbv_object(vm,receiver,&o);actual=o->type;
        method=jbv_virtual_method(&actual,m.owner,method);m.owner=actual;
    }
    if (!method || (method->flags & JBV_ABSTRACT)) status=error(vm,"java/lang/AbstractMethodError");
    else status=jbv_execute(vm,m.owner,method,slots,refs,(uint16_t)used,&bits);
    if(status!=JBV_OK) {
        if(vm->exception) status=jbv_throw_named(vm,R "InvocationTargetException",vm->exception,JBV_EXCEPTION);
        goto done;
    }
    if(m.kind==2)*out=created;
    else if(result.data[0]=='V')*out=0;
    else if(jbv_reference_type(result))*out=(int32_t)bits;
    else status=jbv_box(vm,result.data[0],bits,out);
done:
    (void)jbv_release(vm,created);jbv_free(vm,slots);jbv_free(vm,refs);return status;
}
static JbvStatus field(JbvVM *vm, Member m, JbvObject *member, const int32_t *a, int32_t *out) {
    JbvField *f=(JbvField *)m.target;
    JbvObject *o;
    int32_t *location;
    uint64_t bits;
    JbvStatus status=access(vm,m,member,a[1],0);
    if(status!=JBV_OK)return status;
    if(a[3] != 0 && a[3] != 1 && jbv_reference_type(f->descriptor)) return JBV_BAD_ARGUMENT;
    if(a[3] <= 1 && a[3] != 0 && (f->flags & JBV_FINAL) && (!jbv_data(member)[3] || (f->flags & JBV_STATIC) || jbv_attribute(m.owner,m.owner->attributes,"Record"))) return error(vm,"java/lang/IllegalAccessException");
    if(f->flags & JBV_STATIC){status=jbv_initialize(vm,m.owner);location=&f->value;}
    else {(void)jbv_object(vm,a[1],&o);location=jbv_data(o)+f->slot;}
    if(status!=JBV_OK)return status;
    if(a[3] <= 1 && a[3] != 0){status=convert(vm,a[2],f->descriptor,&bits);if(status==JBV_OK)jbv_put_bits(location,bits,jbv_kind(f->descriptor.data[0]));return status;}
    bits=jbv_slot_bits(location,jbv_kind(f->descriptor.data[0]));
    if(jbv_reference_type(f->descriptor)){*out=(int32_t)bits;return JBV_OK;}
    return jbv_box(vm,f->descriptor.data[0],bits,out);
}
static JbvStatus reflect_array(JbvVM *vm, const int32_t *a, int32_t *out) {
    JbvObject *o, *dims;
    JbvClass *c = 0;
    JbvStatus status;
    uint32_t i, dimensions=0;
    uint64_t bits;
    uint8_t code;
    if (a[3] == 0 || a[3] == 1) {
        c=jbv_mirror_type(vm,a[0]);if(!c)return JBV_NULL_REFERENCE;
        if(c->primitive=='V')return JBV_BAD_ARGUMENT;
        if(a[3]==1){status=jbv_object(vm,a[2],&dims);if(status!=JBV_OK)return status;dimensions=dims->length;if(!dimensions||dimensions>255)return JBV_BAD_ARGUMENT;}
        else {dims=0;dimensions=1;}
        for(i=0;i<c->name.size&&c->name.data[i]=='[';++i){}
        if(dimensions+i>255)return JBV_BAD_ARGUMENT;
        for(i=0;i<dimensions;++i){if(dims&&jbv_data(dims)[i]<0)return JBV_NEGATIVE_ARRAY_SIZE;status=jbv_array_class(vm,c->primitive?0:c,c->primitive?c->primitive:'L',&c);if(status!=JBV_OK)return status;}
        return dims?jbv_multi_array(vm,c,jbv_data(dims),(uint8_t)dimensions,out):jbv_new(vm,c,a[1],out);
    }
    status=jbv_object(vm,a[0],&o);if(status!=JBV_OK)return status;
    c=o->type;code=c->array_kind;if(!code)return JBV_BAD_ARGUMENT;
    if((a[3]<0||a[3]>4)&&code=='L')return JBV_BAD_ARGUMENT;
    if(a[3]==2)return jbv_box(vm,'I',o->length,out);
    if(a[1]<0||(uint32_t)a[1]>=o->length)return JBV_ARRAY_BOUNDS;
    if(a[3]==3||a[3]>4){bits=code=='C'?jbv_chars(o)[a[1]]:jbv_slot_bits(jbv_data(o)+a[1]*jbv_width(jbv_kind(code)),jbv_kind(code));if(code=='L'){*out=(int32_t)bits;return JBV_OK;}return jbv_box(vm,code,bits,out);}
    if(code=='L'){
        JbvObject *value;
        if(a[2]){status=jbv_object(vm,a[2],&value);if(status!=JBV_OK)return status;if(!jbv_assignable(value->type,c->component))return JBV_BAD_ARGUMENT;}
        bits=(uint32_t)a[2];
    }else{JbvText t={&code,1};status=convert(vm,a[2],t,&bits);if(status!=JBV_OK)return status;}
    if(code=='C')jbv_chars(o)[a[1]]=(uint16_t)bits;else jbv_put_bits(jbv_data(o)+a[1]*jbv_width(jbv_kind(code)),bits,jbv_kind(code));return JBV_OK;
}
JbvStatus JBV_CALL jbv_reflect_native(JbvVM *vm, void *user, const int32_t *a, uint16_t count, uint64_t *out) {
    uint32_t op=(uint32_t)(uintptr_t)user;
    JbvStatus status;
    Member m;
    JbvObject *o;
    int32_t ref=0;
    (void)count;*out=0;
    if(op==5)status=reflect_array(vm,a,&ref);
    else if(op==6){uint64_t bits;status=jbv_unbox(vm,a[0],(uint8_t)a[1],0,&bits);if(status==JBV_CLASS_CAST||status==JBV_NULL_REFERENCE)status=JBV_BAD_ARGUMENT;if(status==JBV_OK)status=jbv_box(vm,(uint8_t)a[1],bits,&ref);}
    else {
        status=unpack(vm,a[0],&m,&o);if(status!=JBV_OK)return status;
        if(op==0)status=info(vm,m,(uint32_t)a[1],&ref);
        else if(op==1){*out=flags(m);return JBV_OK;}
        else if(op==2)status=invoke(vm,m,o,a[1],a[2],&ref);
        else if(op==3)status=field(vm,m,o,a,&ref);
        else if(op==7){
            const uint8_t *p;
            if(a[1]==-1)status=jbv_annotations(vm,m.owner,jbv_attribute(m.owner,attributes(m),"RuntimeVisibleAnnotations"),&ref);
            else {
                JbvText d=descriptor(m);uint32_t pos=1,width,n=0,i;JbvObject *outer;const uint8_t *cursor;
                while(d.data[pos]!=')'){(void)jbv_descriptor_type(d,&pos,&width);++n;}
                p=jbv_attribute(m.owner,attributes(m),"RuntimeVisibleParameterAnnotations");
                status=array(vm,"[Ljava/lang/annotation/Annotation;",n,&ref,&outer);
                if(status!=JBV_OK)return status;
                (void)jbv_retain(vm,ref);cursor=p?p+1:0;
                for(i=0;i<n&&status==JBV_OK;++i){
                    /* Decode one annotation table; advance across it using the
                     * reader rather than keeping additional metadata copies. */
                    int32_t item=0;
                    status=jbv_annotations(vm,m.owner,p&&i<n-*p?0:cursor,&item);if(status==JBV_OK)jbv_data(outer)[i]=item;
                    if(cursor&&i>=n-*p)cursor=jbv_skip_annotations(cursor);
                }
                (void)jbv_release(vm,ref);
            }
        }
        else if(op==4){status=access(vm,m,o,a[1],1);if(vm->exception && status==JBV_EXCEPTION){vm->exception=0;return JBV_OK;}*out=status==JBV_OK;return status;}
        else return JBV_UNSUPPORTED_FEATURE;
    }
    if(status==JBV_OK)*out=(uint32_t)ref;return status;
}

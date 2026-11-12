#include "classpath.h"

#if !defined(_M_IX86)   /* annotations_x86.asm; this is the reference */
#define ANNOTATION "java/lang/annotation/Annotation"
#define IMPL "jbv/runtime/AnnotationValue"
JBV_GC static JbvStatus read_annotation(JbvVM *vm, JbvClass *owner, const uint8_t **p, int32_t *ref);
static uint16_t read2(const uint8_t **p) { uint16_t n=jbv_u16(*p);*p+=2;return n; }
static const uint8_t *skip_value(const uint8_t *p);
static const uint8_t *skip_annotation(const uint8_t *p) {
    uint32_t i,n=jbv_u16(p+2);p+=4;
    for(i=0;i<n;++i)p=skip_value(p+2);
    return p;
}
static const uint8_t *skip_value(const uint8_t *p) {
    uint8_t tag=*p++;
    if(tag=='@')return skip_annotation(p);
    if(tag=='['){uint32_t n=jbv_u16(p);p+=2;while(n--)p=skip_value(p);return p;}
    return p+(tag=='e'?4:2);
}
const uint8_t *jbv_skip_annotations(const uint8_t *p) {
    uint32_t n=jbv_u16(p);p+=2;while(n--)p=skip_annotation(p);return p;
}
/* Element producers allocate (objects move): re-fetch the pinned array to store. */
static void store(JbvVM *vm, int32_t array, uint32_t i, int32_t value) {
    JbvObject *o;
    (void)jbv_object(vm,array,&o);jbv_data(o)[i]=value;jbv_barrier_checked(vm,o,value);
}
JBV_GC static JbvStatus clone_array(JbvVM *vm, int32_t value, int32_t *out) {
    JbvObject *o, *copy;
    JbvStatus status=jbv_object(vm,value,&o);
    size_t i;
    if(status!=JBV_OK)return status;
    *out=value;if(!o->type->array_kind)return JBV_OK;
    status=jbv_new(vm,o->type,o->type->array_kind?(int32_t)jbv_length(o):0,out);
    if(status!=JBV_OK)return status;
    (void)jbv_object(vm,*out,&copy);(void)jbv_object(vm,value,&o);   /* jbv_new may have moved it */
    for(i=0;i<jbv_object_bytes(o);++i)((volatile uint8_t *)(copy+1))[i]=((const uint8_t *)(o+1))[i];
    return JBV_OK;
}
JBV_GC static JbvStatus JBV_CALL element(JbvVM *vm, void *user, const int32_t *a, uint16_t count, uint64_t *out) {
    JbvObject *o,*values;
    int32_t ref;
    JbvStatus status=jbv_object(vm,a[0],&o);
    JbvMethod *method;
    uint32_t index=(uint32_t)(uintptr_t)user;
    (void)count;if(status!=JBV_OK)return status;
    method=&o->type->methods[index];
    (void)jbv_object(vm,jbv_data(o)[1],&values);ref=jbv_data(values)[index];
    if(!ref)return jbv_throw_named(vm,"java/lang/annotation/IncompleteAnnotationException",0,JBV_EXCEPTION);
    if(jbv_reference_type(jbv_return_type(method->descriptor))){status=clone_array(vm,ref,&ref);if(status==JBV_OK)*out=(uint32_t)ref;return status;}
    return jbv_unbox(vm,ref,jbv_return_type(method->descriptor).data[0],0,out);
}
static JbvStatus implementation(JbvVM *vm, JbvClass *type, JbvClass **out) {
    JbvClass *c,*base=0;
    uint32_t i;
    JbvStatus status;
    for(c=vm->classes;c;c=c->next)if(c->super&&jbv_text_is(c->super->name,IMPL)&&c->interface_count==1&&c->interfaces[0]==type){*out=c;return JBV_OK;}
    status=jbv_resolve_class(vm,jbv_text(IMPL),&base);if(status!=JBV_OK)return status;
    c=(JbvClass *)jbv_alloc(vm,sizeof(*c)+type->name.size+16);if(!c)return JBV_OUT_OF_MEMORY;
    c->name.data=(const uint8_t *)(c+1);c->name.size=type->name.size+15;
    for(i=0;i<type->name.size;++i)((uint8_t *)c->name.data)[i]=type->name.data[i];
    for(i=0;i<15;++i)((uint8_t *)c->name.data)[type->name.size+i]="$$JbvAnnotation"[i];
    if(jbv_find_class(vm,c->name)){jbv_free_class(vm,c);return JBV_LINKAGE_ERROR;}
    c->methods=(JbvMethod *)jbv_alloc(vm,type->method_count*sizeof(*c->methods));
    c->interfaces=(JbvClass **)jbv_alloc(vm,sizeof(*c->interfaces));
    if(!c->methods||!c->interfaces){jbv_free_class(vm,c);return JBV_OUT_OF_MEMORY;}
    c->super=base;c->instance_slots=base->instance_slots;c->flags=1|JBV_FINAL;c->init_state=c->link_state=2;
    c->interface_count=1;c->interfaces[0]=type;
    for(i=0;i<type->method_count;++i){
        JbvMethod *m;
        if (!(type->methods[i].flags & JBV_ABSTRACT)) continue;
        m=&c->methods[c->method_count++];m->name=type->methods[i].name;m->descriptor=type->methods[i].descriptor;
        m->flags=1|JBV_FINAL|JBV_NATIVE;m->intrinsic=4;m->native_slots=element;m->native_user=(void *)(uintptr_t)(c->method_count-1);m->attributes=type->methods[i].attributes;jbv_prepare_method(m);
    }
    c->next=vm->classes;vm->classes=c;*out=c;return JBV_OK;
}
JBV_GC static JbvStatus read_value(JbvVM *vm, JbvClass *owner, const uint8_t **p, JbvText expected, int32_t *ref) {
    uint8_t tag=*(*p)++;
    uint16_t index;
    JbvClass *type=0;
    JbvStatus status;
    JbvConstant *constant;
    if(tag=='@')return read_annotation(vm,owner,p,ref);
    if(tag=='['){
        uint32_t i,n=read2(p);JbvObject *o;JbvText component={expected.data+1,(uint16_t)(expected.size-1)};
        status=jbv_type_class(vm,expected,&type);if(status==JBV_OK)status=jbv_new(vm,type,(int32_t)n,ref);
        if(status!=JBV_OK)return status;
        (void)jbv_retain(vm,*ref);
        for(i=0;i<n&&status==JBV_OK;++i){
            int32_t item=0;uint64_t bits;
            status=jbv_annotation_value(vm,owner,p,component,&item);if(status!=JBV_OK)break;
            if(type->array_kind=='L')store(vm,*ref,i,item);
            else {status=jbv_unbox(vm,item,type->array_kind,0,&bits);if(status!=JBV_OK)break;
                (void)jbv_object(vm,*ref,&o);jbv_array_set(o,i,type->array_kind,bits);}
        }
        (void)jbv_release(vm,*ref);return status;
    }
    index=read2(p);constant=&owner->pool[index];
    if(tag=='s')return jbv_string_mutf(vm,constant->text,ref);
    if(tag=='c'){status=jbv_type_class(vm,constant->text,&type);return status==JBV_OK?jbv_mirror(vm,type,ref):status;}
    if(tag=='e'){
        JbvText name=owner->pool[read2(p)].text;uint32_t i;
        status=jbv_type_class(vm,constant->text,&type);if(status==JBV_OK)status=jbv_initialize(vm,type);
        if(status!=JBV_OK)return status;
        for(i=0;i<type->field_count;++i)if(jbv_text_eq(type->fields[i].name,name)&&(type->fields[i].flags&0x4000)){*ref=type->fields[i].value;return JBV_OK;}
        return jbv_throw_named(vm,"java/lang/EnumConstantNotPresentException",0,JBV_EXCEPTION);
    }
    return jbv_box(vm,tag,(uint64_t)constant->bits_hi<<32|constant->bits,ref);
}
JbvStatus jbv_annotation_value(JbvVM *vm, JbvClass *owner, const uint8_t **p, JbvText expected, int32_t *ref) {
    JbvStatus status;
    if(vm->depth>=vm->config.max_depth)return JBV_LIMIT_EXCEEDED;
    ++vm->depth;status=read_value(vm,owner,p,expected,ref);--vm->depth;return status;
}
static JbvStatus read_annotation(JbvVM *vm, JbvClass *owner, const uint8_t **p, int32_t *ref) {
    JbvClass *type=0,*impl=0,*array_type=0;
    JbvObject *o;
    JbvText desc=owner->pool[read2(p)].text;
    uint32_t i,j,n=read2(p);
    int32_t array_ref=0,mirror=0,item;
    JbvStatus status=jbv_type_class(vm,desc,&type);
    if(status==JBV_OK)status=implementation(vm,type,&impl);
    if(status==JBV_OK)status=jbv_mirror(vm,type,&mirror);
    if(status==JBV_OK)status=jbv_array_class(vm,jbv_find_class(vm,jbv_text("java/lang/Object")),'L',&array_type);
    if(status==JBV_OK)status=jbv_new(vm,array_type,impl->method_count,&array_ref);
    if(status!=JBV_OK)return status;
    (void)jbv_retain(vm,array_ref);
    /* Resolve explicitly supplied values first: an overridden default must not
     * be evaluated (it can mention a type no longer present in the application). */
    for(i=0;i<n;++i){
        JbvText key=owner->pool[read2(p)].text;
        for(j=0;j<impl->method_count&&!jbv_text_eq(impl->methods[j].name,key);++j){}
        if(j==impl->method_count){*p=skip_value(*p);continue;}
        status=jbv_annotation_value(vm,owner,p,jbv_return_type(impl->methods[j].descriptor),&item);if(status!=JBV_OK)goto done;
        store(vm,array_ref,j,item);
    }
    for(i=0;i<impl->method_count;++i){
        const uint8_t *d;
        (void)jbv_object(vm,array_ref,&o);if(jbv_data(o)[i])continue;
        d=jbv_attribute(type,impl->methods[i].attributes,"AnnotationDefault");
        if(d){status=jbv_annotation_value(vm,type,&d,jbv_return_type(impl->methods[i].descriptor),&item);if(status!=JBV_OK)goto done;store(vm,array_ref,i,item);}
    }
    status=jbv_new(vm,impl,0,ref);if(status==JBV_OK){(void)jbv_object(vm,*ref,&o);jbv_data(o)[0]=mirror;jbv_data(o)[1]=array_ref;}
done:
    (void)jbv_release(vm,array_ref);return status;
}
JbvStatus jbv_annotations(JbvVM *vm, JbvClass *owner, const uint8_t *p, int32_t *ref) {
    JbvClass *type=0;
    int32_t item;
    uint32_t n=p?read2(&p):0,i;
    JbvStatus status=jbv_resolve_class(vm,jbv_text(ANNOTATION),&type);
    if(status==JBV_OK)status=jbv_array_class(vm,type,'L',&type);
    if(status==JBV_OK)status=jbv_new(vm,type,(int32_t)n,ref);
    if(status!=JBV_OK)return status;
    (void)jbv_retain(vm,*ref);
    for(i=0;i<n&&status==JBV_OK;++i){status=read_annotation(vm,owner,&p,&item);if(status==JBV_OK)store(vm,*ref,i,item);}
    (void)jbv_release(vm,*ref);return status;
}
#endif

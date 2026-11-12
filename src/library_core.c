#include "internal.h"

#if !defined(_M_IX86)   /* core_x86.asm; this is the reference */
/* The core profile supplies object identity and cloning. Text, Class mirrors,
 * primitive wrappers and the Java class library are separate build features. */
JBV_GC static JbvStatus JBV_CALL core_native(JbvVM *vm, void *user, const int32_t *args, uint16_t count, uint64_t *out) {
    uint32_t op = (uint32_t)(uintptr_t)user;
    JbvObject *object, *copy = 0;
    JbvStatus status;
    int32_t ref;
    size_t i, bytes;
    (void)count;
    if (op == 1) { *out = args[0] == args[1]; return JBV_OK; }
    if (op == 2) { *out = (uint32_t)args[0]; return JBV_OK; }
    if (op == 4) return jbv_monitor(vm, 0, args[0], 0);
    status = jbv_object(vm,args[0],&object);if(status!=JBV_OK)return status;
    if (!jbv_assignable(object->type,jbv_find_class(vm,jbv_text("java/lang/Cloneable"))))
        return jbv_throw_named(vm,"java/lang/CloneNotSupportedException",0,JBV_EXCEPTION);
    status = jbv_new(vm,object->type,object->type->array_kind?(int32_t)jbv_length(object):0,&ref);if(status!=JBV_OK)return status;
    (void)jbv_object(vm,args[0],&object);(void)jbv_object(vm,ref,&copy);bytes=jbv_object_bytes(object);
    for(i=0;i<bytes;++i)((volatile uint8_t *)(copy+1))[i]=((uint8_t *)(object+1))[i];
    *out=(uint32_t)ref;return JBV_OK;
}
JbvStatus jbv_library_object(JbvVM *vm, JbvClass *type) {
    static const char *const names[]={"<init>","equals","hashCode","clone","notify","notifyAll"};
    static const char *const descriptors[]={"()V","(Ljava/lang/Object;)Z","()I","()Ljava/lang/Object;","()V","()V"};
    uint32_t i;
    jbv_free(vm,type->methods);type->methods=0;type->method_count=0;
    type->methods=(JbvMethod *)jbv_alloc(vm,6*sizeof(*type->methods));if(!type->methods)return JBV_OUT_OF_MEMORY;
    type->method_count=6;
    for(i=0;i<6;++i){JbvMethod *m=&type->methods[i];m->name=jbv_text(names[i]);m->descriptor=jbv_text(descriptors[i]);
        m->flags=JBV_NATIVE|(i==3?4:1);m->intrinsic=i?3:1;m->native_slots=core_native;m->native_user=(void *)(uintptr_t)(i==5?4:i);jbv_prepare_method(m);}
    return JBV_OK;
}
uint8_t jbv_library_id(JbvText name) {(void)name;return 0;}
JbvStatus jbv_library_class(JbvVM *vm,JbvText name,JbvClass **out){(void)vm;(void)name;(void)out;return JBV_NOT_FOUND;}
JbvStatus jbv_library_initialize(JbvVM *vm,JbvClass *type){(void)vm;(void)type;return JBV_OK;}
JbvStatus jbv_literal(JbvVM *vm,JbvClass *type,uint16_t index,int32_t *out){(void)vm;(void)type;(void)index;(void)out;return JBV_UNSUPPORTED_FEATURE;}
JbvStatus jbv_mirror(JbvVM *vm,JbvClass *type,int32_t *out){(void)vm;(void)type;(void)out;return JBV_UNSUPPORTED_FEATURE;}
JBV_GC JBV_API JbvStatus JBV_CALL jbv_string_new_utf16(JbvVM *vm,const uint16_t *text,uint32_t length,JbvRef *out){(void)vm;(void)text;(void)length;(void)out;return JBV_UNSUPPORTED_FEATURE;}
JBV_GC JBV_API JbvStatus JBV_CALL jbv_string_new_utf8(JbvVM *vm,const char *text,uint32_t length,JbvRef *out){(void)vm;(void)text;(void)length;(void)out;return JBV_UNSUPPORTED_FEATURE;}
JBV_API JbvStatus JBV_CALL jbv_string_length(JbvVM *vm,JbvRef ref,uint32_t *out){(void)vm;(void)ref;(void)out;return JBV_UNSUPPORTED_FEATURE;}
JBV_API JbvStatus JBV_CALL jbv_string_read_utf16(JbvVM *vm,JbvRef ref,uint32_t start,uint32_t count,uint16_t *out){(void)vm;(void)ref;(void)start;(void)count;(void)out;return JBV_UNSUPPORTED_FEATURE;}
JBV_API JbvStatus JBV_CALL jbv_string_read_utf8(JbvVM *vm,JbvRef ref,char *out,uint32_t capacity,uint32_t *bytes){(void)vm;(void)ref;(void)out;(void)capacity;(void)bytes;return JBV_UNSUPPORTED_FEATURE;}
#endif

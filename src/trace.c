#include "library.h"

static int internal_frame(JbvFrame *frame, JbvClass *throwable) {
    return jbv_text_is(frame->owner->name,"jbv/runtime/Support") ||
        (jbv_assignable(frame->owner,throwable) &&
            (jbv_text_is(frame->method->name,"<init>") || jbv_text_is(frame->method->name,"fillInStackTrace")));
}
JbvStatus jbv_capture_trace(JbvVM *vm, int32_t *out) {
    JbvClass *throwable, *element_type, *array_type = 0;
    JbvObject *array = 0, *element = 0;
    JbvFrame *frame, *first = vm->frames;
    JbvStatus status;
    uint32_t length = 0, i = 0, j;
    int32_t array_ref = 0, ref;
    status = jbv_resolve_class(vm,jbv_text("java/lang/Throwable"),&throwable);
    if (status != JBV_OK) return status;
    while (first && internal_frame(first,throwable)) first = first->previous;
    for (frame = first; frame; frame = frame->previous) ++length;
    status = jbv_resolve_class(vm,jbv_text("java/lang/StackTraceElement"),&element_type);
    if (status == JBV_OK) status = jbv_array_class(vm,element_type,'L',&array_type);
    if (status == JBV_OK) status = jbv_new(vm,array_type,(int32_t)length,&array_ref);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm,array_ref); (void)jbv_object(vm,array_ref,&array);
    for (frame = first; frame; frame = frame->previous) {
        int32_t *fields, line = -1;
        JbvTextView name;
        status = jbv_new(vm,element_type,0,&ref); if (status != JBV_OK) break;
        jbv_data(array)[i++] = ref; (void)jbv_object(vm,ref,&element); fields=jbv_data(element);
        status = jbv_string_mutf(vm,frame->owner->name,&fields[0]); if (status != JBV_OK) break;
        (void)jbv_string_view(vm,fields[0],&name); for (j=0;j<name.length;++j) if(name.data[j]=='/')name.data[j]='.';
        status = jbv_string_mutf(vm,frame->method->name,&fields[1]); if (status != JBV_OK) break;
        if (frame->owner->source_file.size) {status = jbv_string_mutf(vm,frame->owner->source_file,&fields[2]);if(status!=JBV_OK)break;}
        if (frame->method->flags & JBV_NATIVE) line = -2;
        else for (j=0;j<frame->method->line_count;++j) if(jbv_u16(frame->method->lines+4*j)<=*frame->pc)line=jbv_u16(frame->method->lines+4*j+2);
        fields[3]=line;
    }
    if (status == JBV_OK) *out=array_ref;
    (void)jbv_release(vm,array_ref);return status;
}

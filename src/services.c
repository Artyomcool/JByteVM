#include "internal.h"
#if !defined(_M_IX86)   /* x86: in assembly; this is the reference */
JBV_API uint32_t JBV_CALL jbv_features(void) {
    return JBV_FEATURE_NATIVE | JBV_FEATURE_MONITORS | JBV_FEATURE_ACCESS
#if !JBV_PROFILE_CORE
        | JBV_FEATURE_TEXT
#endif
#if JBV_PROFILE_FULL
        | JBV_FEATURE_CLASSPATH | JBV_FEATURE_REFLECTION | JBV_FEATURE_TRACES
#endif
        ;
}
JBV_API JbvStatus JBV_CALL jbv_set_host_services(JbvVM *vm,const JbvHostServices *services) {
    JbvHostServices empty={0};
    if(!vm)return JBV_BAD_ARGUMENT;if(vm->depth)return JBV_BUSY;vm->services=services?*services:empty;return JBV_OK;
}
#endif

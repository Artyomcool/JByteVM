package java.lang.invoke;
public final class MethodHandles {
    private MethodHandles() {}
    public static Lookup lookup(){return new Lookup(jbv.runtime.Support.callerClass(1));}
    public static Lookup publicLookup(){return new Lookup(null);}
    public static final class Lookup {
        private final Class<?> caller;
        Lookup(Class<?> caller){this.caller=caller;}
        public Class<?> lookupClass(){return caller==null?Object.class:caller;}
        public int lookupModes(){return caller==null?32:95;}
        public boolean hasFullPrivilegeAccess(){return caller!=null;}
        public MethodHandle findStatic(Class<?> owner,String name,MethodType type)throws NoSuchMethodException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,name,type.toMethodDescriptorString(),6);}
        public MethodHandle findVirtual(Class<?> owner,String name,MethodType type)throws NoSuchMethodException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,name,type.toMethodDescriptorString(),5);}
        public MethodHandle findConstructor(Class<?> owner,MethodType type)throws NoSuchMethodException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,"<init>",type.toMethodDescriptorString(),8);}
        public MethodHandle findGetter(Class<?> owner,String name,Class<?> type)throws NoSuchFieldException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,name,MethodType.methodType(type).toMethodDescriptorString().substring(2),1);}
        public MethodHandle findSetter(Class<?> owner,String name,Class<?> type)throws NoSuchFieldException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,name,MethodType.methodType(type).toMethodDescriptorString().substring(2),3);}
        public MethodHandle findStaticGetter(Class<?> owner,String name,Class<?> type)throws NoSuchFieldException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,name,MethodType.methodType(type).toMethodDescriptorString().substring(2),2);}
        public MethodHandle findStaticSetter(Class<?> owner,String name,Class<?> type)throws NoSuchFieldException,IllegalAccessException{return jbv.runtime.Support.findHandle(caller,owner,name,MethodType.methodType(type).toMethodDescriptorString().substring(2),4);}
    }
}

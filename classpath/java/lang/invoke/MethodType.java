package java.lang.invoke;
import java.util.Objects;
public final class MethodType {
    private final String descriptor;
    private MethodType(String descriptor){this.descriptor=descriptor;}
    public static MethodType fromMethodDescriptorString(String descriptor,ClassLoader loader){Objects.requireNonNull(descriptor);jbv.runtime.Support.methodTypeClass(descriptor,-2);return new MethodType(descriptor);}
    private static String descriptor(Class<?> type){Objects.requireNonNull(type);String n=type.getName();if(type.isArray())return n.replace('.','/');if(!type.isPrimitive())return "L"+n.replace('.','/')+";";String[] names={"void","boolean","byte","char","short","int","long","float","double"};String codes="VZBCSIJFD";for(int i=0;i<names.length;i++)if(n.equals(names[i]))return String.valueOf(codes.charAt(i));throw new IllegalArgumentException();}
    public static MethodType methodType(Class<?> result,Class<?>... args){StringBuilder b=new StringBuilder("(");for(Class<?> c:args){if(c==void.class)throw new IllegalArgumentException();b.append(descriptor(c));}return fromMethodDescriptorString(b.append(')').append(descriptor(result)).toString(),null);}
    public static MethodType methodType(Class<?> result){return methodType(result,new Class<?>[0]);}
    public static MethodType methodType(Class<?> result,Class<?> arg){return methodType(result,new Class<?>[]{arg});}
    public static MethodType methodType(Class<?> result,Class<?> first,Class<?>... rest){Class<?>[] all=new Class<?>[rest.length+1];all[0]=first;System.arraycopy(rest,0,all,1,rest.length);return methodType(result,all);}
    public Class<?> returnType(){return jbv.runtime.Support.methodTypeClass(descriptor,-1);}
    public Class<?> parameterType(int index){return jbv.runtime.Support.methodTypeClass(descriptor,index);}
    public int parameterCount(){int n=0;for(int i=1;descriptor.charAt(i)!=')';n++){while(descriptor.charAt(i)=='[')i++;if(descriptor.charAt(i++)=='L')while(descriptor.charAt(i++)!=';'){} }return n;}
    public Class<?>[] parameterArray(){Class<?>[] a=new Class<?>[parameterCount()];for(int i=0;i<a.length;i++)a[i]=parameterType(i);return a;}
    public MethodType changeReturnType(Class<?> result){return methodType(result,parameterArray());}
    public MethodType changeParameterType(int index,Class<?> type){Class<?>[] a=parameterArray();a[index]=type;return methodType(returnType(),a);}
    public String toMethodDescriptorString(){return descriptor;}
    public boolean equals(Object o){return o instanceof MethodType&&descriptor.equals(((MethodType)o).descriptor);}
    public int hashCode(){int h=31+returnType().hashCode();for(Class<?> c:parameterArray())h=31*h+c.hashCode();return h;}
    public String toString(){StringBuilder b=new StringBuilder("(");Class<?>[] a=parameterArray();for(int i=0;i<a.length;i++){if(i>0)b.append(',');b.append(a[i].getName());}return b.append(')').append(returnType().getName()).toString();}
}

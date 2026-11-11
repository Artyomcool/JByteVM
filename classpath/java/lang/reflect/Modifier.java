package java.lang.reflect;
public class Modifier {
 public static final int PUBLIC=1; public static boolean isPublic(int m){return (m&PUBLIC)!=0;}
 public static final int PRIVATE=2; public static boolean isPrivate(int m){return (m&PRIVATE)!=0;}
 public static final int PROTECTED=4; public static boolean isProtected(int m){return (m&PROTECTED)!=0;}
 public static final int STATIC=8; public static boolean isStatic(int m){return (m&STATIC)!=0;}
 public static final int FINAL=16; public static boolean isFinal(int m){return (m&FINAL)!=0;}
 public static final int SYNCHRONIZED=32; public static boolean isSynchronized(int m){return (m&SYNCHRONIZED)!=0;}
 public static final int VOLATILE=64; public static boolean isVolatile(int m){return (m&VOLATILE)!=0;}
 public static final int TRANSIENT=128; public static boolean isTransient(int m){return (m&TRANSIENT)!=0;}
 public static final int NATIVE=256; public static boolean isNative(int m){return (m&NATIVE)!=0;}
 public static final int INTERFACE=512; public static boolean isInterface(int m){return (m&INTERFACE)!=0;}
 public static final int ABSTRACT=1024; public static boolean isAbstract(int m){return (m&ABSTRACT)!=0;}
 public static final int STRICT=2048; public static boolean isStrict(int m){return (m&STRICT)!=0;}
 public static String toString(int m){StringBuilder s=new StringBuilder();if((m&PUBLIC)!=0)s.append("public ");if((m&PROTECTED)!=0)s.append("protected ");if((m&PRIVATE)!=0)s.append("private ");if((m&ABSTRACT)!=0)s.append("abstract ");if((m&STATIC)!=0)s.append("static ");if((m&FINAL)!=0)s.append("final ");if((m&TRANSIENT)!=0)s.append("transient ");if((m&VOLATILE)!=0)s.append("volatile ");if((m&SYNCHRONIZED)!=0)s.append("synchronized ");if((m&NATIVE)!=0)s.append("native ");if((m&STRICT)!=0)s.append("strictfp ");if((m&INTERFACE)!=0)s.append("interface ");return s.length()==0?"":s.substring(0,s.length()-1);}
}

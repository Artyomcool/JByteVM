package java.lang.reflect;
import jbv.runtime.Reflection;
public final class Array {
 private Array() {}
 public static Object newInstance(Class<?> component,int length){return Reflection.array(component,length,null,0);}
 public static Object newInstance(Class<?> component,int... dimensions){return Reflection.array(component,0,dimensions,1);}
 public static int getLength(Object array){return ((Integer)Reflection.array(array,0,null,2)).intValue();}
 public static Object get(Object array,int index){return Reflection.array(array,index,null,3);}
 public static void set(Object array,int index,Object value){Reflection.array(array,index,value,4);}
 public static boolean getBoolean(Object array,int index){return ((Boolean)Reflection.convert(Reflection.array(array,index,null,'Z'),'Z')).booleanValue();}
 public static void setBoolean(Object array,int index,boolean value){Reflection.array(array,index,value,-'Z');}
 public static byte getByte(Object array,int index){return ((Byte)Reflection.convert(Reflection.array(array,index,null,'B'),'B')).byteValue();}
 public static void setByte(Object array,int index,byte value){Reflection.array(array,index,value,-'B');}
 public static char getChar(Object array,int index){return ((Character)Reflection.convert(Reflection.array(array,index,null,'C'),'C')).charValue();}
 public static void setChar(Object array,int index,char value){Reflection.array(array,index,value,-'C');}
 public static short getShort(Object array,int index){return ((Short)Reflection.convert(Reflection.array(array,index,null,'S'),'S')).shortValue();}
 public static void setShort(Object array,int index,short value){Reflection.array(array,index,value,-'S');}
 public static int getInt(Object array,int index){return ((Integer)Reflection.convert(Reflection.array(array,index,null,'I'),'I')).intValue();}
 public static void setInt(Object array,int index,int value){Reflection.array(array,index,value,-'I');}
 public static long getLong(Object array,int index){return ((Long)Reflection.convert(Reflection.array(array,index,null,'J'),'J')).longValue();}
 public static void setLong(Object array,int index,long value){Reflection.array(array,index,value,-'J');}
 public static float getFloat(Object array,int index){return ((Float)Reflection.convert(Reflection.array(array,index,null,'F'),'F')).floatValue();}
 public static void setFloat(Object array,int index,float value){Reflection.array(array,index,value,-'F');}
 public static double getDouble(Object array,int index){return ((Double)Reflection.convert(Reflection.array(array,index,null,'D'),'D')).doubleValue();}
 public static void setDouble(Object array,int index,double value){Reflection.array(array,index,value,-'D');}
}

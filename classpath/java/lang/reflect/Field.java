package java.lang.reflect;
import jbv.runtime.Reflection;
public final class Field extends AccessibleObject implements Member {
 Field() {}
 public Class<?> getDeclaringClass(){return owner;}
 public String getName(){return name();}
 public int getModifiers(){return flags();}
 public Class<?> getType(){return type();}
 public Type getGenericType(){return (Type)jbv.runtime.Generics.member(this,0);}
 public boolean isSynthetic(){return (getModifiers()&0x1000)!=0;}
 public boolean isEnumConstant(){return (getModifiers()&0x4000)!=0;}
 public Object get(Object receiver)throws IllegalAccessException{return Reflection.field(this,receiver,null,0);}
 public void set(Object receiver,Object value)throws IllegalAccessException{Reflection.field(this,receiver,value,1);}
 public boolean equals(Object other){return other instanceof Field&&same((Field)other);}
 public int hashCode(){return getDeclaringClass().getName().hashCode()^getName().hashCode();}
 static String typeName(Class<?> c){return c.isArray()?typeName(c.getComponentType())+"[]":c.getName();}
 public String toString(){String m=Modifier.toString(getModifiers());return (m.isEmpty()?"":m+" ")+typeName(getType())+" "+getDeclaringClass().getName()+"."+getName();}
 public boolean getBoolean(Object receiver) throws IllegalAccessException{return ((Boolean)Reflection.convert(Reflection.field(this,receiver,null,'Z'),'Z')).booleanValue();}
 public void setBoolean(Object receiver,boolean value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'Z');}
 public byte getByte(Object receiver) throws IllegalAccessException{return ((Byte)Reflection.convert(Reflection.field(this,receiver,null,'B'),'B')).byteValue();}
 public void setByte(Object receiver,byte value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'B');}
 public char getChar(Object receiver) throws IllegalAccessException{return ((Character)Reflection.convert(Reflection.field(this,receiver,null,'C'),'C')).charValue();}
 public void setChar(Object receiver,char value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'C');}
 public short getShort(Object receiver) throws IllegalAccessException{return ((Short)Reflection.convert(Reflection.field(this,receiver,null,'S'),'S')).shortValue();}
 public void setShort(Object receiver,short value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'S');}
 public int getInt(Object receiver) throws IllegalAccessException{return ((Integer)Reflection.convert(Reflection.field(this,receiver,null,'I'),'I')).intValue();}
 public void setInt(Object receiver,int value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'I');}
 public long getLong(Object receiver) throws IllegalAccessException{return ((Long)Reflection.convert(Reflection.field(this,receiver,null,'J'),'J')).longValue();}
 public void setLong(Object receiver,long value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'J');}
 public float getFloat(Object receiver) throws IllegalAccessException{return ((Float)Reflection.convert(Reflection.field(this,receiver,null,'F'),'F')).floatValue();}
 public void setFloat(Object receiver,float value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'F');}
 public double getDouble(Object receiver) throws IllegalAccessException{return ((Double)Reflection.convert(Reflection.field(this,receiver,null,'D'),'D')).doubleValue();}
 public void setDouble(Object receiver,double value) throws IllegalAccessException{Reflection.field(this,receiver,value,-'D');}
}

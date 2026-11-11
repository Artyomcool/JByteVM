package java.lang.reflect;
public interface Member { int PUBLIC=0,DECLARED=1; Class<?> getDeclaringClass(); String getName(); int getModifiers(); boolean isSynthetic(); }

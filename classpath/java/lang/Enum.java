package java.lang;
public abstract class Enum<E extends Enum<E>> implements Comparable<E>,java.io.Serializable {
    private final String name;private final int ordinal;
    protected Enum(String name,int ordinal){this.name=name;this.ordinal=ordinal;}
    public final String name(){return name;}public final int ordinal(){return ordinal;}
    public String toString(){return name;}
    public final boolean equals(Object other){return this==other;}
    public final int hashCode(){return System.identityHashCode(this);}
    public final int compareTo(E other){if(getDeclaringClass()!=other.getDeclaringClass())throw new ClassCastException();return ordinal-other.ordinal();}
    @SuppressWarnings("unchecked") public final Class<E> getDeclaringClass(){Class<?> c=getClass();return (Class<E>)(c.getSuperclass()==Enum.class?c:c.getSuperclass());}
    protected final Object clone()throws CloneNotSupportedException{throw new CloneNotSupportedException();}
    @SuppressWarnings("unchecked") public static <T extends Enum<T>> T valueOf(Class<T> type,String name){return (T)jbv.runtime.Support.enumValue(type,name);}
}

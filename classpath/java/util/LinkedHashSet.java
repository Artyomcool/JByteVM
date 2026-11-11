package java.util;
public class LinkedHashSet<E> extends HashSet<E> {
    public LinkedHashSet(){super(16,.75f,true);}
    public LinkedHashSet(int capacity){super(capacity,.75f,true);}
    public LinkedHashSet(int capacity,float loadFactor){super(capacity,loadFactor,true);}
    public LinkedHashSet(Collection<? extends E> c){super(Math.max(2*c.size(),11),.75f,true);addAll(c);}
    public static <T> LinkedHashSet<T> newLinkedHashSet(int expected){if(expected<0)throw new IllegalArgumentException();return new LinkedHashSet<T>((int)Math.min(1<<30,Math.ceil(expected/.75)));}
    public Object clone(){return new LinkedHashSet<E>(this);}
}

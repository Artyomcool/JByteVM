package java.util;
public abstract class AbstractSet<E> extends AbstractCollection<E> implements Set<E> {
    protected AbstractSet() {}
    public boolean equals(Object other){if(other==this)return true;if(!(other instanceof Set<?>))return false;Collection<?> c=(Collection<?>)other;return c.size()==size()&&containsAll(c);}
    public int hashCode(){int h=0;for(E x:this)h+=Objects.hashCode(x);return h;}
}

package java.util;
public interface Set<E> extends Collection<E> {
    static <E> Set<E> of(E... values){return jbv.runtime.Collections.immutableSet(values);}
    static <E> Set<E> copyOf(Collection<? extends E> values){return jbv.runtime.Collections.immutableSet(new HashSet<E>(values).toArray());}
    // BEGIN GENERATED FACTORIES
    static <E> Set<E> of(){return jbv.runtime.Collections.immutableSet(new Object[]{});}
    static <E> Set<E> of(E e0){return jbv.runtime.Collections.immutableSet(new Object[]{e0});}
    static <E> Set<E> of(E e0,E e1){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1});}
    static <E> Set<E> of(E e0,E e1,E e2){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3,E e4){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3,e4});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3,E e4,E e5){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3,e4,e5});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3,e4,e5,e6});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6,E e7){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3,e4,e5,e6,e7});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6,E e7,E e8){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3,e4,e5,e6,e7,e8});}
    static <E> Set<E> of(E e0,E e1,E e2,E e3,E e4,E e5,E e6,E e7,E e8,E e9){return jbv.runtime.Collections.immutableSet(new Object[]{e0,e1,e2,e3,e4,e5,e6,e7,e8,e9});}
    // END GENERATED FACTORIES
}

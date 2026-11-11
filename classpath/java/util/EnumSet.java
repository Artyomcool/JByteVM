package java.util;
/** One bit-vector implementation (long[] words) for every universe size; iterators behave like the JDK's. */
@SuppressWarnings("unchecked")
public class EnumSet<E extends Enum<E>> extends AbstractSet<E> implements Cloneable,java.io.Serializable {
    final Class<E> type;final Object[] universe;long[] bits;
    EnumSet(Class<E> type,Object[] universe){this.type=type;this.universe=universe;bits=new long[(universe.length+63)>>>6];}
    public static <E extends Enum<E>> EnumSet<E> noneOf(Class<E> type){
        Object[] u=type.getEnumConstants();if(u==null)throw new ClassCastException(type+" not an enum");
        return new EnumSet<E>(type,u);
    }
    public static <E extends Enum<E>> EnumSet<E> allOf(Class<E> type){EnumSet<E> s=noneOf(type);s.flip();return s;}
    public static <E extends Enum<E>> EnumSet<E> copyOf(EnumSet<E> s){return s.clone();}
    public static <E extends Enum<E>> EnumSet<E> copyOf(Collection<E> c){
        if(c instanceof EnumSet<?>)return ((EnumSet<E>)c).clone();
        if(c.isEmpty())throw new IllegalArgumentException("Collection is empty");
        EnumSet<E> s=make(c.iterator().next());s.addAll(c);return s;
    }
    public static <E extends Enum<E>> EnumSet<E> complementOf(EnumSet<E> s){EnumSet<E> r=s.clone();r.flip();return r;}
    public static <E extends Enum<E>> EnumSet<E> of(E e){return make(e);}
    public static <E extends Enum<E>> EnumSet<E> of(E e1,E e2){return make(e1,e2);}
    public static <E extends Enum<E>> EnumSet<E> of(E e1,E e2,E e3){return make(e1,e2,e3);}
    public static <E extends Enum<E>> EnumSet<E> of(E e1,E e2,E e3,E e4){return make(e1,e2,e3,e4);}
    public static <E extends Enum<E>> EnumSet<E> of(E e1,E e2,E e3,E e4,E e5){return make(e1,e2,e3,e4,e5);}
    @SafeVarargs public static <E extends Enum<E>> EnumSet<E> of(E first,E... rest){EnumSet<E> s=make(first);for(E e:rest)s.add(e);return s;}
    private static <E extends Enum<E>> EnumSet<E> make(E first,Enum<?>... rest){EnumSet<E> s=noneOf(first.getDeclaringClass());s.add(first);for(Enum<?> e:rest)s.add((E)e);return s;}
    public static <E extends Enum<E>> EnumSet<E> range(E from,E to){
        if(from.compareTo(to)>0)throw new IllegalArgumentException(from+" > "+to);
        EnumSet<E> s=noneOf(from.getDeclaringClass());for(int i=from.ordinal();i<=to.ordinal();i++)s.bits[i>>>6]|=1L<<i;return s;
    }
    private void flip(){int n=bits.length;for(int i=0;i<n;i++)bits[i]=~bits[i];if(n>0)bits[n-1]&=-1L>>>-universe.length;}
    /** Ordinal of o if it is a constant of this set's enum type, else -1. */
    private int index(Object o){if(o==null)return -1;Class<?> c=o.getClass();return c==type||c.getSuperclass()==type?((Enum<?>)o).ordinal():-1;}
    public int size(){int n=0;for(long w:bits)n+=Long.bitCount(w);return n;}
    public boolean isEmpty(){for(long w:bits)if(w!=0)return false;return true;}
    public boolean contains(Object o){int i=index(o);return i>=0&&(bits[i>>>6]&1L<<i)!=0;}
    public boolean add(E e){
        int i=index(Objects.requireNonNull(e));if(i<0)throw new ClassCastException(e.getClass()+" != "+type);
        long w=bits[i>>>6];bits[i>>>6]=w|1L<<i;return (w&1L<<i)==0;
    }
    public boolean remove(Object o){int i=index(o);if(i<0)return false;long w=bits[i>>>6];bits[i>>>6]=w&~(1L<<i);return (w&1L<<i)!=0;}
    public void clear(){Arrays.fill(bits,0L);}
    public Iterator<E> iterator(){return new Iterator<E>(){
        int word,lastWord;long unseen=bits.length>0?bits[0]:0,last;
        public boolean hasNext(){while(unseen==0&&word<bits.length-1)unseen=bits[++word];return unseen!=0;}
        public E next(){if(!hasNext())throw new NoSuchElementException();last=unseen&-unseen;lastWord=word;unseen-=last;return (E)universe[(word<<6)+Long.numberOfTrailingZeros(last)];}
        public void remove(){if(last==0)throw new IllegalStateException();bits[lastWord]&=~last;last=0;}
    };}
    public EnumSet<E> clone(){EnumSet<E> s=new EnumSet<E>(type,universe);s.bits=bits.clone();return s;}
}

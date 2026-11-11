package java.util;
import java.util.function.*;
public final class Optional<T> {
    private static final Optional<?> EMPTY=new Optional<Object>(null);
    private final T value;
    private Optional(T value){this.value=value;}
    @SuppressWarnings("unchecked") public static <T> Optional<T> empty(){return (Optional<T>)EMPTY;}
    public static <T> Optional<T> of(T value){return new Optional<T>(Objects.requireNonNull(value));}
    public static <T> Optional<T> ofNullable(T value){return value==null?Optional.<T>empty():new Optional<T>(value);}
    public T get(){if(value==null)throw new NoSuchElementException("No value present");return value;}
    public boolean isPresent(){return value!=null;}
    public boolean isEmpty(){return value==null;}
    public void ifPresent(Consumer<? super T> action){if(value!=null)action.accept(value);}
    public void ifPresentOrElse(Consumer<? super T> action,Runnable empty){if(value!=null)action.accept(value);else empty.run();}
    public Optional<T> filter(Predicate<? super T> p){Objects.requireNonNull(p);return value==null||p.test(value)?this:Optional.<T>empty();}
    public <U> Optional<U> map(Function<? super T,? extends U> m){Objects.requireNonNull(m);return value==null?Optional.<U>empty():Optional.<U>ofNullable(m.apply(value));}
    @SuppressWarnings("unchecked") public <U> Optional<U> flatMap(Function<? super T,? extends Optional<? extends U>> m){
        Objects.requireNonNull(m);return value==null?Optional.<U>empty():Objects.requireNonNull((Optional<U>)m.apply(value));}
    @SuppressWarnings("unchecked") public Optional<T> or(Supplier<? extends Optional<? extends T>> s){
        Objects.requireNonNull(s);return value!=null?this:Objects.requireNonNull((Optional<T>)s.get());}
    public java.util.stream.Stream<T> stream(){return value==null?java.util.stream.Stream.<T>empty():java.util.stream.Stream.of(value);}
    public T orElse(T other){return value!=null?value:other;}
    public T orElseGet(Supplier<? extends T> s){return value!=null?value:s.get();}
    public T orElseThrow(){return get();}
    public <X extends Throwable> T orElseThrow(Supplier<? extends X> s) throws X{if(value!=null)return value;throw s.get();}
    public boolean equals(Object o){return o==this||o instanceof Optional&&Objects.equals(value,((Optional<?>)o).value);}
    public int hashCode(){return Objects.hashCode(value);}
    public String toString(){return value!=null?"Optional["+value+"]":"Optional.empty";}
}

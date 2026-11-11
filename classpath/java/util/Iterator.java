package java.util;
import java.util.function.Consumer;
public interface Iterator<E> {
    boolean hasNext(); E next();
    default void remove() {throw new UnsupportedOperationException();}
    default void forEachRemaining(Consumer<? super E> action) {Objects.requireNonNull(action);while(hasNext())action.accept(next());}
}

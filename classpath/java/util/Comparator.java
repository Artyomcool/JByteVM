package java.util;
public interface Comparator<T> {
    int compare(T a,T b);
    default Comparator<T> reversed() {Comparator<T> self=this;return new Comparator<T>(){public int compare(T a,T b){return self.compare(b,a);}};}
    default Comparator<T> thenComparing(Comparator<? super T> other) {Objects.requireNonNull(other);Comparator<T> self=this;return new Comparator<T>(){public int compare(T a,T b){int c=self.compare(a,b);return c==0?other.compare(a,b):c;}};}
    static <T extends Comparable<? super T>> Comparator<T> naturalOrder() {return new Comparator<T>(){public int compare(T a,T b){return a.compareTo(b);}};}
    static <T extends Comparable<? super T>> Comparator<T> reverseOrder() {return Comparator.<T>naturalOrder().reversed();}
    static <T,U extends Comparable<? super U>> Comparator<T> comparing(java.util.function.Function<? super T,? extends U> key) {Objects.requireNonNull(key);return new Comparator<T>(){public int compare(T a,T b){return key.apply(a).compareTo(key.apply(b));}};}
    static <T> Comparator<T> comparingInt(java.util.function.ToIntFunction<? super T> key) {Objects.requireNonNull(key);return new Comparator<T>(){public int compare(T a,T b){return Integer.compare(key.applyAsInt(a),key.applyAsInt(b));}};}
}

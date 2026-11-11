package java.util;
public interface Comparator<T> {
    int compare(T a,T b);
    default Comparator<T> reversed() {Comparator<T> self=this;return new Comparator<T>(){public int compare(T a,T b){return self.compare(b,a);}};}
    default Comparator<T> thenComparing(Comparator<? super T> other) {Objects.requireNonNull(other);Comparator<T> self=this;return new Comparator<T>(){public int compare(T a,T b){int c=self.compare(a,b);return c==0?other.compare(a,b):c;}};}
    static <T extends Comparable<? super T>> Comparator<T> naturalOrder() {return new Comparator<T>(){public int compare(T a,T b){return a.compareTo(b);}};}
    static <T extends Comparable<? super T>> Comparator<T> reverseOrder() {return Comparator.<T>naturalOrder().reversed();}
    static <T,U extends Comparable<? super U>> Comparator<T> comparing(java.util.function.Function<? super T,? extends U> key) {Objects.requireNonNull(key);return new Comparator<T>(){public int compare(T a,T b){return key.apply(a).compareTo(key.apply(b));}};}
    static <T> Comparator<T> comparingInt(java.util.function.ToIntFunction<? super T> key) {Objects.requireNonNull(key);return new Comparator<T>(){public int compare(T a,T b){return Integer.compare(key.applyAsInt(a),key.applyAsInt(b));}};}
    default <U extends Comparable<? super U>> Comparator<T> thenComparing(java.util.function.Function<? super T,? extends U> key) {return thenComparing(comparing(key));}
    default <U> Comparator<T> thenComparing(java.util.function.Function<? super T,? extends U> key,Comparator<? super U> order) {return thenComparing(comparing(key,order));}
    default Comparator<T> thenComparingInt(java.util.function.ToIntFunction<? super T> key) {return thenComparing(comparingInt(key));}
    default Comparator<T> thenComparingLong(java.util.function.ToLongFunction<? super T> key) {return thenComparing(comparingLong(key));}
    default Comparator<T> thenComparingDouble(java.util.function.ToDoubleFunction<? super T> key) {return thenComparing(comparingDouble(key));}
    static <T,U> Comparator<T> comparing(java.util.function.Function<? super T,? extends U> key,Comparator<? super U> order) {Objects.requireNonNull(key);Objects.requireNonNull(order);return new Comparator<T>(){public int compare(T a,T b){return order.compare(key.apply(a),key.apply(b));}};}
    static <T> Comparator<T> comparingLong(java.util.function.ToLongFunction<? super T> key) {Objects.requireNonNull(key);return new Comparator<T>(){public int compare(T a,T b){return Long.compare(key.applyAsLong(a),key.applyAsLong(b));}};}
    static <T> Comparator<T> comparingDouble(java.util.function.ToDoubleFunction<? super T> key) {Objects.requireNonNull(key);return new Comparator<T>(){public int compare(T a,T b){return Double.compare(key.applyAsDouble(a),key.applyAsDouble(b));}};}
    static <T> Comparator<T> nullsFirst(Comparator<? super T> order) {return nulls(order,-1);}
    static <T> Comparator<T> nullsLast(Comparator<? super T> order) {return nulls(order,1);}
    private static <T> Comparator<T> nulls(Comparator<? super T> order,int sign) {return new Comparator<T>(){public int compare(T a,T b){if(a==null)return b==null?0:sign;if(b==null)return -sign;return order==null?0:order.compare(a,b);}};}
}

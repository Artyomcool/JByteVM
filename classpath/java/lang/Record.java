package java.lang;
public abstract class Record {
    protected Record() {}
    @Override public abstract boolean equals(Object other);
    @Override public abstract int hashCode();
    @Override public abstract String toString();
}

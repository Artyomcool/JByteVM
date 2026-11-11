package java.util;
public final class IllegalFormatArgumentIndexException extends IllegalFormatException {
    public IllegalFormatArgumentIndexException(int i) { super(i==Integer.MIN_VALUE?"Format argument index: (not representable as int)":"Illegal format argument index = "+i); }
}

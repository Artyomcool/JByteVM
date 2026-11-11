package java.util;
public class IllegalFormatPrecisionException extends IllegalFormatException {
    public IllegalFormatPrecisionException(int p) { super(Integer.toString(p)); }
}

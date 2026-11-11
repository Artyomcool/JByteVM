package java.util;
public class IllegalFormatWidthException extends IllegalFormatException {
    public IllegalFormatWidthException(int w) { super(Integer.toString(w)); }
}

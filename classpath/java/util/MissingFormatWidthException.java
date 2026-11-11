package java.util;
public class MissingFormatWidthException extends IllegalFormatException {
    public MissingFormatWidthException(String s) { super(Objects.requireNonNull(s)); }
}

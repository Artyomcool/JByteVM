package java.util;
public class UnknownFormatConversionException extends IllegalFormatException {
    public UnknownFormatConversionException(String s) { super("Conversion = '"+Objects.requireNonNull(s)+"'"); }
}

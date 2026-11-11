package java.util;
public class IllegalFormatConversionException extends IllegalFormatException {
    public IllegalFormatConversionException(char c, Class<?> arg) { super(c+" != "+arg.getName()); }
}

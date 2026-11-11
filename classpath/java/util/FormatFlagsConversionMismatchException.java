package java.util;
public class FormatFlagsConversionMismatchException extends IllegalFormatException {
    public FormatFlagsConversionMismatchException(String f, char c) { super("Conversion = "+c+", Flags = "+Objects.requireNonNull(f)); }
}

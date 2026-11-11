package java.util;
public class IllegalFormatFlagsException extends IllegalFormatException {
    public IllegalFormatFlagsException(String f) { super("Flags = '"+Objects.requireNonNull(f)+"'"); }
}

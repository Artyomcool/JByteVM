package java.util;
public class DuplicateFormatFlagsException extends IllegalFormatException {
    public DuplicateFormatFlagsException(String f) { super("Flags = '"+Objects.requireNonNull(f)+"'"); }
}

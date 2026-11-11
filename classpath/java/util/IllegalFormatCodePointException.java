package java.util;
public class IllegalFormatCodePointException extends IllegalFormatException {
    public IllegalFormatCodePointException(int c) { super("Code point = 0x"+Integer.toHexString(c)); }
}

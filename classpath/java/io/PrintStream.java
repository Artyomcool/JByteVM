package java.io;
public class PrintStream implements AutoCloseable, Appendable {
    private final boolean error;
    private boolean closed,failed;
    public PrintStream(boolean error) { this.error=error; }
    private void emit(String text) { if(closed){failed=true;return;} jbv.runtime.Support.write(text,error); }
    public void print(String value) { emit(value==null?"null":value); }
    public void print(Object value) { print(String.valueOf(value)); }
    public void print(char[] value) { print(String.valueOf(value)); }
    public void print(char value) { print(String.valueOf(value)); }
    public void print(boolean value) { print(String.valueOf(value)); }
    public void print(int value) { print(String.valueOf(value)); }
    public void print(long value) { print(String.valueOf(value)); }
    public void print(float value) { print(String.valueOf(value)); }
    public void print(double value) { print(String.valueOf(value)); }
    public void println() { print(System.lineSeparator()); }
    public void println(String value) { print(value);println(); }
    public void println(Object value) { print(value);println(); }
    public void println(char[] value) { print(value);println(); }
    public void println(char value) { print(value);println(); }
    public void println(boolean value) { print(value);println(); }
    public void println(int value) { print(value);println(); }
    public void println(long value) { print(value);println(); }
    public void println(float value) { print(value);println(); }
    public void println(double value) { print(value);println(); }
    public PrintStream append(char value) { print(value);return this; }
    public PrintStream append(CharSequence value) { print(value==null?"null":value.toString());return this; }
    public PrintStream append(CharSequence value,int start,int end) { if(value==null)value="null"; return append(value.subSequence(start,end)); }
    public void flush() {}
    public void close() { closed=true; }
    public boolean checkError() { return failed; }
}

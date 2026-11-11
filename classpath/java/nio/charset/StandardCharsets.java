package java.nio.charset;
public final class StandardCharsets {
    private StandardCharsets() {}
    public static final Charset UTF_8 = Charset.of(0), ISO_8859_1 = Charset.of(1), US_ASCII = Charset.of(2),
        UTF_16 = Charset.of(3), UTF_16BE = Charset.of(4), UTF_16LE = Charset.of(5);
}

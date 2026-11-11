package p20;
public final class Main {
    static int fnv(String s) { int h = 0x811c9dc5; for (int i = 0; i < s.length(); i++) { h ^= s.charAt(i); h *= 0x01000193; } return h; }
    static int crc32(byte[] data) { int crc = ~0; for (byte b : data) { crc ^= b & 0xff; for (int k = 0; k < 8; k++) crc = (crc >>> 1) ^ (0xEDB88320 & -(crc & 1)); } return ~crc; }
    static long xorshift(long x) { x ^= x << 13; x ^= x >>> 7; x ^= x << 17; return x; }
    public static String run() {
        long x = 88172645463325252L; for (int i = 0; i < 1000; i++) x = xorshift(x);
        byte[] bytes = "JByteVM mods".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        int packed = (3 << 24) | (200 << 16) | (17 << 8) | 255;
        return Integer.toHexString(fnv("hello")) + " " + Integer.toHexString(crc32(bytes)) + " " + Long.toHexString(x) + " " + Long.toBinaryString(5L) + " "
            + Integer.bitCount(packed) + " " + Integer.numberOfLeadingZeros(1 << 20) + " " + Integer.reverse(1) + " " + Integer.toUnsignedString(-1) + " "
            + Long.divideUnsigned(-1L, 3) + " " + Integer.compareUnsigned(-1, 1) + " " + ((packed >>> 16) & 0xff) + " " + (byte) (packed >> 8) + " " + Long.rotateLeft(1L, 65) + " " + Integer.parseInt("-ff", 16) + " " + Integer.toString(255, 2);
    }
}

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/** Raw class-file checks for the build: constant-pool tags (no invokedynamic/condy) and the
 * embedded library's images without verifier stack maps. Not a verifier. */
final class ClassFiles {
    /** Whether the constant pool has an entry with this tag (18 invokedynamic, 17 dynamic). */
    static boolean hasConstant(byte[] data, int wanted) {
        if (data.length < 10 || (data[0] & 0xFF) != 0xCA || (data[1] & 0xFF) != 0xFE || (data[2] & 0xFF) != 0xBA || (data[3] & 0xFF) != 0xBE)
            throw new IllegalArgumentException("not a class file");
        int count = u16(data, 8);
        if (count == 0) throw new IllegalArgumentException("empty constant pool");
        int index = 1, pos = 10;
        while (index < count) {
            if (pos >= data.length) throw new IllegalArgumentException("truncated constant pool");
            int tag = data[pos++] & 0xFF;
            if (tag == wanted) return true;
            switch (tag) {
                case 1 -> { if (pos + 2 > data.length) throw new IllegalArgumentException("truncated UTF8 length"); pos += 2 + u16(data, pos); }
                case 3, 4, 9, 10, 11, 12, 17, 18 -> pos += 4;
                case 5, 6 -> { pos += 8; if (++index >= count) throw new IllegalArgumentException("missing second constant pool slot"); }
                case 7, 8, 16, 19, 20 -> pos += 2;
                case 15 -> pos += 3;
                default -> throw new IllegalArgumentException("unknown constant pool tag " + tag);
            }
            if (pos > data.length) throw new IllegalArgumentException("truncated constant pool entry");
            index++;
        }
        return false;
    }
    static boolean hasIndy(byte[] data) { return hasConstant(data, 18); }

    /** The class with every StackMapTable dropped; everything else byte for byte. */
    static byte[] withoutStackMaps(byte[] data) {
        Map<Integer, String> utf = new HashMap<>();
        int count = u16(data, 8), index = 1, pos = 10;
        while (index < count) {
            int tag = data[pos++] & 0xFF;
            if (tag == 1) { int size = u16(data, pos); utf.put(index, new String(data, pos + 2, size, StandardCharsets.ISO_8859_1)); pos += 2 + size; }
            else if (tag == 5 || tag == 6) { pos += 8; index++; }
            else pos += switch (tag) { case 3, 4, 9, 10, 11, 12, 17, 18 -> 4; case 7, 8, 16, 19, 20 -> 2; case 15 -> 3; default -> throw new IllegalArgumentException("tag " + tag); };
            index++;
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        pos += 6;
        pos += 2 + 2 * u16(data, pos);
        out.write(data, 0, pos);
        int[] at = {pos};
        for (int kind = 0; kind < 2; kind++) {   // fields, then methods
            int members = u16(data, at[0]);
            out.write(data, at[0], 2); at[0] += 2;
            for (int i = 0; i < members; i++) { out.write(data, at[0], 6); at[0] += 6; out.writeBytes(attributes(data, at, utf, false)); }
        }
        out.writeBytes(attributes(data, at, utf, false));
        if (at[0] != data.length) throw new IllegalArgumentException("Invalid class image");
        return out.toByteArray();
    }
    static byte[] attributes(byte[] data, int[] at, Map<Integer, String> utf, boolean code) {
        int total = u16(data, at[0]); at[0] += 2;
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        int kept = 0;
        for (int i = 0; i < total; i++) {
            int name = u16(data, at[0]), size = ByteBuffer.wrap(data, at[0] + 2, 4).getInt(), offset = at[0] + 6, end = offset + size;
            at[0] = end;
            if (code && "StackMapTable".equals(utf.get(name))) continue;
            byte[] body;
            if ("Code".equals(utf.get(name))) {
                int p = offset + 8 + ByteBuffer.wrap(data, offset + 4, 4).getInt();
                p += 2 + 8 * u16(data, p);
                int[] nestedAt = {p};
                byte[] nested = attributes(data, nestedAt, utf, true);
                if (nestedAt[0] != end) throw new IllegalArgumentException("Invalid Code attribute");
                ByteArrayOutputStream b = new ByteArrayOutputStream();
                b.write(data, offset, p - offset); b.writeBytes(nested);
                body = b.toByteArray();
            } else body = java.util.Arrays.copyOfRange(data, offset, end);
            result.write(name >>> 8); result.write(name);
            result.writeBytes(ByteBuffer.allocate(4).putInt(body.length).array());
            result.writeBytes(body);
            kept++;
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(kept >>> 8); out.write(kept);
        out.writeBytes(result.toByteArray());
        return out.toByteArray();
    }
    static int u16(byte[] d, int at) { return (d[at] & 0xFF) << 8 | d[at + 1] & 0xFF; }
}

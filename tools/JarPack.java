import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.zip.CRC32;

/** A minimal, deterministic JAR (plain ZIP: no extra fields, no comments, fixed timestamps).
 * Entries are LZMA (ZIP method 14), or stored when that is not smaller: what JByteVM reads.
 * All classes go into one solid entry, jbv/classes.bin. */
final class JarPack {
    static final int DOS_TIME = 0, DOS_DATE = (2026 - 1980) << 9 | 1 << 5 | 1;
    static final String CLASSES = "jbv/classes.bin";

    /** ZIP method 14: version, props size 5, props (lc/lp/pb, dictionary size), the raw stream.
     * The smallest of a few lc/pb choices, checked by decoding it again. */
    static byte[] lzma(byte[] data) {
        int dictionary = 1 << Math.max(12, 32 - Integer.numberOfLeadingZeros(Math.max(0, data.length - 1)));
        byte[] best = null;
        for (int lc = 0; lc <= 4; lc++) for (int pb : new int[] {0, 2}) {
            byte[] raw = Lzma.compress(data, lc, 0, pb, dictionary);
            if (best != null && raw.length + 9 >= best.length) continue;
            ByteBuffer b = ByteBuffer.allocate(raw.length + 9).order(ByteOrder.LITTLE_ENDIAN);
            b.put((byte) 9).put((byte) 20).put((byte) 5).put((byte) 0).put((byte) ((pb * 5) * 9 + lc)).putInt(dictionary).put(raw);
            best = b.array();
        }
        int props = best[4] & 0xFF;
        byte[] back = Lzma.decompress(best, 9, props % 9, props / 9 % 5, props / 45, data.length);
        if (!java.util.Arrays.equals(back, data)) throw new IllegalStateException("LZMA self-check failed");
        return best;
    }

    /** classes: (internal name, bytes). Sorted by name: neighbours share the most strings.
     * u32 count, count x {u32 offset, u32 size, u8 length, name}, then the images. */
    static byte[] classesBlob(List<Map.Entry<String, byte[]>> classes) {
        classes = new ArrayList<>(classes);
        classes.sort(Map.Entry.comparingByKey());
        HashSet<String> seen = new HashSet<>();
        int offset = 4;
        for (var c : classes) {
            if (!seen.add(c.getKey())) throw new IllegalArgumentException("Duplicate class in one JAR.");
            int length = c.getKey().getBytes(StandardCharsets.UTF_8).length;
            if (length > 255) throw new IllegalArgumentException("Class name too long: " + c.getKey());
            offset += 9 + length;
        }
        ByteArrayOutputStream index = new ByteArrayOutputStream(), images = new ByteArrayOutputStream();
        index.writeBytes(le(classes.size()));
        for (var c : classes) {
            byte[] name = c.getKey().getBytes(StandardCharsets.UTF_8);
            index.writeBytes(le(offset)); index.writeBytes(le(c.getValue().length)); index.write(name.length); index.writeBytes(name);
            images.writeBytes(c.getValue());
            offset += c.getValue().length;
        }
        index.writeBytes(images.toByteArray());
        return index.toByteArray();
    }

    /** A JByteVM JAR: all classes in one solid entry, resources as ordinary entries (sorted). */
    static byte[] packClasses(List<Map.Entry<String, byte[]>> classes, List<Map.Entry<String, byte[]>> resources) {
        List<Map.Entry<String, byte[]>> entries = new ArrayList<>();
        entries.add(Map.entry(CLASSES, classesBlob(classes)));
        List<Map.Entry<String, byte[]>> sorted = new ArrayList<>(resources);
        sorted.sort(Map.Entry.comparingByKey(Comparator.naturalOrder()));
        entries.addAll(sorted);
        return pack(entries);
    }

    static byte[] pack(List<Map.Entry<String, byte[]>> entries) {
        ByteArrayOutputStream local = new ByteArrayOutputStream(), central = new ByteArrayOutputStream();
        for (var e : entries) {
            byte[] raw = e.getKey().getBytes(StandardCharsets.UTF_8), data = e.getValue(), packed = lzma(data);
            int method = 14;
            if (packed.length >= data.length) { packed = data; method = 0; }
            CRC32 crc = new CRC32(); crc.update(data);
            ByteBuffer head = ByteBuffer.allocate(22).order(ByteOrder.LITTLE_ENDIAN);
            head.putShort((short) (method == 14 ? 63 : 20)).putShort((short) (method == 14 ? 0x802 : 0x800)).putShort((short) method)
                .putShort((short) DOS_TIME).putShort((short) DOS_DATE).putInt((int) crc.getValue()).putInt(packed.length).putInt(data.length);
            ByteBuffer c = ByteBuffer.allocate(46 + raw.length).order(ByteOrder.LITTLE_ENDIAN);
            c.putInt(0x02014b50).putShort((short) 20).put(head.array()).putShort((short) raw.length).putShort((short) 0).putShort((short) 0)
                .putShort((short) 0).putShort((short) 0).putInt(0).putInt(local.size()).put(raw);
            central.writeBytes(c.array());
            ByteBuffer l = ByteBuffer.allocate(30 + raw.length).order(ByteOrder.LITTLE_ENDIAN);
            l.putInt(0x04034b50).put(head.array()).putShort((short) raw.length).putShort((short) 0).put(raw);
            local.writeBytes(l.array());
            local.writeBytes(packed);
        }
        ByteBuffer end = ByteBuffer.allocate(22).order(ByteOrder.LITTLE_ENDIAN);
        end.putInt(0x06054b50).putShort((short) 0).putShort((short) 0).putShort((short) entries.size()).putShort((short) entries.size())
            .putInt(central.size()).putInt(local.size()).putShort((short) 0);
        local.writeBytes(central.toByteArray());
        local.writeBytes(end.array());
        return local.toByteArray();
    }

    /** The entries of a JAR this class wrote (or any stored/LZMA ZIP): name -> bytes, in order. */
    static List<Map.Entry<String, byte[]>> read(byte[] jar) {
        ByteBuffer b = ByteBuffer.wrap(jar).order(ByteOrder.LITTLE_ENDIAN);
        int eocd = jar.length - 22;
        while (eocd >= 0 && b.getInt(eocd) != 0x06054b50) eocd--;
        if (eocd < 0) throw new IllegalArgumentException("Not a ZIP archive.");
        int count = b.getShort(eocd + 10) & 0xFFFF, at = b.getInt(eocd + 16);
        List<Map.Entry<String, byte[]>> result = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            if (b.getInt(at) != 0x02014b50) throw new IllegalArgumentException("Bad central directory.");
            int method = b.getShort(at + 10) & 0xFFFF, packedSize = b.getInt(at + 20), size = b.getInt(at + 24);
            int nameLength = b.getShort(at + 28) & 0xFFFF, extra = b.getShort(at + 30) & 0xFFFF, comment = b.getShort(at + 32) & 0xFFFF;
            int localAt = b.getInt(at + 42);
            String name = new String(jar, at + 46, nameLength, StandardCharsets.UTF_8);
            int data = localAt + 30 + (b.getShort(localAt + 26) & 0xFFFF) + (b.getShort(localAt + 28) & 0xFFFF);
            byte[] value;
            if (method == 0) value = java.util.Arrays.copyOfRange(jar, data, data + size);
            else if (method == 14) {
                int props = jar[data + 4] & 0xFF;
                value = Lzma.decompress(jar, data + 9, props % 9, props / 9 % 5, props / 45, size);
            } else throw new IllegalArgumentException(name + ": only stored and LZMA entries are supported.");
            if (packedSize < 0) throw new IllegalArgumentException("Bad entry size.");
            result.add(Map.entry(name, value));
            at += 46 + nameLength + extra + comment;
        }
        return result;
    }

    /** Expand a JByteVM JAR into a plain class directory (for HotSpot and tools). */
    static void unpack(Path jar, Path directory) throws IOException {
        for (var e : read(Files.readAllBytes(jar))) {
            if (!e.getKey().equals(CLASSES)) { write(directory.resolve(e.getKey()), e.getValue()); continue; }
            ByteBuffer d = ByteBuffer.wrap(e.getValue()).order(ByteOrder.LITTLE_ENDIAN);
            int count = d.getInt(0), at = 4;
            for (int i = 0; i < count; i++) {
                int offset = d.getInt(at), size = d.getInt(at + 4), length = e.getValue()[at + 8] & 0xFF;
                String name = new String(e.getValue(), at + 9, length, StandardCharsets.UTF_8);
                at += 9 + length;
                write(directory.resolve(name + ".class"), java.util.Arrays.copyOfRange(e.getValue(), offset, offset + size));
            }
        }
    }
    static void write(Path path, byte[] data) throws IOException { Files.createDirectories(path.getParent()); Files.write(path, data); }
    static byte[] le(int v) { return new byte[] {(byte) v, (byte) (v >>> 8), (byte) (v >>> 16), (byte) (v >>> 24)}; }
}

/* Minimal JAR (ZIP) reader with a raw DEFLATE decoder (RFC 1950/1951 subset:
 * stored and deflated entries, no ZIP64, no encryption). Size over speed:
 * it only runs when a class is loaded. Every read is bounds-checked, so a
 * damaged archive yields JBV_BAD_CLASS instead of undefined behaviour. */
#include "jar.h"

typedef struct Huff { uint16_t count[16], symbol[288]; } Huff;
typedef struct Bits { const uint8_t *in, *end; uint8_t *out; size_t pos, size; uint32_t bits, n; int bad; } Bits;

static uint32_t get(Bits *b, uint32_t n) {
    uint32_t v;
    while (b->n < n) {
        if (b->in == b->end) { b->bad = 1; return 0; }
        b->bits |= (uint32_t)*b->in++ << b->n; b->n += 8;
    }
    v = b->bits & ((1u << n) - 1); b->bits >>= n; b->n -= n;
    return v;
}
/* Canonical Huffman table; over-subscribed sets are rejected. */
static int build(Huff *h, const uint8_t *length, uint32_t n) {
    uint16_t offset[16];
    uint32_t i;
    int left = 1;
    for (i = 0; i < 16; ++i) h->count[i] = 0;
    for (i = 0; i < n; ++i) h->count[length[i]]++;
    for (i = 1; i < 16; ++i) { left = (left << 1) - h->count[i]; if (left < 0) return 0; }
    offset[1] = 0;
    for (i = 1; i < 15; ++i) offset[i + 1] = (uint16_t)(offset[i] + h->count[i]);
    for (i = 0; i < n; ++i) if (length[i]) h->symbol[offset[length[i]]++] = (uint16_t)i;
    return 1;
}
static uint32_t decode(Bits *b, const Huff *h) {
    int code = 0, first = 0, index = 0, length, count;
    for (length = 1; length < 16; ++length) {
        code |= (int)get(b, 1);
        count = h->count[length];
        if (code - count < first) return h->symbol[index + code - first];
        index += count; first = (first + count) << 1; code <<= 1;
    }
    b->bad = 1; return 0;
}
static void put(Bits *b, uint8_t value) { if (b->pos < b->size) b->out[b->pos++] = value; else b->bad = 1; }
static void codes(Bits *b, const Huff *lit, const Huff *dist) {
    uint32_t symbol, length, extra, distance;
    while (!b->bad) {
        symbol = decode(b, lit);
        if (symbol < 256) { put(b, (uint8_t)symbol); continue; }
        if (symbol == 256) return;
        symbol -= 257;
        if (symbol >= 29) { b->bad = 1; return; }
        if (symbol < 8) length = symbol + 3;
        else if (symbol == 28) length = 258;
        else { extra = (symbol >> 2) - 1; length = ((4 + (symbol & 3)) << extra) + 3 + get(b, extra); }
        symbol = decode(b, dist);
        if (symbol >= 30) { b->bad = 1; return; }
        if (symbol < 4) distance = symbol + 1;
        else { extra = (symbol >> 1) - 1; distance = ((2 + (symbol & 1)) << extra) + 1 + get(b, extra); }
        if (distance > b->pos || length > b->size - b->pos) { b->bad = 1; return; }
        while (length--) { b->out[b->pos] = b->out[b->pos - distance]; b->pos++; }
    }
}
static JbvStatus inflate(const uint8_t *in, size_t in_size, uint8_t *out, size_t out_size) {
    static const uint8_t order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
    Bits b;
    Huff lit, dist;
    uint8_t length[320];
    uint32_t last, type, i, nlit, ndist, ncode, symbol, repeat, value;
    b.in = in; b.end = in + in_size; b.out = out; b.pos = 0; b.size = out_size; b.bits = 0; b.n = 0; b.bad = 0;
    do {
        last = get(&b, 1); type = get(&b, 2);
        if (type == 0) {
            b.bits = 0; b.n = 0;
            if (b.end - b.in < 4) return JBV_BAD_CLASS;
            i = b.in[0] | (uint32_t)b.in[1] << 8;
            if ((i ^ (b.in[2] | (uint32_t)b.in[3] << 8)) != 0xffff) return JBV_BAD_CLASS;
            b.in += 4;
            if ((size_t)(b.end - b.in) < i) return JBV_BAD_CLASS;
            while (i--) put(&b, *b.in++);
        } else if (type == 1) {
            for (i = 0; i < 288; ++i) length[i] = (uint8_t)(i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8);
            for (i = 0; i < 30; ++i) length[288 + i] = 5;
            build(&lit, length, 288); build(&dist, length + 288, 30);
            codes(&b, &lit, &dist);
        } else if (type == 2) {
            nlit = get(&b, 5) + 257; ndist = get(&b, 5) + 1; ncode = get(&b, 4) + 4;
            if (nlit > 286 || ndist > 30) return JBV_BAD_CLASS;
            for (i = 0; i < 19; ++i) length[order[i]] = (uint8_t)(i < ncode ? get(&b, 3) : 0);
            if (!build(&lit, length, 19)) return JBV_BAD_CLASS;
            for (i = 0; i < nlit + ndist && !b.bad;) {
                symbol = decode(&b, &lit);
                if (symbol < 16) { length[i++] = (uint8_t)symbol; continue; }
                if (symbol == 16) { if (!i) return JBV_BAD_CLASS; value = length[i - 1]; repeat = 3 + get(&b, 2); }
                else { value = 0; repeat = symbol == 17 ? 3 + get(&b, 3) : 11 + get(&b, 7); }
                if (i + repeat > nlit + ndist) return JBV_BAD_CLASS;
                while (repeat--) length[i++] = (uint8_t)value;
            }
            if (b.bad || !length[256] || !build(&lit, length, nlit) || !build(&dist, length + nlit, ndist)) return JBV_BAD_CLASS;
            codes(&b, &lit, &dist);
        } else return JBV_BAD_CLASS;
    } while (!last && !b.bad);
    return b.bad || b.pos != out_size ? JBV_BAD_CLASS : JBV_OK;
}

static uint32_t le16(const uint8_t *p) { return p[0] | (uint32_t)p[1] << 8; }
static uint32_t le32(const uint8_t *p) { return le16(p) | le16(p + 2) << 16; }

JbvStatus jbv_jar_read(JbvVM *vm, const uint8_t *jar, size_t size, JbvText name, const char *suffix, uint8_t **out, size_t *out_size) {
    const uint8_t *eocd, *entry, *local, *end;
    uint32_t count, method, packed, plain, length, offset, i, k;
    size_t tail = 0;
    uint8_t *data;
    JbvStatus status;
    while (suffix[tail]) ++tail;
    if (size < 22) return JBV_BAD_CLASS;
    /* End of central directory: last signature, the comment may follow it. */
    for (eocd = jar + size - 22; le32(eocd) != 0x06054b50; --eocd) if (eocd == jar) return JBV_BAD_CLASS;
    count = le16(eocd + 10); offset = le32(eocd + 16); end = eocd;
    if (offset > (size_t)(eocd - jar)) return JBV_BAD_CLASS;
    for (entry = jar + offset; count--; entry += 46 + length + le16(entry + 30) + le16(entry + 32)) {
        if (end - entry < 46 || le32(entry) != 0x02014b50) return JBV_BAD_CLASS;
        length = le16(entry + 28);
        if ((size_t)(end - entry - 46) < length) return JBV_BAD_CLASS;
        if (length != name.size + tail) continue;
        for (k = 0; k < name.size && entry[46 + k] == name.data[k]; ++k) {}
        if (k < name.size) continue;
        for (i = 0; i < tail && entry[46 + k + i] == (uint8_t)suffix[i]; ++i) {}
        if (i < tail) continue;
        if (!out) return JBV_OK;
        method = le16(entry + 10); packed = le32(entry + 20); plain = le32(entry + 24); offset = le32(entry + 42);
        if (offset > size || size - offset < 30 || le32(jar + offset) != 0x04034b50 || (method != 0 && method != 8)) return JBV_BAD_CLASS;
        local = jar + offset + 30 + le16(jar + offset + 26) + le16(jar + offset + 28);
        if (local > jar + size || (size_t)(jar + size - local) < packed || (method == 0 && packed != plain)) return JBV_BAD_CLASS;
        data = (uint8_t *)jbv_alloc(vm, plain);
        if (!data) return JBV_OUT_OF_MEMORY;
        if (method == 8) status = inflate(local, packed, data, plain);
        else { for (i = 0; i < plain; ++i) data[i] = local[i]; status = JBV_OK; }
        if (status != JBV_OK) { jbv_free(vm, data); return status; }
        *out = data; *out_size = plain;
        return JBV_OK;
    }
    return JBV_NOT_FOUND;
}

/* jbv/classes.bin: u32 count, count x {u32 offset, u32 size, u8 length, name}, class images. */
JbvStatus jbv_archive_open(JbvVM *vm, JbvArchive *archive, const uint8_t *jar, size_t size) {
    JbvStatus status = jbv_jar_read(vm, jar, size, jbv_text("jbv/classes"), ".bin", &archive->data, &archive->size);
    return status == JBV_NOT_FOUND ? JBV_BAD_CLASS : status;
}
JbvStatus jbv_archive_find(const JbvArchive *archive, JbvText name, const uint8_t **data, uint32_t *size) {
    const uint8_t *p = archive->data;
    size_t at = 4, total = archive->size;
    uint32_t count, length, k;
    if (!p) return JBV_NOT_FOUND;
    if (total < 4) return JBV_BAD_CLASS;
    for (count = le32(p); count--; at += 9 + length) {
        if (total - at < 9 || total - at - 9 < (length = p[at + 8])) return JBV_BAD_CLASS;
        if (length != name.size) continue;
        for (k = 0; k < length && p[at + 9 + k] == name.data[k]; ++k) {}
        if (k < length) continue;
        k = le32(p + at);
        if (k > total || le32(p + at + 4) > total - k) return JBV_BAD_CLASS;
        if (data) { *data = p + k; *size = le32(p + at + 4); }
        return JBV_OK;
    }
    return JBV_NOT_FOUND;
}

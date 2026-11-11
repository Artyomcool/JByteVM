/* Minimal JAR (ZIP) reader for JARs made by tools/prepare.py and the embedded
 * library: stored and LZMA (method 14) entries, no ZIP64, no encryption. Size over speed:
 * it only runs when a class is loaded. Every read is bounds-checked, so a
 * damaged archive yields JBV_BAD_CLASS instead of undefined behaviour. */
#include "jar.h"

/* LZMA1 (ZIP method 14: u8 version[2], u16 props size = 5, props, then the stream),
 * after the LZMA specification. Probabilities: one block of 11-bit counters. */
typedef struct Rc { const uint8_t *in, *end; uint32_t range, code; } Rc;
static uint32_t rc_bit(Rc *r, uint16_t *p) {
    uint32_t bound = (r->range >> 11) * *p, bit = r->code >= bound;
    if (bit) { r->range -= bound; r->code -= bound; *p -= *p >> 5; } else { r->range = bound; *p += (2048 - *p) >> 5; }
    if (r->range < (1u << 24)) { r->range <<= 8; r->code = r->code << 8 | (r->in < r->end ? *r->in++ : 0); }
    return bit;
}
static uint32_t rc_tree(Rc *r, uint16_t *p, uint32_t n, int reverse) {
    uint32_t m = 1, sym = 0, i, bit;
    for (i = 0; i < n; ++i) { bit = rc_bit(r, p + m); m = m << 1 | bit; sym |= bit << i; }
    return reverse ? sym : m - (1u << n);
}
static uint32_t rc_len(Rc *r, uint16_t *p, uint32_t pos_state) {   /* choice, choice2, low[16][8], mid[16][8], high[256] */
    if (!rc_bit(r, p)) return rc_tree(r, p + 2 + pos_state * 8, 3, 0);
    if (!rc_bit(r, p + 1)) return 8 + rc_tree(r, p + 130 + pos_state * 8, 3, 0);
    return 16 + rc_tree(r, p + 258, 8, 0);
}
enum { L_MATCH = 0, L_REP = 192, L_G0 = 204, L_G1 = 216, L_G2 = 228, L_LONG = 240, L_SLOT = 432, L_SPEC = 688, L_ALIGN = 803,
       L_LEN = 819, L_REPLEN = 1333, L_LIT = 1847 };
static JbvStatus unlzma(JbvVM *vm, const uint8_t *in, size_t in_size, uint8_t *out, size_t size) {
    Rc r;
    uint16_t *p;
    uint32_t lc, lp, pb, n, i, state = 0, rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0, len, dist;
    size_t pos = 0;
    if (in_size < 9 + 5 || in[2] != 5 || in[3] || in[4] >= 9 * 5 * 5 || in[9]) return JBV_BAD_CLASS;
    lc = in[4] % 9; lp = in[4] / 9 % 5; pb = in[4] / 45;
    if (lc + lp > 8) return JBV_BAD_CLASS;
    n = L_LIT + (0x300u << (lc + lp));
    p = (uint16_t *)jbv_alloc(vm, n * sizeof(uint16_t));
    if (!p) return JBV_OUT_OF_MEMORY;
    for (i = 0; i < n; ++i) p[i] = 1024;
    r.in = in + 10; r.end = in + in_size; r.range = 0xffffffffu; r.code = 0;
    for (i = 0; i < 4; ++i) r.code = r.code << 8 | (r.in < r.end ? *r.in++ : 0);
    while (pos < size) {
        uint32_t ps = (uint32_t)pos & ((1u << pb) - 1);
        if (!rc_bit(&r, p + L_MATCH + (state << 4) + ps)) {   /* literal */
            uint16_t *lit = p + L_LIT + 0x300 * ((((uint32_t)pos & ((1u << lp) - 1)) << lc) + ((pos ? out[pos - 1] : 0u) >> (8 - lc)));
            uint32_t sym = 1;
            if (state >= 7 && pos > rep0) {
                uint32_t match = out[pos - rep0 - 1];
                do {
                    uint32_t mbit = match >> 7 & 1, bit;
                    match <<= 1;
                    bit = rc_bit(&r, lit + ((1 + mbit) << 8) + sym);
                    sym = sym << 1 | bit;
                    if (bit != mbit) break;
                } while (sym < 0x100);
            }
            while (sym < 0x100) sym = sym << 1 | rc_bit(&r, lit + sym);
            out[pos++] = (uint8_t)sym;
            state = state < 4 ? 0 : state < 10 ? state - 3 : state - 6;
            continue;
        }
        if (rc_bit(&r, p + L_REP + state)) {
            if (!pos) break;
            if (!rc_bit(&r, p + L_G0 + state)) {
                if (!rc_bit(&r, p + L_LONG + (state << 4) + ps)) {   /* one byte at rep0 */
                    state = state < 7 ? 9 : 11;
                    if (rep0 >= pos) break;
                    out[pos] = out[pos - rep0 - 1]; ++pos;
                    continue;
                }
            } else {
                if (!rc_bit(&r, p + L_G1 + state)) dist = rep1;
                else { if (!rc_bit(&r, p + L_G2 + state)) dist = rep2; else { dist = rep3; rep3 = rep2; } rep2 = rep1; }
                rep1 = rep0; rep0 = dist;
            }
            len = rc_len(&r, p + L_REPLEN, ps);
            state = state < 7 ? 8 : 11;
        } else {
            uint32_t slot;
            rep3 = rep2; rep2 = rep1; rep1 = rep0;
            len = rc_len(&r, p + L_LEN, ps);
            state = state < 7 ? 7 : 10;
            slot = rc_tree(&r, p + L_SLOT + (len < 3 ? len : 3) * 64, 6, 0);
            if (slot < 4) dist = slot;
            else {
                uint32_t direct = (slot >> 1) - 1;
                dist = (2 | (slot & 1)) << direct;
                if (slot < 14) dist += rc_tree(&r, p + L_SPEC + dist - slot, direct, 1);
                else {
                    for (i = direct - 4; i--;) {   /* direct bits, then 4 aligned */
                        r.range >>= 1;
                        if (r.code >= r.range) { r.code -= r.range; dist += 1u << (i + 4); }
                        if (r.range < (1u << 24)) { r.range <<= 8; r.code = r.code << 8 | (r.in < r.end ? *r.in++ : 0); }
                    }
                    dist += rc_tree(&r, p + L_ALIGN, 4, 1);
                    if (dist == 0xffffffffu) break;   /* end marker */
                }
            }
            rep0 = dist;
        }
        if (rep0 >= pos) break;
        for (len += 2; len-- && pos < size; ++pos) out[pos] = out[pos - rep0 - 1];
    }
    jbv_free(vm, p);
    return pos == size ? JBV_OK : JBV_BAD_CLASS;
}

static uint32_t le16(const uint8_t *p) { return p[0] | (uint32_t)p[1] << 8; }
static uint32_t le32(const uint8_t *p) { return le16(p) | le16(p + 2) << 16; }

JbvStatus jbv_jar_read(JbvVM *vm, const uint8_t *jar, size_t size, JbvText name, const char *suffix, uint8_t **out, size_t *out_size, int verify) {
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
        if (offset > size || size - offset < 30 || le32(jar + offset) != 0x04034b50 || (method != 0 && method != 14)) return JBV_BAD_CLASS;
        local = jar + offset + 30 + le16(jar + offset + 26) + le16(jar + offset + 28);
        if (local > jar + size || (size_t)(jar + size - local) < packed || (method == 0 && packed != plain)) return JBV_BAD_CLASS;
        data = (uint8_t *)jbv_alloc(vm, plain);
        if (!data) return JBV_OUT_OF_MEMORY;
        if (method == 14) status = unlzma(vm, local, packed, data, plain);
        else { for (i = 0; i < plain; ++i) data[i] = local[i]; status = JBV_OK; }
        if (status == JBV_OK && verify) {   /* CRC-32 of the entry: catches damage DEFLATE itself cannot see */
            uint32_t crc = 0xffffffffu, bit;
            for (i = 0; i < plain; ++i) { crc ^= data[i]; for (bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u))); }
            if (~crc != le32(entry + 16)) status = JBV_BAD_CLASS;
        }
        if (status != JBV_OK) { jbv_free(vm, data); return status; }
        *out = data; *out_size = plain;
        return JBV_OK;
    }
    return JBV_NOT_FOUND;
}

/* jbv/classes.bin: u32 count, count x {u32 offset, u32 size, u8 length, name}, class images. */
JbvStatus jbv_archive_open(JbvVM *vm, JbvArchive *archive, const uint8_t *jar, size_t size, int verify) {
    JbvStatus status = jbv_jar_read(vm, jar, size, jbv_text("jbv/classes"), ".bin", &archive->data, &archive->size, verify);
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

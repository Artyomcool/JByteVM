#include "library.h"

JbvStatus jbv_string_view(JbvVM *vm, int32_t ref, JbvTextView *out) {
    JbvObject *s, *a;
    JbvStatus status = jbv_object(vm, ref, &s);
    if (status != JBV_OK) return status;
    if (s->type->builtin != B_STRING) return JBV_CLASS_CAST;
    out->data = 0; out->length = 0;
    if (!jbv_data(s)[0]) return JBV_OK;
    status = jbv_object(vm, jbv_data(s)[0], &a);
    if (status == JBV_OK) { out->data = jbv_chars(a); out->length = jbv_length(a); }
    return status;
}
static JbvStatus char_array(JbvVM *vm, uint32_t length, int32_t *ref, uint16_t **data) {
    JbvClass *type;
    JbvObject *o = 0;
    JbvStatus status;
    if (length > INT32_MAX) return JBV_OUT_OF_MEMORY;
    status = jbv_array_class(vm, 0, 'C', &type);
    if (status == JBV_OK) status = jbv_new(vm, type, (int32_t)length, ref);
    if (status == JBV_OK) { (void)jbv_object(vm, *ref, &o); *data = jbv_chars(o); }
    return status;
}
/* Returns a borrowed reference and its backing buffer. No allocation is safe
 * between return and publishing/pinning the reference. Empty strings need no array. */
JbvStatus jbv_string_alloc(JbvVM *vm, uint32_t length, int32_t *ref, uint16_t **data) {
    JbvClass *type;
    JbvObject *s = 0;
    JbvStatus status;
    int32_t value = 0, array;
    *data = 0;
    if (length > INT32_MAX) return JBV_OUT_OF_MEMORY;
    status = jbv_resolve_class(vm, jbv_text("java/lang/String"), &type);
    if (status == JBV_OK) status = jbv_new(vm, type, 0, &value);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm, value);
    if (length) {
        status = char_array(vm, length, &array, data);
        if (status == JBV_OK) { (void)jbv_object(vm, value, &s); jbv_data(s)[0] = array; }
    }
    (void)jbv_release(vm, value);
    if (status == JBV_OK) *ref = value;
    return status;
}
static JbvStatus copy_string(JbvVM *vm, const uint16_t *data, uint32_t n, int32_t *out) {
    uint16_t *to;
    uint32_t i;
    JbvStatus status = jbv_string_alloc(vm, n, out, &to);
    if (status == JBV_OK) for (i = 0; i < n; ++i) to[i] = data[i];
    return status;
}
/* MUTF-8 is supplied by trusted classfiles: NUL is C0 80, supplementary
 * characters are two independently encoded surrogate code units. */
JbvStatus jbv_string_mutf(JbvVM *vm, JbvText text, int32_t *out) {
    uint32_t i, n = 0, ch;
    uint16_t *data;
    JbvStatus status;
    for (i = 0; i < text.size; ++n) i += text.data[i] < 128 ? 1u : text.data[i] < 224 ? 2u : 3u;
    status = jbv_string_alloc(vm, n, out, &data);
    if (status != JBV_OK) return status;
    for (i = n = 0; i < text.size; data[n++] = (uint16_t)ch) {
        ch = text.data[i++];
        if (ch >= 224) { ch = ((ch & 15) << 12) | ((text.data[i] & 63) << 6) | (text.data[i+1] & 63); i += 2; }
        else if (ch >= 128) ch = ((ch & 31) << 6) | (text.data[i++] & 63);
    }
    return JBV_OK;
}
JbvStatus jbv_string_intern(JbvVM *vm, int32_t ref, int32_t *out) {
    JbvTextView text, other;
    JbvObject *o = 0;
    uint32_t i, j;
    JbvStatus status = jbv_string_view(vm, ref, &text);
    if (status != JBV_OK) return status;
    for (i = 1; i <= vm->handle_capacity; ++i) {
        if (!jbv_bit(vm->interned, i)) continue;
        (void)jbv_string_view(vm, (int32_t)jbv_handle_ref(vm, i), &other);
        if (text.length != other.length) continue;
        for (j = 0; j < text.length && text.data[j] == other.data[j]; ++j) {}
        if (j == text.length) { *out = (int32_t)jbv_handle_ref(vm, i); return JBV_OK; }
    }
    (void)o; i = (uint32_t)ref & JBV_HANDLE_MASK; vm->interned[i >> 5] |= 1u << (i & 31); *out = ref; return JBV_OK;
}
JbvStatus jbv_object_text(JbvVM *vm, int32_t ref, int32_t *out) {
    JbvMethodId id;
    JbvObject *o;
    JbvClass *owner;
    uint64_t result;
    JbvStatus status;
    if (!ref) return jbv_string_mutf(vm, jbv_text("null"), out);
    status = jbv_object(vm, ref, &o);
    if (status != JBV_OK) return status;
    owner = o->type;
    id.method = jbv_lookup_method(&owner, jbv_text("toString"), jbv_text("()Ljava/lang/String;")); id.owner = owner;
    if (!id.method) return JBV_NOT_FOUND;
    status = jbv_invoke(vm, &id, &ref, 1, &result);
    if (status == JBV_OK) { *out = (int32_t)result; (void)jbv_release(vm, *out); }
    return status;
}
uint32_t jbv_integer_text(uint64_t magnitude, int negative, uint32_t radix, uint16_t *out) {
    uint32_t start = negative ? 1u : 0u, n = start, i;
    if (negative) out[0] = '-';
    do { uint32_t digit = (uint32_t)(magnitude % radix); out[n++] = (uint16_t)(digit < 10 ? '0' + digit : 'a' + digit - 10); magnitude /= radix; } while (magnitude);
    for (i = start; i < (n + start) / 2; ++i) { uint16_t t = out[i]; out[i] = out[n - 1 - i + start]; out[n - 1 - i + start] = t; }
    return n;
}
/* Each formatting function writes at most 32 UTF-16 units into this buffer. */
__declspec(safebuffers)
static JbvStatus value_string(JbvVM *vm, uint8_t kind, const int32_t *a, int32_t *out) {
    uint16_t text[32];
    uint32_t n;
    uint64_t bits;
    if (kind == 'L' || kind == 'O') return jbv_object_text(vm, a[0], out);
    if (kind == 'Z') return jbv_string_mutf(vm, jbv_text(a[0] ? "true" : "false"), out);
    if (kind == 'C') { text[0] = (uint16_t)a[0]; n = 1; }
    else if (kind == 'F' || kind == 'D') n = jbv_decimal_text(jbv_slot_bits(a, kind == 'D' ? JBV_DOUBLE : JBV_FLOAT), kind == 'F', text);
    else {
        int negative = kind == 'J' ? a[1] < 0 : a[0] < 0;
        bits = kind == 'J' ? jbv_slot_bits(a, JBV_LONG) : (uint64_t)(int64_t)a[0];
        n = jbv_integer_text(negative ? 0 - bits : bits, negative, 10, text);
    }
    return copy_string(vm, text, n, out);
}
static JbvStatus string_bounds(JbvVM *vm) {
    return jbv_throw_named(vm, "java/lang/StringIndexOutOfBoundsException", 0, JBV_ARRAY_BOUNDS);
}
static JbvStatus array_view(JbvVM *vm, int32_t ref, JbvTextView *view) {
    JbvObject *o;
    JbvStatus status = jbv_object(vm, ref, &o);
    if (status != JBV_OK) return status;
    if (o->type->array_kind != 'C') return JBV_CLASS_CAST;
    view->data = jbv_chars(o); view->length = jbv_length(o); return JBV_OK;
}
static JbvStatus sequence_string(JbvVM *vm, int32_t ref, int sliced, int32_t start, int32_t end, int32_t *out) {
    JbvObject *o;
    JbvClass *owner;
    JbvMethodId id;
    uint64_t length, ch;
    int32_t args[2], value;
    uint16_t *data;
    uint32_t i;
    JbvTextView text;
    JbvStatus status;
    int pinned = 0;
    if (!ref) {
        status = jbv_string_mutf(vm, jbv_text("null"), &ref);
        if (status != JBV_OK) return status;
        (void)jbv_retain(vm, ref); pinned = 1;
    }
    status = jbv_object(vm, ref, &o);
    if (status != JBV_OK) return status;
    if (o->type->builtin == B_STRING) {
        (void)jbv_string_view(vm, ref, &text);
        if (!sliced) { *out = ref; status = JBV_OK; }
        else if (start < 0 || end < start || (uint32_t)end > text.length)
            status = jbv_throw_named(vm, "java/lang/IndexOutOfBoundsException", 0, JBV_ARRAY_BOUNDS);
        else status = copy_string(vm, text.data ? text.data + start : 0, (uint32_t)(end - start), out);
        if (pinned) (void)jbv_release(vm, ref);
        return status;
    }
    owner = o->type;
    id.method = jbv_lookup_method(&owner, jbv_text("length"), jbv_text("()I")); id.owner = owner;
    if (!id.method) return JBV_NOT_FOUND;
    status = jbv_invoke(vm, &id, &ref, 1, &length);
    if (status != JBV_OK) return status;
    if (!sliced) { start = 0; end = (int32_t)length; }
    if (start < 0 || end < start || (uint32_t)end > (uint32_t)length)
        return jbv_throw_named(vm, "java/lang/IndexOutOfBoundsException", 0, JBV_ARRAY_BOUNDS);
    status = jbv_string_alloc(vm, (uint32_t)(end - start), &value, &data);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm, value);
    owner = o->type;
    id.method = jbv_lookup_method(&owner, jbv_text("charAt"), jbv_text("(I)C")); id.owner = owner;
    args[0] = ref;
    if (!id.method) status = JBV_NOT_FOUND;
    for (i = 0; status == JBV_OK && i < (uint32_t)(end - start); ++i) {
        args[1] = start + (int32_t)i;
        status = jbv_invoke(vm, &id, args, 2, &ch);
        if (status == JBV_OK) data[i] = (uint16_t)ch;
    }
    (void)jbv_release(vm, value);
    if (status == JBV_OK) *out = value;
    return status;
}
static JbvStatus builder_buffer(JbvVM *vm, JbvObject *o, uint32_t minimum, JbvTextView *view) {
    int32_t *fields = jbv_data(o), ref;
    uint16_t *data;
    JbvStatus status;
    uint32_t n, i;
    view->data = 0; view->length = 0;
    if (fields[0]) { status = array_view(vm, fields[0], view); if (status != JBV_OK) return status; }
    if (minimum <= view->length) return JBV_OK;
    if (minimum > INT32_MAX) return JBV_OUT_OF_MEMORY;
    n = view->length <= (INT32_MAX - 2u) / 2 ? view->length * 2 + 2 : INT32_MAX;
    if (n < minimum) n = minimum;
    status = char_array(vm, n, &ref, &data);
    if (status != JBV_OK) return status;
    for (i = 0; i < (uint32_t)fields[1]; ++i) data[i] = view->data[i];
    fields[0] = ref; jbv_barrier_checked(vm, (JbvObject *)fields - 1, ref); view->data = data; view->length = n;
    return JBV_OK;
}
static JbvStatus builder_call(JbvVM *vm, uint32_t op, uint8_t kind, const int32_t *a, uint16_t count, int32_t *out) {
    JbvObject *o;
    JbvTextView buffer, text;
    JbvStatus status = jbv_object(vm, a[0], &o);
    int32_t *fields, ref = 0, start = 0, end;
    uint32_t length, i, at, removed = 0;
    const int32_t *v = a + (op == A_INSERT ? 2 : 1);
    if (status != JBV_OK) return status;
    fields = jbv_data(o); length = (uint32_t)fields[1];
    status = builder_buffer(vm, o, 0, &buffer);
    if (status != JBV_OK) return status;
    *out = 0;
    switch (op) {
    case A_TRIM:
        if (buffer.length == length) return JBV_OK;
        status = char_array(vm, length, &ref, &text.data);
        if (status != JBV_OK) return status;
        for (i = 0; i < length; ++i) text.data[i] = buffer.data[i];
        fields[0] = ref; jbv_barrier_checked(vm, (JbvObject *)fields - 1, ref); return JBV_OK;
    case A_DELETE: case A_DELETE_CHAR:
        start = a[1]; end = op == A_DELETE_CHAR ? start : a[2];
        if (start < 0 || (uint32_t)start > length || end < start || (op == A_DELETE_CHAR && (uint32_t)start == length)) return string_bounds(vm);
        if (op == A_DELETE_CHAR) ++end;
        if ((uint32_t)end > length) end = (int32_t)length;
        for (i = (uint32_t)end; i < length; ++i) buffer.data[i - (uint32_t)(end-start)] = buffer.data[i];
        fields[1] -= end-start; *out = a[0]; return JBV_OK;
    case A_REPLACE:
        if (a[1] < 0 || (uint32_t)a[1] > length || a[2] < a[1]) return string_bounds(vm);
        if (!a[3]) return JBV_NULL_REFERENCE;
        removed = ((uint32_t)a[2] > length ? length : (uint32_t)a[2]) - (uint32_t)a[1];
        ref = a[3]; goto materialized;
    case A_CODEPOINT: {
        uint32_t ch = (uint32_t)a[1];
        if (ch > 0x10ffff) return JBV_BAD_ARGUMENT;
        status = jbv_string_alloc(vm, ch > 65535 ? 2 : 1, &ref, &text.data);
        if (status != JBV_OK) return status;
        text.data[0] = ch > 65535 ? (uint16_t)(0xd800 + ((ch-65536)>>10)) : (uint16_t)ch;
        if (ch > 65535) text.data[1] = (uint16_t)(0xdc00 + ((ch-65536)&1023));
        goto materialized;
    }
    case A_COMPARE: {
        JbvObject *other;
        uint32_t other_length;
        status = jbv_object(vm, a[1], &other);
        if (status != JBV_OK) return status;
        if (other->type->builtin != B_BUILDER) return JBV_CLASS_CAST;
        other_length = (uint32_t)jbv_data(other)[1];
        status = builder_buffer(vm, other, 0, &text);
        if (status != JBV_OK) return status;
        for (i = 0; i < length && i < other_length && buffer.data[i] == text.data[i]; ++i) {}
        *out = i < length && i < other_length ? buffer.data[i] - text.data[i] : (int32_t)length - (int32_t)other_length;
        return JBV_OK;
    }
    case A_LENGTH: *out = (int32_t)length; return JBV_OK;
    case A_CAPACITY: *out = (int32_t)buffer.length; return JBV_OK;
    case A_CHAR: case A_SET_CHAR:
        if ((uint32_t)a[1] >= length) return string_bounds(vm);
        if (op == A_CHAR) *out = buffer.data[a[1]]; else buffer.data[a[1]] = (uint16_t)a[2];
        return JBV_OK;
    case A_ENSURE: return a[1] <= 0 ? JBV_OK : builder_buffer(vm, o, (uint32_t)a[1], &buffer);
    case A_SET_LENGTH:
        if (a[1] < 0) return string_bounds(vm);
        status = builder_buffer(vm, o, (uint32_t)a[1], &buffer);
        if (status == JBV_OK) { for (i = length; i < (uint32_t)a[1]; ++i) buffer.data[i] = 0; fields[1] = a[1]; }
        return status;
    case A_TEXT: case A_SUBSTRING:
        end = (int32_t)length;
        if (op == A_SUBSTRING) { start = a[1]; if (count == 3) end = a[2]; }
        if (start < 0 || end < start || (uint32_t)end > length) return string_bounds(vm);
        return copy_string(vm, buffer.data ? buffer.data + start : 0, (uint32_t)(end - start), out);
    case A_REVERSE:
        for (i = 0; i < length / 2; ++i) { uint16_t t = buffer.data[i]; buffer.data[i] = buffer.data[length - 1 - i]; buffer.data[length - 1 - i] = t; }
        for (i = 0; i + 1 < length; ++i)
            if (buffer.data[i] >= 0xdc00 && buffer.data[i] <= 0xdfff && buffer.data[i+1] >= 0xd800 && buffer.data[i+1] <= 0xdbff) {
                uint16_t t = buffer.data[i]; buffer.data[i] = buffer.data[i+1]; buffer.data[++i] = t;
            }
        *out = a[0]; return JBV_OK;
    default: break;
    }
    if (op == A_INIT) {
        if (!kind || kind == 'I') {
            int32_t capacity = kind ? a[1] : 16;
            if (capacity < 0) return JBV_NEGATIVE_ARRAY_SIZE;
            /* Constructor capacity is exact, unlike ensureCapacity growth. */
            status = char_array(vm, (uint32_t)capacity, &ref, &buffer.data);
            if (status == JBV_OK) { fields[0] = ref; fields[1] = 0; jbv_barrier_checked(vm, (JbvObject *)fields - 1, ref); }
            return status;
        }
        if (!a[1]) return JBV_NULL_REFERENCE;
    }
    if (op == A_INSERT) {
        if (a[1] < 0 || (uint32_t)a[1] > length) return string_bounds(vm);
        --count;
    }
    if (kind == '[') {
        status = array_view(vm, v[0], &text);
        if (status != JBV_OK) return status;
        if (count == 4) {
            if (v[1] < 0 || v[2] < 0 || (uint32_t)v[1] > text.length || (uint32_t)v[2] > text.length - (uint32_t)v[1]) return JBV_ARRAY_BOUNDS;
            text.data += v[1]; text.length = (uint32_t)v[2];
        }
        status = copy_string(vm, text.data, text.length, &ref);
    } else if (kind == 'Q') status = sequence_string(vm, v[0], count == 4, count == 4 ? v[1] : 0, count == 4 ? v[2] : 0, &ref);
    else status = value_string(vm, kind, v, &ref);
    if (status != JBV_OK) return status;
    if (!ref) { status = jbv_string_mutf(vm, jbv_text("null"), &ref); if (status != JBV_OK) return status; }
materialized:
    (void)jbv_retain(vm, ref);
    status = jbv_string_view(vm, ref, &text);
    if (status != JBV_OK) goto done;
    /* User toString/CharSequence calls may have reentered and modified this
     * very builder. Append after its current content, not the pre-call length. */
    length = (uint32_t)fields[1];
    at = op == A_INSERT || op == A_REPLACE ? (uint32_t)a[1] : length;
    if (at > length) { status = string_bounds(vm); goto done; }
    if (text.length > INT32_MAX - (length-removed) || (op == A_INIT && text.length > INT32_MAX - 16u)) { status = JBV_OUT_OF_MEMORY; goto done; }
    status = builder_buffer(vm, o, length - removed + text.length + (op == A_INIT ? 16u : 0u), &buffer);
    if (status == JBV_OK) {
        if (text.length > removed) { i = length; while (i > at+removed) { --i; buffer.data[i+text.length-removed] = buffer.data[i]; } }
        else for (i = at+removed; i < length; ++i) buffer.data[i+text.length-removed] = buffer.data[i];
        /* CharSequence insertion reads charAt after making room. Preserve the
         * observable aliasing order when the source is this same builder. */
        if (op == A_INSERT && kind == 'Q' && v[0] == a[0])
            for (i = 0; i < text.length; ++i) buffer.data[at+i] = buffer.data[(count == 4 ? (uint32_t)v[1] : 0u)+i];
        else for (i = 0; i < text.length; ++i) buffer.data[at+i] = text.data[i];
        fields[1] = (int32_t)(length - removed + text.length);
        if (op != A_INIT) *out = a[0];
    }
done:
    (void)jbv_release(vm, ref); return status;
}
static int text_match(JbvTextView text, uint32_t at, JbvTextView pattern) {
    uint32_t i;
    if (pattern.length > text.length-at) return 0;
    for (i = 0; i < pattern.length; ++i) if (text.data[at+i] != pattern.data[i]) return 0;
    return 1;
}
static JbvStatus replace_sequence(JbvVM *vm, JbvTextView text, const int32_t *a, int32_t *out, int contains) {
    JbvTextView pattern, replacement;
    int32_t p = 0, r = 0;
    uint16_t *data;
    uint32_t i, j, hits = 0, next = 0;
    uint64_t length;
    JbvStatus status;
    if (!a[1] || (!contains && !a[2])) return JBV_NULL_REFERENCE;
    status = sequence_string(vm, a[1], 0, 0, 0, &p);
    if (status != JBV_OK) return status;
    (void)jbv_retain(vm, p); (void)jbv_string_view(vm, p, &pattern);
    for (i = 0; i <= text.length; ++i) if (text_match(text, i, pattern)) {
        ++hits; if (pattern.length) i += pattern.length-1;
    }
    if (contains) { *out = hits != 0; goto done; }
    status = sequence_string(vm, a[2], 0, 0, 0, &r);
    if (status != JBV_OK) goto done;
    (void)jbv_retain(vm, r); (void)jbv_string_view(vm, r, &replacement);
    if (!hits) { *out = a[0]; goto done; }
    length = text.length - (uint64_t)hits*pattern.length + (uint64_t)hits*replacement.length;
    if (length > INT32_MAX) { status = JBV_OUT_OF_MEMORY; goto done; }
    status = jbv_string_alloc(vm, (uint32_t)length, out, &data);
    if (status != JBV_OK) goto done;
    for (i = 0; i <= text.length;) {
        if (text_match(text, i, pattern)) {
            for (j = 0; j < replacement.length; ++j) data[next++] = replacement.data[j];
            if (pattern.length) { i += pattern.length; continue; }
        }
        if (i < text.length) data[next++] = text.data[i];
        ++i;
    }
done:
    (void)jbv_release(vm, p); (void)jbv_release(vm, r); return status;
}
JbvStatus jbv_text_native(JbvVM *vm, uint32_t op, uint8_t kind, const int32_t *a, uint16_t count, uint64_t *out) {
    JbvTextView text, other;
    JbvObject *o = 0, *s = 0;
    JbvStatus status;
    int32_t result = 0, start, end;
    uint16_t *data;
    uint32_t i, j, hash;
    if (op >= A_INIT) {
        status = builder_call(vm, op, kind, a, count, &result);
        if (status == JBV_OK) *out = (uint32_t)result;
        return status;
    }
    if (op == S_VALUE) {
        if (kind != '[') status = value_string(vm, kind, a, &result);
        else {
            status = array_view(vm, a[0], &text);
            if (status != JBV_OK) return status;
            start = count == 3 ? a[1] : 0; end = count == 3 ? a[2] : (int32_t)text.length;
            if (start < 0 || end < 0 || (uint32_t)start > text.length || (uint32_t)end > text.length - (uint32_t)start) return string_bounds(vm);
            status = copy_string(vm, text.data + start, (uint32_t)end, &result);
        }
        if (status == JBV_OK) *out = (uint32_t)result;
        return status;
    }
    status = jbv_string_view(vm, a[0], &text);
    if (status != JBV_OK) return status;
    switch (op) {
    case S_TRIM:
        start = 0; end = (int32_t)text.length;
        while (start < end && text.data[start] <= 32) ++start;
        while (start < end && text.data[end-1] <= 32) --end;
        if (!start && (uint32_t)end == text.length) result = a[0];
        else { status = copy_string(vm, text.data ? text.data+start : 0, (uint32_t)(end-start), &result); if (status != JBV_OK) return status; }
        break;
    case S_REPLACE: case S_CONTAINS:
        if (!kind) { status = replace_sequence(vm, text, a, &result, op == S_CONTAINS); if (status != JBV_OK) return status; break; }
        for (i = 0; i < text.length && text.data[i] != (uint16_t)a[1]; ++i) {}
        if (i == text.length || a[1] == a[2]) { result = a[0]; break; }
        status = jbv_string_alloc(vm, text.length, &result, &data);
        if (status != JBV_OK) return status;
        for (i = 0; i < text.length; ++i) data[i] = text.data[i] == (uint16_t)a[1] ? (uint16_t)a[2] : text.data[i];
        break;
    case S_REPEAT:
        if (a[1] < 0) return JBV_BAD_ARGUMENT;
        if (a[1] == 1) { result = a[0]; break; }
        if (a[1] && text.length > INT32_MAX / (uint32_t)a[1]) return JBV_OUT_OF_MEMORY;
        status = jbv_string_alloc(vm, text.length*(uint32_t)a[1], &result, &data);
        if (status != JBV_OK) return status;
        if (text.length) for (i = 0; i < (uint32_t)a[1]; ++i) for (j = 0; j < text.length; ++j) data[i*text.length+j] = text.data[j];
        break;
    case S_INIT:
        (void)jbv_object(vm, a[0], &s);
        if (!kind) break;
        if (kind == 'L') {
            status = jbv_string_view(vm, a[1], &other);
            if (status != JBV_OK) return status;
            (void)jbv_object(vm, a[1], &o); jbv_data(s)[0] = jbv_data(o)[0]; jbv_barrier_checked(vm, s, jbv_data(s)[0]); break;
        }
        status = array_view(vm, a[1], &other);
        if (status != JBV_OK) return status;
        start = count == 4 ? a[2] : 0; end = count == 4 ? a[3] : (int32_t)other.length;
        if (start < 0 || end < 0 || (uint32_t)start > other.length || (uint32_t)end > other.length - (uint32_t)start) return string_bounds(vm);
        status = char_array(vm, (uint32_t)end, &result, &data);
        if (status != JBV_OK) return status;
        for (i = 0; i < (uint32_t)end; ++i) data[i] = other.data[start+i];
        jbv_data(s)[0] = result; jbv_barrier_checked(vm, s, result); result = 0; break;
    case S_LENGTH: result = (int32_t)text.length; break;
    case S_EMPTY: result = text.length == 0; break;
    case S_TEXT: result = a[0]; break;
    case S_CHAR:
        if ((uint32_t)a[1] >= text.length) return string_bounds(vm);
        result = text.data[a[1]]; break;
    case S_HASH:
        for (i = hash = 0; i < text.length; ++i) hash = hash * 31 + (uint32_t)text.data[i];
        result = jbv_i32(hash); break;
    case S_EQUALS: case S_COMPARE:
        if (op == S_EQUALS && !a[1]) break;
        status = jbv_string_view(vm, a[1], &other);
        if (status == JBV_CLASS_CAST && op == S_EQUALS) break;
        if (status != JBV_OK) return status;
        for (i = 0; i < text.length && i < other.length; ++i) if (text.data[i] != other.data[i]) break;
        if (op == S_EQUALS) result = i == text.length && i == other.length;
        else result = i < text.length && i < other.length ? text.data[i] - other.data[i] : (int32_t)text.length - (int32_t)other.length;
        break;
    case S_SUBSTRING:
        start = a[1]; end = count == 3 ? a[2] : (int32_t)text.length;
        if (start < 0 || end < start || (uint32_t)end > text.length) return string_bounds(vm);
        if (!start && (uint32_t)end == text.length) result = a[0];
        else { status = copy_string(vm, text.data ? text.data + start : 0, (uint32_t)(end - start), &result); if (status != JBV_OK) return status; }
        break;
    case S_CHARS:
        status = char_array(vm, text.length, &result, &data);
        if (status != JBV_OK) return status;
        for (i = 0; i < text.length; ++i) data[i] = text.data[i];
        break;
    case S_GET_CHARS:
        if (a[1] < 0 || a[2] < a[1] || (uint32_t)a[2] > text.length) return string_bounds(vm);
        status = array_view(vm, a[3], &other);
        if (status != JBV_OK) return status;
        if (a[4] < 0 || (uint32_t)a[4] > other.length || (uint32_t)(a[2] - a[1]) > other.length - (uint32_t)a[4]) return JBV_ARRAY_BOUNDS;
        for (i = 0; i < (uint32_t)(a[2] - a[1]); ++i) other.data[a[4]+i] = text.data[a[1]+i];
        break;
    case S_CONCAT:
        status = jbv_string_view(vm, a[1], &other);
        if (status != JBV_OK) return status;
        if (!other.length) { result = a[0]; break; }
        if (other.length > INT32_MAX - text.length) return JBV_OUT_OF_MEMORY;
        status = jbv_string_alloc(vm, text.length + other.length, &result, &data);
        if (status != JBV_OK) return status;
        for (i = 0; i < text.length; ++i) data[i] = text.data[i];
        for (j = 0; j < other.length; ++j) data[i+j] = other.data[j];
        break;
    case S_INTERN: status = jbv_string_intern(vm, a[0], &result); if (status != JBV_OK) return status; break;
    case S_STARTS: case S_ENDS:
        status = jbv_string_view(vm, a[1], &other);
        if (status != JBV_OK) return status;
        start = op == S_ENDS ? (int32_t)text.length - (int32_t)other.length : count == 3 ? a[2] : 0;
        if (start < 0 || (uint32_t)start > text.length || other.length > text.length - (uint32_t)start) break;
        for (i = 0; i < other.length && text.data[start+i] == other.data[i]; ++i) {}
        result = i == other.length; break;
    case S_INDEX: case S_LAST_INDEX: {
        uint16_t pair[2];
        if (kind == 'I') {
            uint32_t ch = (uint32_t)a[1];
            if (ch > 0x10ffff) { result = -1; break; }
            other.length = ch > 65535 ? 2 : 1; other.data = pair;
            pair[0] = ch > 65535 ? (uint16_t)(0xd800 + ((ch - 65536) >> 10)) : (uint16_t)ch;
            pair[1] = (uint16_t)(0xdc00 + ((ch - 65536) & 1023));
        } else { status = jbv_string_view(vm, a[1], &other); if (status != JBV_OK) return status; }
        end = (int32_t)text.length - (int32_t)other.length;
        start = count == 3 ? a[2] : op == S_LAST_INDEX ? (int32_t)text.length : 0;
        result = -1;
        if (op == S_INDEX) {
            if (start < 0) start = 0;
            if (!other.length && (uint32_t)start > text.length) start = (int32_t)text.length;
            for (; start <= end; ++start) {
                for (i = 0; i < other.length && text.data[start+i] == other.data[i]; ++i) {}
                if (i == other.length) { result = start; break; }
            }
        } else {
            if (start > end) start = end;
            for (; start >= 0; --start) {
                for (i = 0; i < other.length && text.data[start+i] == other.data[i]; ++i) {}
                if (i == other.length) { result = start; break; }
            }
        }
        break;
    }
    default: return JBV_UNSUPPORTED_FEATURE;
    }
    *out = (uint32_t)result; return JBV_OK;
}

JBV_API JbvStatus JBV_CALL jbv_string_new_utf16(JbvVM *vm, const uint16_t *text, uint32_t length, JbvRef *out) {
    int32_t ref;
    uint16_t *data;
    uint32_t i;
    JbvStatus status;
    if (!vm || !out || (length && !text)) return JBV_BAD_ARGUMENT;
    status = jbv_string_alloc(vm, length, &ref, &data);
    if (status == JBV_OK) {
        for (i = 0; i < length; ++i) data[i] = text[i];
        status = jbv_retain(vm, ref);
        if (status == JBV_OK) *out = ref;
    }
    return status;
}
static int utf8_next(const uint8_t *s, uint32_t n, uint32_t *pos, uint32_t *out) {
    uint32_t ch = s[(*pos)++], need, min;
    if (ch < 128) { *out = ch; return 1; }
    if (ch >= 0xc2 && ch <= 0xdf) { need = 1; min = 128; ch &= 31; }
    else if (ch >= 0xe0 && ch <= 0xef) { need = 2; min = 2048; ch &= 15; }
    else if (ch >= 0xf0 && ch <= 0xf4) { need = 3; min = 65536; ch &= 7; }
    else return 0;
    if (need > n - *pos) return 0;
    while (need--) { uint32_t b = s[(*pos)++]; if ((b & 192) != 128) return 0; ch = (ch << 6) | (b & 63); }
    if (ch < min || ch > 0x10ffff || (ch >= 0xd800 && ch <= 0xdfff)) return 0;
    *out = ch; return 1;
}
JBV_API JbvStatus JBV_CALL jbv_string_new_utf8(JbvVM *vm, const char *text, uint32_t bytes, JbvRef *out) {
    uint32_t pos = 0, n = 0, ch = 0;
    int32_t ref;
    uint16_t *data;
    JbvStatus status;
    if (!vm || !out || (bytes && !text)) return JBV_BAD_ARGUMENT;
    while (pos < bytes) {
        if (!utf8_next((const uint8_t *)text, bytes, &pos, &ch)) return JBV_BAD_ARGUMENT;
        n += ch > 65535 ? 2u : 1u;
    }
    status = jbv_string_alloc(vm, n, &ref, &data);
    if (status != JBV_OK) return status;
    pos = n = 0;
    while (pos < bytes) {
        (void)utf8_next((const uint8_t *)text, bytes, &pos, &ch);
        if (ch > 65535) { data[n++] = (uint16_t)(0xd800 + ((ch - 65536) >> 10)); ch = 0xdc00 + ((ch - 65536) & 1023); }
        data[n++] = (uint16_t)ch;
    }
    status = jbv_retain(vm, ref);
    if (status == JBV_OK) *out = ref;
    return status;
}
JBV_API JbvStatus JBV_CALL jbv_string_length(JbvVM *vm, JbvRef ref, uint32_t *out) {
    JbvTextView text;
    JbvStatus status;
    if (!vm || !out) return JBV_BAD_ARGUMENT;
    status = jbv_string_view(vm, ref, &text);
    if (status == JBV_OK) *out = text.length;
    return status;
}
JBV_API JbvStatus JBV_CALL jbv_string_read_utf16(JbvVM *vm, JbvRef ref, uint32_t start, uint32_t count, uint16_t *out) {
    JbvTextView text;
    JbvStatus status;
    uint32_t i;
    if (!vm || (count && !out)) return JBV_BAD_ARGUMENT;
    status = jbv_string_view(vm, ref, &text);
    if (status != JBV_OK) return status;
    if (start > text.length || count > text.length - start) return JBV_ARRAY_BOUNDS;
    for (i = 0; i < count; ++i) out[i] = (uint16_t)text.data[start+i];
    return JBV_OK;
}
JBV_API JbvStatus JBV_CALL jbv_string_read_utf8(JbvVM *vm, JbvRef ref, char *out, uint32_t capacity, uint32_t *bytes) {
    JbvTextView text;
    JbvStatus status;
    uint32_t pass, i, n = 0, ch, width;
    if (!vm || !bytes || (!out && capacity)) return JBV_BAD_ARGUMENT;
    status = jbv_string_view(vm, ref, &text);
    if (status != JBV_OK) return status;
    for (pass = 0; pass < 2; ++pass) {
        n = 0;
        for (i = 0; i < text.length; ++i) {
            ch = (uint32_t)text.data[i];
            if (ch >= 0xd800 && ch <= 0xdfff) {
                if (ch <= 0xdbff && i + 1 < text.length && text.data[i+1] >= 0xdc00 && text.data[i+1] <= 0xdfff)
                    ch = 65536 + ((ch - 0xd800) << 10) + ((uint32_t)text.data[++i] - 0xdc00);
                else ch = 0xfffd;
            }
            width = ch < 128 ? 1u : ch < 2048 ? 2u : ch < 65536 ? 3u : 4u;
            if (width > UINT32_MAX - n) return JBV_LIMIT_EXCEEDED;
            if (pass) {
                if (width == 1) out[n] = (char)ch;
                else {
                    uint32_t j = width - 1;
                    while (j) { out[n+j] = (char)(128 | (ch & 63)); ch >>= 6; --j; }
                    out[n] = (char)((width == 2 ? 192 : width == 3 ? 224 : 240) | ch);
                }
            }
            n += width;
        }
        if (!out) break;
        if (!pass && n > capacity) return JBV_BAD_ARGUMENT;
    }
    *bytes = n; return JBV_OK;
}

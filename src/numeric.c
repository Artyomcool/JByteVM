#include "internal.h"

int _fltused = 0;
typedef union Number { uint64_t u; int64_t j; double d; } Number;
typedef union Single { uint32_t u; float f; } Single;
uint8_t jbv_kind(uint8_t c) {
    return c == 'L' || c == '[' || c == 'P' ? JBV_REF : c == 'J' ? JBV_LONG :
        c == 'F' ? JBV_FLOAT : c == 'D' ? JBV_DOUBLE : JBV_INT;
}
/* Packed input/output slot kinds; TOP denotes an absent right operand. */
uint32_t jbv_numeric_types(uint8_t op) {
    uint32_t a, b, r;
    if (op >= 97 && op <= 115) {
        a = (op & 3) == 1 ? JBV_LONG : (op & 3) == 2 ? JBV_FLOAT : JBV_DOUBLE;
        b = r = a;
    } else if (op >= 117 && op <= 119) {
        a = op == 117 ? JBV_LONG : op == 118 ? JBV_FLOAT : JBV_DOUBLE; b = JBV_TOP; r = a;
    } else if (op >= 121 && op <= 131) {
        a = r = JBV_LONG; b = op <= 125 ? JBV_INT : JBV_LONG;
    } else if (op >= 133 && op <= 144) {
        a = op <= 135 ? JBV_INT : op <= 138 ? JBV_LONG : op <= 141 ? JBV_FLOAT : JBV_DOUBLE;
        b = JBV_TOP;
        switch (op) {
        case 133: case 140: case 143: r = JBV_LONG; break;
        case 134: case 137: case 144: r = JBV_FLOAT; break;
        case 135: case 138: case 141: r = JBV_DOUBLE; break;
        default: r = JBV_INT; break;
        }
    } else {
        a = b = op == 148 ? JBV_LONG : op <= 150 ? JBV_FLOAT : JBV_DOUBLE; r = JBV_INT;
    }
    return a | (b << 8) | (r << 16);
}
static int64_t signed64(uint64_t n) { return n <= INT64_MAX ? (int64_t)n : -1 - (int64_t)(UINT64_MAX - n); }
static uint64_t integer_to_ieee(uint64_t n, uint32_t precision, uint32_t bias, uint32_t sign_bit) {
    uint64_t sign = n >> 63, scan, significant, mask;
    uint32_t exponent = 0;
    if (sign) n = 0 - n;
    if (!n) return 0;
    for (scan = n; scan >>= 1;) ++exponent;
    if (exponent <= precision) significant = n << (precision - exponent);
    else {
        uint32_t shift = exponent - precision;
        uint64_t half = UINT64_C(1) << (shift - 1), tail = n & ((half << 1) - 1);
        significant = n >> shift;
        if (tail > half || (tail == half && (significant & 1))) ++significant;
        if (significant >> (precision + 1)) { significant >>= 1; ++exponent; }
    }
    mask = (UINT64_C(1) << precision) - 1;
    return (sign << sign_bit) | ((uint64_t)(exponent + bias) << precision) | (significant & mask);
}
static uint64_t float_to_integer(double n, int wide) {
    Number value;
    uint64_t magnitude, sign;
    int exponent;
    value.d = n;
    sign = value.u >> 63;
    exponent = (int)((value.u >> 52) & 2047);
    magnitude = value.u & UINT64_C(0xfffffffffffff);
    if (exponent == 2047 && magnitude) return 0; /* NaN */
    exponent -= 1023;
    if (exponent < 0) return 0;
    if (exponent >= (wide ? 63 : 31))
        return wide ? (sign ? UINT64_C(0x8000000000000000) : INT64_MAX) : (sign ? (uint32_t)INT32_MIN : INT32_MAX);
    magnitude |= UINT64_C(1) << 52;
    magnitude = exponent > 52 ? magnitude << (exponent - 52) : magnitude >> (52 - exponent);
    magnitude = sign ? 0 - magnitude : magnitude;
    return wide ? magnitude : (uint32_t)magnitude;
}
/* Binary long division of significands computes truncating IEEE remainder
 * without importing libm. Its result is exact, including subnormal values. */
static double remainder(double a, double b) {
    Number x, y, result;
    uint64_t mx, my, sign;
    int ex, ey;
    x.d = a; y.d = b;
    sign = x.u & UINT64_C(0x8000000000000000);
    x.u &= UINT64_C(0x7fffffffffffffff); y.u &= UINT64_C(0x7fffffffffffffff);
    if (!y.u || x.u >= UINT64_C(0x7ff0000000000000) || y.u > UINT64_C(0x7ff0000000000000)) {
        result.u = UINT64_C(0x7ff8000000000000); return result.d;
    }
    if (x.u < y.u) return a;
    if (x.u == y.u) { result.u = sign; return result.d; }
    ex = (int)(x.u >> 52); ey = (int)(y.u >> 52);
    mx = x.u & UINT64_C(0xfffffffffffff); my = y.u & UINT64_C(0xfffffffffffff);
    if (ex) { mx |= UINT64_C(1) << 52; ex -= 1023; }
    else { ex = -1022; while (!(mx & (UINT64_C(1) << 52))) { mx <<= 1; --ex; } }
    if (ey) { my |= UINT64_C(1) << 52; ey -= 1023; }
    else { ey = -1022; while (!(my & (UINT64_C(1) << 52))) { my <<= 1; --ey; } }
    while (ex > ey) {
        if (mx >= my) mx -= my;
        mx <<= 1; --ex;
    }
    if (mx >= my) mx -= my;
    if (!mx) { result.u = sign; return result.d; }
    while (!(mx & (UINT64_C(1) << 52))) { mx <<= 1; --ey; }
    result.u = sign | (ey >= -1022 ? ((uint64_t)(ey + 1023) << 52) | (mx & UINT64_C(0xfffffffffffff)) : mx >> (-1022 - ey));
    return result.d;
}
JbvStatus jbv_numeric(uint8_t op, uint64_t a, uint64_t b, uint64_t *out) {
    uint32_t types = jbv_numeric_types(op), kind = types & 255, shift;
    Number x, y, z;
    Single f, g, h;
    int64_t left, right;
    double d;
    x.u = a; y.u = b; f.u = (uint32_t)a; g.u = (uint32_t)b;
    left = signed64(a); right = signed64(b);
    if (op >= 133 && op <= 144) {
        uint32_t target = types >> 16;
        if (target == JBV_INT && kind == JBV_LONG) *out = (uint32_t)a;
        else if (target == JBV_LONG && kind == JBV_INT) *out = (uint64_t)(int64_t)jbv_i32((uint32_t)a);
        else if (target == JBV_INT || target == JBV_LONG) *out = float_to_integer(kind == JBV_FLOAT ? (double)f.f : x.d, target == JBV_LONG);
        else if (target == JBV_FLOAT) {
            if (kind == JBV_LONG) *out = integer_to_ieee(a, 23, 127, 31);
            else { h.f = kind == JBV_INT ? (float)jbv_i32((uint32_t)a) : (float)x.d; *out = h.u; }
        } else {
            if (kind == JBV_LONG) *out = integer_to_ieee(a, 52, 1023, 63);
            else { z.d = kind == JBV_INT ? (double)jbv_i32((uint32_t)a) : (double)f.f; *out = z.u; }
        }
        return JBV_OK;
    }
    if (op >= 148) {
        int comparison;
        if (kind == JBV_LONG) comparison = left < right ? -1 : left > right;
        else {
            d = kind == JBV_FLOAT ? (double)f.f : x.d;
            z.d = kind == JBV_FLOAT ? (double)g.f : y.d;
            comparison = d != d || z.d != z.d ? (op == 149 || op == 151 ? -1 : 1) : d < z.d ? -1 : d > z.d;
        }
        *out = (uint32_t)comparison; return JBV_OK;
    }
    if (kind == JBV_LONG) {
        shift = (uint32_t)b & 63;
        switch (op) {
        case 97: *out = a + b; break;
        case 101: *out = a - b; break;
        case 105: *out = a * b; break;
        case 109: case 113:
            if (!b) return JBV_DIVIDE_BY_ZERO;
            if (a == UINT64_C(0x8000000000000000) && b == UINT64_MAX) *out = op == 109 ? a : 0;
            else *out = (uint64_t)(op == 109 ? left / right : left % right);
            break;
        case 117: *out = 0 - a; break;
        case 121: *out = a << shift; break;
        case 123: *out = (a >> shift) | ((a >> 63) && shift ? UINT64_MAX << (64 - shift) : 0); break;
        case 125: *out = a >> shift; break;
        case 127: *out = a & b; break;
        case 129: *out = a | b; break;
        case 131: *out = a ^ b; break;
        default: return JBV_UNSUPPORTED_FEATURE;
        }
    } else if (kind == JBV_FLOAT) {
        switch (op) {
        case 98: h.f = f.f + g.f; break;
        case 102: h.f = f.f - g.f; break;
        case 106: h.f = f.f * g.f; break;
        case 110: h.f = f.f / g.f; break;
        case 114: h.f = (float)remainder((double)f.f, (double)g.f); break;
        case 118: h.u = f.u ^ 0x80000000u; break;
        default: return JBV_UNSUPPORTED_FEATURE;
        }
        *out = h.u;
    } else {
        switch (op) {
        case 99: z.d = x.d + y.d; break;
        case 103: z.d = x.d - y.d; break;
        case 107: z.d = x.d * y.d; break;
        case 111: z.d = x.d / y.d; break;
        case 115: z.d = remainder(x.d, y.d); break;
        case 119: z.u = x.u ^ UINT64_C(0x8000000000000000); break;
        default: return JBV_UNSUPPORTED_FEATURE;
        }
        *out = z.u;
    }
    return JBV_OK;
}

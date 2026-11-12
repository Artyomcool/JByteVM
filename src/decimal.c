#include "library.h"
#if defined(_M_IX86)
/* decimal_x86.asm; the C below is the reference and serves other targets */
uint32_t JBV_CALL jbv_decimal_text_x86(uint32_t lo, uint32_t hi, int single, uint16_t *out);
int JBV_CALL jbv_parse_fp_x86(const uint16_t *s, uint32_t n, int single, uint64_t *out);
uint32_t jbv_decimal_text(uint64_t bits, int single, uint16_t *out) { return jbv_decimal_text_x86((uint32_t)bits, (uint32_t)(bits >> 32), single, out); }
JbvStatus jbv_parse_fp(JbvVM *vm, int32_t string, int single, uint64_t *out) {
    JbvTextView text;
    JbvStatus status = jbv_string_view(vm, string, &text);
    if (status != JBV_OK) return status;
    if (!jbv_parse_fp_x86(text.data, text.length, single, out)) return JBV_OK;
    return jbv_throw_named(vm, "java/lang/NumberFormatException", 0, JBV_EXCEPTION);
}
#else

/* Exact interval conversion for binary32/binary64. This uses integer arithmetic
 * only: no locale, CRT printf, FP rounding mode, or large power-of-ten tables.
 * R/S is the exact value, lower/upper its rounding margins. Digits stop at the
 * shortest admissible decimal (at least two digits before trimming, as required
 * by Java 25's closest choice when the shortest decimal has length one).
 * Formatting needs fewer than 1200 bits. Parsing below needs at most 4096.
 * This prioritizes image size over the throughput of a table-based formatter. */
typedef struct Big { uint32_t n, word[128]; } Big;
static void set(Big *a, uint64_t x) {
    a->word[0] = (uint32_t)x; a->word[1] = (uint32_t)(x >> 32);
    a->n = a->word[1] ? 2u : 1u;
}
static void copy(Big *a, const Big *b) {
    uint32_t i; a->n = b->n;
    for (i = 0; i < b->n; ++i) a->word[i] = b->word[i];
}
static void multiply(Big *a, uint32_t factor) {
    uint32_t i; uint64_t carry = 0;
    for (i = 0; i < a->n; ++i) { carry += (uint64_t)a->word[i] * factor; a->word[i] = (uint32_t)carry; carry >>= 32; }
    if (carry) a->word[a->n++] = (uint32_t)carry;
}
static int compare(const Big *a, const Big *b) {
    uint32_t i;
    if (a->n != b->n) return a->n > b->n ? 1 : -1;
    for (i = a->n; i--;) if (a->word[i] != b->word[i]) return a->word[i] > b->word[i] ? 1 : -1;
    return 0;
}
static void subtract(Big *a, const Big *b) {
    uint32_t i; uint64_t borrow = 0;
    for (i = 0; i < a->n; ++i) {
        uint64_t sub = (i < b->n ? b->word[i] : 0u) + borrow;
        borrow = a->word[i] < sub;
        a->word[i] = (uint32_t)(a->word[i] - sub);
    }
    while (a->n > 1 && !a->word[a->n-1]) --a->n;
}
static void add(Big *a, const Big *b) {
    uint32_t i; uint64_t carry = 0;
    for (i = 0; i < a->n || i < b->n; ++i) {
        carry += (i < a->n ? a->word[i] : 0u) + (uint64_t)(i < b->n ? b->word[i] : 0u);
        a->word[i] = (uint32_t)carry; carry >>= 32;
    }
    a->n = i;
    if (carry) a->word[a->n++] = (uint32_t)carry;
}
__declspec(safebuffers)
uint32_t jbv_decimal_text(uint64_t bits, int single, uint16_t *out) {
    uint32_t fraction_bits = single ? 23u : 52u, exponent_bits = single ? 8u : 11u;
    uint32_t max_exp = (1u << exponent_bits) - 1, exponent = (uint32_t)(bits >> fraction_bits) & max_exp;
    uint64_t fraction = bits & ((UINT64_C(1) << fraction_bits) - 1), m = fraction;
    int negative = (int)((bits >> (fraction_bits + exponent_bits)) & 1), even;
    int binary_exp, decimal_exp = 0, low, high, cmp;
    Big r, s, lower, upper, temp;
    uint64_t significand = 0;
    uint32_t n = 0, digit, pos = 0, i, length;
    uint16_t digits[24];
    const char *special = 0;
    if (exponent == max_exp) { special = fraction ? "NaN" : "Infinity"; if (fraction) negative = 0; }
    else if (!exponent && !fraction) special = "0.0";
    if (negative) out[pos++] = '-';
    if (special) { for (i = 0; special[i]; ++i) out[pos++] = special[i]; return pos; }
    binary_exp = (exponent ? (int)exponent : 1) - (single ? 127 : 1023) - (int)fraction_bits;
    if (exponent) m |= UINT64_C(1) << fraction_bits;
    even = !(m & 1);
    set(&r, 4 * m); set(&s, 1);
    set(&lower, fraction || exponent <= 1 ? 2 : 1); set(&upper, 2);
    binary_exp -= 2;
    while (binary_exp > 0) { multiply(&r, 2); multiply(&lower, 2); multiply(&upper, 2); --binary_exp; }
    while (binary_exp < 0) { multiply(&s, 2); ++binary_exp; }
    copy(&temp, &s); multiply(&temp, 10);
    while (compare(&r, &temp) >= 0) { copy(&s, &temp); multiply(&temp, 10); ++decimal_exp; }
    while (compare(&r, &s) < 0) { multiply(&r, 10); multiply(&lower, 10); multiply(&upper, 10); --decimal_exp; }
    for (;;) {
        digit = 0;
        while (compare(&r, &s) >= 0) { subtract(&r, &s); ++digit; }
        significand = significand * 10 + digit; ++n;
        cmp = compare(&r, &lower); low = cmp < 0 || (!cmp && even);
        copy(&temp, &r); add(&temp, &upper);
        cmp = compare(&temp, &s); high = cmp > 0 || (!cmp && even);
        if (n >= 2 && (low || high)) {
            copy(&temp, &r); multiply(&temp, 2); cmp = compare(&temp, &s);
            if (high && (!low || cmp > 0 || (!cmp && (significand & 1)))) ++significand;
            break;
        }
        multiply(&r, 10); multiply(&lower, 10); multiply(&upper, 10);
    }
    length = jbv_integer_text(significand, 0, 10, digits);
    if (length > n) ++decimal_exp;
    while (length > 1 && digits[length-1] == '0') --length;
    if (decimal_exp >= -3 && decimal_exp < 7) {
        if (decimal_exp < 0) {
            out[pos++] = '0'; out[pos++] = '.';
            for (i = 1; i < (uint32_t)-decimal_exp; ++i) out[pos++] = '0';
            for (i = 0; i < length; ++i) out[pos++] = digits[i];
        } else {
            uint32_t point = (uint32_t)decimal_exp + 1;
            for (i = 0; i < point || i < length; ++i) {
                if (i == point) out[pos++] = '.';
                out[pos++] = i < length ? digits[i] : '0';
            }
            if (length <= point) { out[pos++] = '.'; out[pos++] = '0'; }
        }
    } else {
        out[pos++] = digits[0]; out[pos++] = '.';
        if (length == 1) out[pos++] = '0';
        for (i = 1; i < length; ++i) out[pos++] = digits[i];
        out[pos++] = 'E';
        pos += jbv_integer_text((uint32_t)(decimal_exp < 0 ? -decimal_exp : decimal_exp), decimal_exp < 0, 10, out + pos);
    }
    return pos;
}

static uint32_t bit_length(const Big *a) {
    uint32_t n=(a->n-1)*32, top=a->word[a->n-1];
    while(top) { ++n; top>>=1; }
    return n;
}
static void shift(Big *a, uint32_t n) { while(n--) multiply(a,2); }
static void half(Big *a) {
    uint32_t i=a->n, carry=0;
    while(i--) { uint32_t next=a->word[i]&1; a->word[i]=(a->word[i]>>1)|(carry<<31); carry=next; }
    while(a->n>1&&!a->word[a->n-1]) --a->n;
}
static void append_digit(Big *a, uint32_t base, uint32_t digit) {
    uint32_t i=0;
    uint64_t carry=digit;
    multiply(a,base);
    while(carry && i<a->n) { carry+=a->word[i]; a->word[i++]=(uint32_t)carry; carry>>=32; }
    if(carry) a->word[a->n++]=(uint32_t)carry;
}
static int ascii_equal(const uint16_t *s, uint32_t n, const char *t) {
    uint32_t i; for(i=0;i<n;i++)if(!t[i]||s[i]!=(uint8_t)t[i])return 0;
    return !t[n];
}
/* Keep 768 significant decimal digits (300 hex). Every binary64 midpoint
 * has <= 768 significant decimal digits; omitted nonzero digits can therefore
 * only break a tie at a retained exact midpoint, never cross another midpoint.
 * Exponents and digit counters use 64 bits, so long inputs cannot wrap them.
 * All buffers are bounded by the binary32/binary64 exponent range. */
__declspec(safebuffers)
JbvStatus jbv_parse_fp(JbvVM *vm, int32_t string, int single, uint64_t *out) {
    JbvTextView text;
    JbvStatus status=jbv_string_view(vm,string,&text);
    uint32_t start=0,end,i,base=10,kept=0,limit=768,digit,any=0,dot=0,sticky=0,sign=0,negative_exp=0;
    int64_t fractional=0,dropped=0,exp=0,power,order;
    uint32_t fraction_bits=single?23u:52u,bias=single?127u:1023u;
    int minimum=single?-126:-1022,maximum=single?127:1023,e,scale,j,cmp;
    uint64_t value=0,sign_bit,inf;
    Big r,s,temp;
    if(status!=JBV_OK)return status;
    end=text.length;
    while(start<end&&text.data[start]<=32)++start;
    while(end>start&&text.data[end-1]<=32)--end;
    if(start==end)goto invalid;
    if(text.data[start]=='+'||text.data[start]=='-')sign=text.data[start++]=='-';
    sign_bit=(uint64_t)sign<<(single?31:63);
    inf=(uint64_t)(single?255:2047)<<fraction_bits;
    if(ascii_equal(text.data+start,end-start,"NaN")) { *out=inf|(UINT64_C(1)<<(fraction_bits-1));return JBV_OK; }
    if(ascii_equal(text.data+start,end-start,"Infinity")) { *out=sign_bit|inf;return JBV_OK; }
    if(start==end)goto invalid;
    if(text.data[end-1]=='f'||text.data[end-1]=='F'||text.data[end-1]=='d'||text.data[end-1]=='D')--end;
    if(start+2<=end&&text.data[start]=='0'&&(text.data[start+1]=='x'||text.data[start+1]=='X')) {base=16;limit=300;start+=2;}
    set(&r,0);set(&s,1);
    for(i=start;i<end;i++) {
        int32_t ch=text.data[i];
        if(ch=='.'&&!dot){dot=1;continue;}
        digit=ch>='0'&&ch<='9'?(uint32_t)(ch-'0'):base==16&&ch>='a'&&ch<='f'?(uint32_t)(ch-'a'+10):base==16&&ch>='A'&&ch<='F'?(uint32_t)(ch-'A'+10):base;
        if(digit>=base)break;
        any=1; if(dot)++fractional;
        if(!kept&&!digit)continue;
        if(kept<limit){append_digit(&r,base,digit);++kept;}
        else{++dropped;sticky|=digit!=0;}
    }
    if(!any)goto invalid;
    if(i<end&&((base==10&&(text.data[i]=='e'||text.data[i]=='E'))||(base==16&&(text.data[i]=='p'||text.data[i]=='P')))) {
        ++i;if(i<end&&(text.data[i]=='+'||text.data[i]=='-'))negative_exp=text.data[i++]=='-';
        start=i;
        for(;i<end&&text.data[i]>='0'&&text.data[i]<='9';i++)if(exp<INT64_C(10000000000))exp=exp*10+text.data[i]-'0';
        if(i==start)goto invalid;
        if(negative_exp)exp=-exp;
    } else if(base==16)goto invalid;
    if(i!=end)goto invalid;
    if(!kept){*out=sign_bit;return JBV_OK;}
    if(base==10) {
        power=exp-fractional+dropped;order=power+kept-1;
        if(order>309){*out=sign_bit|inf;return JBV_OK;}
        if(order< -325){*out=sign_bit;return JBV_OK;}
        while(power>0){multiply(&r,10);--power;}
        while(power<0){multiply(&s,10);++power;}
    } else {
        power=exp-4*fractional+4*dropped;order=power+bit_length(&r)-1;
        if(order>1023){*out=sign_bit|inf;return JBV_OK;}
        if(order< -1075){*out=sign_bit;return JBV_OK;}
        if(power>0)shift(&r,(uint32_t)power);else shift(&s,(uint32_t)-power);
    }
    e=(int)bit_length(&r)-(int)bit_length(&s);
    if(e>=0){copy(&temp,&s);shift(&temp,(uint32_t)e);if(compare(&r,&temp)<0)--e;}
    else{copy(&temp,&r);shift(&temp,(uint32_t)-e);if(compare(&temp,&s)<0)--e;}
    if(e>maximum){*out=sign_bit|inf;return JBV_OK;}
    if(e<minimum-(int)fraction_bits-1){*out=sign_bit;return JBV_OK;}
    scale=(int)fraction_bits-(e<minimum?minimum:e);
    if(scale>=0)shift(&r,(uint32_t)scale);else shift(&s,(uint32_t)-scale);
    copy(&temp,&s);shift(&temp,fraction_bits+1);
    for(j=(int)fraction_bits+1;j>=0;--j){if(compare(&r,&temp)>=0){subtract(&r,&temp);value|=UINT64_C(1)<<j;}half(&temp);}
    multiply(&r,2);cmp=compare(&r,&s);
    if(cmp>0||(!cmp&&(sticky||(value&1))))++value;
    if(e>=minimum) {
        if(value==(UINT64_C(1)<<(fraction_bits+1))){value>>=1;++e;}
        value=e>maximum?inf:((uint64_t)(e+(int)bias)<<fraction_bits)|(value&((UINT64_C(1)<<fraction_bits)-1));
    }
    *out=sign_bit|value;return JBV_OK;
invalid:
    return jbv_throw_named(vm,"java/lang/NumberFormatException",0,JBV_EXCEPTION);
}
#endif

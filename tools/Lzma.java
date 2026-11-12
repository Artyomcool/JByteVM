import java.io.ByteArrayOutputStream;
import java.util.Arrays;

/** LZMA1 for the JARs JByteVM reads (ZIP method 14): an encoder with optimal parsing in the
 * manner of the LZMA SDK (hash-chain match finder, price-driven parse, end marker) and a
 * decoder, used to check every entry and to unpack. Deterministic: the same input, lc, pb
 * and dictionary give the same bytes. */
final class Lzma {
    static final int STATES = 12, POS_SLOT_BITS = 6, START_POS_MODEL = 4, END_POS_MODEL = 14,
        FULL_DISTANCES = 128, ALIGN_BITS = 4, ALIGN_SIZE = 16, LEN_TO_POS_STATES = 4, MIN_LEN = 2, MAX_LEN = 273,
        LOW_BITS = 3, MID_BITS = 3, HIGH_BITS = 8, LOW_SYMBOLS = 8, MID_SYMBOLS = 8, POS_STATES_MAX = 16,
        REPS = 4, OPTS = 4096, INFINITY = 0xFFFFFFF, BIT_MODEL_TOTAL = 1 << 11, MOVE_BITS = 5;

    static int stateChar(int s) { return s < 4 ? 0 : s < 10 ? s - 3 : s - 6; }
    static int stateMatch(int s) { return s < 7 ? 7 : 10; }
    static int stateRep(int s) { return s < 7 ? 8 : 11; }
    static int stateShortRep(int s) { return s < 7 ? 9 : 11; }
    static boolean isChar(int s) { return s < 7; }
    static int lenToPosState(int len) { len -= MIN_LEN; return len < LEN_TO_POS_STATES ? len : LEN_TO_POS_STATES - 1; }
    static int posSlot(int dist) {
        if (dist < 4) return dist;
        int n = 31 - Integer.numberOfLeadingZeros(dist);
        return (n << 1) | ((dist >>> (n - 1)) & 1);
    }

    // ---- prices of bits (1/64 bit units)
    static final int[] PROB_PRICES = new int[BIT_MODEL_TOTAL >>> 2];
    static {
        int bits = 9;
        for (int i = bits - 1; i >= 0; i--) {
            int start = 1 << (bits - i - 1), end = 1 << (bits - i);
            for (int j = start; j < end; j++) PROB_PRICES[j] = (i << 6) + (((end - j) << 6) >>> (bits - i - 1));
        }
    }
    static int price(int prob, int bit) { return PROB_PRICES[(((prob - bit) ^ (-bit)) & (BIT_MODEL_TOTAL - 1)) >>> 2]; }
    static int price0(int prob) { return PROB_PRICES[prob >>> 2]; }
    static int price1(int prob) { return PROB_PRICES[(BIT_MODEL_TOTAL - prob) >>> 2]; }
    static short[] probs(int n) { short[] p = new short[n]; Arrays.fill(p, (short) (BIT_MODEL_TOTAL >>> 1)); return p; }

    // ---- the range encoder
    static final class Range {
        final ByteArrayOutputStream out = new ByteArrayOutputStream();
        long low; int range = -1, cache, cacheSize = 1;
        void shiftLow() {
            int high = (int) (low >>> 32);
            if (high != 0 || low < 0xFF000000L) {
                int temp = cache;
                do { out.write(temp + high); temp = 0xFF; } while (--cacheSize != 0);
                cache = ((int) low) >>> 24;
            }
            cacheSize++;
            low = (low & 0xFFFFFF) << 8;
        }
        void bit(short[] p, int i, int bit) {
            int prob = p[i], bound = (range >>> 11) * prob;
            if (bit == 0) { range = bound; p[i] = (short) (prob + ((BIT_MODEL_TOTAL - prob) >>> MOVE_BITS)); }
            else { low += bound & 0xFFFFFFFFL; range -= bound; p[i] = (short) (prob - (prob >>> MOVE_BITS)); }
            if ((range & 0xFF000000) == 0) { range <<= 8; shiftLow(); }
        }
        void direct(int value, int count) {
            for (int i = count - 1; i >= 0; i--) {
                range >>>= 1;
                if (((value >>> i) & 1) == 1) low += range & 0xFFFFFFFFL;
                if ((range & 0xFF000000) == 0) { range <<= 8; shiftLow(); }
            }
        }
        void flush() { for (int i = 0; i < 5; i++) shiftLow(); }
    }

    // ---- bit trees
    static void tree(Range rc, short[] p, int base, int bits, int symbol) {
        int m = 1;
        for (int i = bits; i > 0; i--) { int bit = (symbol >>> (i - 1)) & 1; rc.bit(p, base + m, bit); m = m << 1 | bit; }
    }
    static void reverseTree(Range rc, short[] p, int base, int bits, int symbol) {
        int m = 1;
        for (int i = 0; i < bits; i++) { int bit = symbol & 1; rc.bit(p, base + m, bit); m = m << 1 | bit; symbol >>= 1; }
    }
    static int treePrice(short[] p, int base, int bits, int symbol) {
        int price = 0, m = 1;
        for (int i = bits; i > 0; i--) { int bit = (symbol >>> (i - 1)) & 1; price += price(p[base + m], bit); m = (m << 1) + bit; }
        return price;
    }
    static int reverseTreePrice(short[] p, int base, int bits, int symbol) {
        int price = 0, m = 1;
        for (int i = bits; i > 0; i--) { int bit = symbol & 1; symbol >>>= 1; price += price(p[base + m], bit); m = m << 1 | bit; }
        return price;
    }

    /** Lengths 2..273: choice bits, then 3/3/8-bit trees; prices cached per position state. */
    static final class Length {
        final short[] choice = probs(2), low = probs(POS_STATES_MAX << LOW_BITS), mid = probs(POS_STATES_MAX << MID_BITS), high = probs(1 << HIGH_BITS);
        final int[] prices = new int[POS_STATES_MAX * (MAX_LEN - MIN_LEN + 1)];
        final int[] counters = new int[POS_STATES_MAX];
        final int tableSize;
        Length(int tableSize, int posStates) { this.tableSize = tableSize; for (int i = 0; i < posStates; i++) update(i); }
        void encode(Range rc, int symbol, int posState) {
            if (symbol < LOW_SYMBOLS) { rc.bit(choice, 0, 0); tree(rc, low, posState << LOW_BITS, LOW_BITS, symbol); }
            else {
                rc.bit(choice, 0, 1);
                if (symbol < LOW_SYMBOLS + MID_SYMBOLS) { rc.bit(choice, 1, 0); tree(rc, mid, posState << MID_BITS, MID_BITS, symbol - LOW_SYMBOLS); }
                else { rc.bit(choice, 1, 1); tree(rc, high, 0, HIGH_BITS, symbol - LOW_SYMBOLS - MID_SYMBOLS); }
            }
            if (--counters[posState] == 0) update(posState);
        }
        void update(int posState) {
            int a0 = price0(choice[0]), a1 = price1(choice[0]), b0 = a1 + price0(choice[1]), b1 = a1 + price1(choice[1]);
            int st = posState * (MAX_LEN - MIN_LEN + 1), i = 0;
            for (; i < LOW_SYMBOLS && i < tableSize; i++) prices[st + i] = a0 + treePrice(low, posState << LOW_BITS, LOW_BITS, i);
            for (; i < LOW_SYMBOLS + MID_SYMBOLS && i < tableSize; i++) prices[st + i] = b0 + treePrice(mid, posState << MID_BITS, MID_BITS, i - LOW_SYMBOLS);
            for (; i < tableSize; i++) prices[st + i] = b1 + treePrice(high, 0, HIGH_BITS, i - LOW_SYMBOLS - MID_SYMBOLS);
            counters[posState] = tableSize;
        }
        int price(int symbol, int posState) { return prices[posState * (MAX_LEN - MIN_LEN + 1) + symbol]; }
    }

    static final class Optimal {
        int state, posPrev, backPrev, price, posPrev2, backPrev2, back0, back1, back2, back3;
        boolean prev1IsChar, prev2;
        void makeChar() { backPrev = -1; prev1IsChar = false; }
        void makeShortRep() { backPrev = 0; prev1IsChar = false; }
        boolean isShortRep() { return backPrev == 0; }
    }

    // ---- the encoder state
    final byte[] buf; final int n, lc, lp, pb, posMask, dictSize, niceLen, depth, distTableSize;
    final Range rc = new Range();
    final short[] isMatch = probs(STATES << 4), isRep = probs(STATES), isRepG0 = probs(STATES), isRepG1 = probs(STATES),
        isRepG2 = probs(STATES), isRep0Long = probs(STATES << 4), posSlots = probs(LEN_TO_POS_STATES << POS_SLOT_BITS),
        posSpecial = probs(FULL_DISTANCES - END_POS_MODEL + 1), align = probs(ALIGN_SIZE), literals;
    final Length lenCoder, repLenCoder;
    final Optimal[] opt = new Optimal[OPTS];
    final int[] reps = new int[REPS], repLens = new int[REPS], dist = new int[REPS], matches = new int[MAX_LEN * 2 + 2];
    final int[] posSlotPrices = new int[LEN_TO_POS_STATES << POS_SLOT_BITS], distancesPrices = new int[LEN_TO_POS_STATES * FULL_DISTANCES],
        alignPrices = new int[ALIGN_SIZE], tempPrices = new int[FULL_DISTANCES];
    int state, previousByte, matchPriceCount, alignPriceCount, additionalOffset, optimumEnd, optimumCurrent, backRes,
        longestMatchLength, numDistancePairs;
    boolean longestMatchWasFound;
    // the match finder: hash chains over the whole input
    int pos;
    final int[] head2 = new int[1 << 16], head3 = new int[1 << 16], head4 = new int[1 << 20], prev;

    Lzma(byte[] data, int lc, int lp, int pb, int dictSize) {
        this.buf = data; this.n = data.length; this.lc = lc; this.lp = lp; this.pb = pb; this.posMask = (1 << pb) - 1;
        this.dictSize = dictSize; this.niceLen = MAX_LEN; this.depth = 512;
        int log = 0; while ((1 << log) < dictSize) log++;
        this.distTableSize = log * 2;
        literals = probs(0x300 << (lc + lp));
        lenCoder = new Length(niceLen + 1 - MIN_LEN, 1 << pb);
        repLenCoder = new Length(niceLen + 1 - MIN_LEN, 1 << pb);
        for (int i = 0; i < OPTS; i++) opt[i] = new Optimal();
        prev = new int[n];
        Arrays.fill(head2, -1); Arrays.fill(head3, -1); Arrays.fill(head4, -1);
    }

    /** The raw LZMA stream of data (with an end marker). */
    static byte[] compress(byte[] data, int lc, int lp, int pb, int dictSize) {
        Lzma e = new Lzma(data, lc, lp, pb, dictSize);
        e.encode();
        return e.rc.out.toByteArray();
    }

    // ---- match finder
    int byteAt(int index) { return buf[pos + index] & 0xFF; }   // relative to the finder's position
    int available() { return n - pos; }
    int matchLen(int index, int distance, int limit) {
        int at = pos + index, from = at - distance - 1;
        if (from < 0) return 0;
        limit = Math.min(limit, n - at);
        int i = 0;
        while (i < limit && buf[at + i] == buf[from + i]) i++;
        return i;
    }
    int hash2(int p) { return (buf[p] & 0xFF) | (buf[p + 1] & 0xFF) << 8; }
    int hash3(int p) { return ((buf[p] & 0xFF) * 506832829 + (buf[p + 1] & 0xFF) * 2654435 + (buf[p + 2] & 0xFF)) >>> 0 & 0xFFFF; }
    int hash4(int p) { int v = (buf[p] & 0xFF) | (buf[p + 1] & 0xFF) << 8 | (buf[p + 2] & 0xFF) << 16 | (buf[p + 3] & 0xFF) << 24; return (v * 0x9E3779B1) >>> 12; }
    void insert(int p) {
        if (n - p < 4) return;
        int h4 = hash4(p);
        prev[p] = head4[h4]; head4[h4] = p; head3[hash3(p)] = p; head2[hash2(p)] = p;
    }
    /** Pairs (length, distance - 1) of strictly increasing length at the finder's position; moves on. */
    int findMatches() {
        int p = pos, count = 0, limit = Math.min(niceLen, n - p);
        if (limit < 4) { pos++; return 0; }
        int maxLen = 1;
        int c2 = head2[hash2(p)], c3 = head3[hash3(p)];
        int d2 = p - c2, d3 = p - c3;
        if (c2 >= 0 && d2 <= dictSize && buf[c2] == buf[p] && buf[c2 + 1] == buf[p + 1]) { maxLen = 2; matches[count++] = 2; matches[count++] = d2 - 1; }
        if (c3 >= 0 && d3 != d2 && d3 <= dictSize && buf[c3] == buf[p] && buf[c3 + 1] == buf[p + 1] && buf[c3 + 2] == buf[p + 2]) {
            maxLen = 3; matches[count++] = 3; matches[count++] = d3 - 1; d2 = d3;
        }
        if (count != 0) {   // the short match's real length
            int from = p - d2;
            while (maxLen < limit && buf[from + maxLen] == buf[p + maxLen]) maxLen++;
            matches[count - 2] = maxLen;
        }
        if (maxLen < limit) {
            int cur = head4[hash4(p)];
            for (int steps = depth; cur >= 0 && steps-- > 0; cur = prev[cur]) {
                int d = p - cur;
                if (d > dictSize) break;
                if (buf[cur + maxLen] != buf[p + maxLen] || buf[cur] != buf[p]) continue;
                int len = 0;
                while (len < limit && buf[cur + len] == buf[p + len]) len++;
                if (len > maxLen) {
                    maxLen = len;
                    if (count != 0 && matches[count - 1] == d - 1) matches[count - 2] = len;
                    else { matches[count++] = len; matches[count++] = d - 1; }
                    if (len == limit) break;
                }
            }
        }
        insert(p);
        pos++;
        return count;
    }
    void skip(int num) { while (num-- > 0) { insert(pos); pos++; } }

    int readMatchDistances() {
        int lenRes = 0;
        numDistancePairs = findMatches();
        if (numDistancePairs > 0) {
            lenRes = matches[numDistancePairs - 2];
            if (lenRes == niceLen) lenRes += matchLen(lenRes - 1, matches[numDistancePairs - 1], MAX_LEN - lenRes);
        }
        additionalOffset++;
        return lenRes;
    }
    void movePos(int num) { if (num > 0) { skip(num); additionalOffset += num; } }

    // ---- literals
    int literalBase(int position, int prevByte) { return 0x300 * (((position & ((1 << lp) - 1)) << lc) + ((prevByte & 0xFF) >>> (8 - lc))); }
    void literal(int base, int symbol) {
        int context = 1;
        for (int i = 7; i >= 0; i--) { int bit = (symbol >>> i) & 1; rc.bit(literals, base + context, bit); context = context << 1 | bit; }
    }
    void literalMatched(int base, int matchByte, int symbol) {
        int context = 1; boolean same = true;
        for (int i = 7; i >= 0; i--) {
            int bit = (symbol >>> i) & 1, index = context;
            if (same) { int matchBit = (matchByte >>> i) & 1; index += (1 + matchBit) << 8; same = matchBit == bit; }
            rc.bit(literals, base + index, bit);
            context = context << 1 | bit;
        }
    }
    int literalPrice(int base, boolean matchMode, int matchByte, int symbol) {
        int price = 0, context = 1, i = 7;
        if (matchMode) for (; i >= 0; i--) {
            int matchBit = (matchByte >>> i) & 1, bit = (symbol >>> i) & 1;
            price += price(literals[base + ((1 + matchBit) << 8) + context], bit);
            context = context << 1 | bit;
            if (matchBit != bit) { i--; break; }
        }
        for (; i >= 0; i--) { int bit = (symbol >>> i) & 1; price += price(literals[base + context], bit); context = context << 1 | bit; }
        return price;
    }

    // ---- prices of matches
    int repLen1Price(int state, int posState) { return price0(isRepG0[state]) + price0(isRep0Long[(state << 4) + posState]); }
    int pureRepPrice(int repIndex, int state, int posState) {
        if (repIndex == 0) return price0(isRepG0[state]) + price1(isRep0Long[(state << 4) + posState]);
        int price = price1(isRepG0[state]);
        if (repIndex == 1) return price + price0(isRepG1[state]);
        return price + price1(isRepG1[state]) + price(isRepG2[state], repIndex - 2);
    }
    int repPrice(int repIndex, int len, int state, int posState) { return repLenCoder.price(len - MIN_LEN, posState) + pureRepPrice(repIndex, state, posState); }
    int posLenPrice(int distance, int len, int posState) {
        int lps = lenToPosState(len), price;
        if (distance < FULL_DISTANCES) price = distancesPrices[lps * FULL_DISTANCES + distance];
        else price = posSlotPrices[(lps << POS_SLOT_BITS) + posSlot(distance)] + alignPrices[distance & (ALIGN_SIZE - 1)];
        return price + lenCoder.price(len - MIN_LEN, posState);
    }
    void fillDistancesPrices() {
        for (int i = START_POS_MODEL; i < FULL_DISTANCES; i++) {
            int slot = posSlot(i), footer = (slot >>> 1) - 1, base = (2 | (slot & 1)) << footer;
            tempPrices[i] = reverseTreePrice(posSpecial, base - slot - 1, footer, i - base);
        }
        for (int lps = 0; lps < LEN_TO_POS_STATES; lps++) {
            int st = lps << POS_SLOT_BITS;
            for (int slot = 0; slot < distTableSize; slot++) posSlotPrices[st + slot] = treePrice(posSlots, st, POS_SLOT_BITS, slot);
            for (int slot = END_POS_MODEL; slot < distTableSize; slot++) posSlotPrices[st + slot] += ((slot >>> 1) - 1 - ALIGN_BITS) << 6;
            int st2 = lps * FULL_DISTANCES, i = 0;
            for (; i < START_POS_MODEL; i++) distancesPrices[st2 + i] = posSlotPrices[st + i];
            for (; i < FULL_DISTANCES; i++) distancesPrices[st2 + i] = posSlotPrices[st + posSlot(i)] + tempPrices[i];
        }
        matchPriceCount = 0;
    }
    void fillAlignPrices() {
        for (int i = 0; i < ALIGN_SIZE; i++) alignPrices[i] = reverseTreePrice(align, 0, ALIGN_BITS, i);
        alignPriceCount = 0;
    }

    // ---- optimal parsing
    int backward(int cur) {
        optimumEnd = cur;
        int posMem = opt[cur].posPrev, backMem = opt[cur].backPrev;
        do {
            if (opt[cur].prev1IsChar) {
                opt[posMem].makeChar();
                opt[posMem].posPrev = posMem - 1;
                if (opt[cur].prev2) {
                    opt[posMem - 1].prev1IsChar = false;
                    opt[posMem - 1].posPrev = opt[cur].posPrev2;
                    opt[posMem - 1].backPrev = opt[cur].backPrev2;
                }
            }
            int posPrev = posMem, backCur = backMem;
            backMem = opt[posPrev].backPrev;
            posMem = opt[posPrev].posPrev;
            opt[posPrev].backPrev = backCur;
            opt[posPrev].posPrev = cur;
            cur = posPrev;
        } while (cur > 0);
        backRes = opt[0].backPrev;
        optimumCurrent = opt[0].posPrev;
        return optimumCurrent;
    }

    int getOptimum(int position) {
        if (optimumEnd != optimumCurrent) {
            int lenRes = opt[optimumCurrent].posPrev - optimumCurrent;
            backRes = opt[optimumCurrent].backPrev;
            optimumCurrent = opt[optimumCurrent].posPrev;
            return lenRes;
        }
        optimumCurrent = optimumEnd = 0;
        int lenMain;
        if (!longestMatchWasFound) lenMain = readMatchDistances();
        else { lenMain = longestMatchLength; longestMatchWasFound = false; }
        int pairs = numDistancePairs;
        int availableBytes = available() + 1;
        if (availableBytes < 2) { backRes = -1; return 1; }
        if (availableBytes > MAX_LEN) availableBytes = MAX_LEN;
        int repMaxIndex = 0;
        for (int i = 0; i < REPS; i++) {
            dist[i] = reps[i];
            repLens[i] = matchLen(-1, dist[i], MAX_LEN);
            if (repLens[i] > repLens[repMaxIndex]) repMaxIndex = i;
        }
        if (repLens[repMaxIndex] >= niceLen) {
            backRes = repMaxIndex;
            int lenRes = repLens[repMaxIndex];
            movePos(lenRes - 1);
            return lenRes;
        }
        if (lenMain >= niceLen) {
            backRes = matches[pairs - 1] + REPS;
            movePos(lenMain - 1);
            return lenMain;
        }
        int currentByte = byteAt(-1), matchByte = pos - dist[0] - 2 >= 0 ? byteAt(-dist[0] - 2) : 0;
        if (lenMain < 2 && currentByte != matchByte && repLens[repMaxIndex] < 2) { backRes = -1; return 1; }
        opt[0].state = state;
        int posState = position & posMask;
        opt[1].price = price0(isMatch[(state << 4) + posState]) + literalPrice(literalBase(position, previousByte), !isChar(state), matchByte, currentByte);
        opt[1].makeChar();
        int matchPrice = price1(isMatch[(state << 4) + posState]);
        int repMatchPrice = matchPrice + price1(isRep[state]);
        if (matchByte == currentByte) {
            int shortRepPrice = repMatchPrice + repLen1Price(state, posState);
            if (shortRepPrice < opt[1].price) { opt[1].price = shortRepPrice; opt[1].makeShortRep(); }
        }
        int lenEnd = Math.max(lenMain, repLens[repMaxIndex]);
        if (lenEnd < 2) { backRes = opt[1].backPrev; return 1; }
        opt[1].posPrev = 0;
        opt[0].back0 = dist[0]; opt[0].back1 = dist[1]; opt[0].back2 = dist[2]; opt[0].back3 = dist[3];
        for (int len = lenEnd; len >= 2; len--) opt[len].price = INFINITY;
        for (int i = 0; i < REPS; i++) {
            int repLen = repLens[i];
            if (repLen < 2) continue;
            int price = repMatchPrice + pureRepPrice(i, state, posState);
            do {
                int curAndLenPrice = price + repLenCoder.price(repLen - 2, posState);
                Optimal o = opt[repLen];
                if (curAndLenPrice < o.price) { o.price = curAndLenPrice; o.posPrev = 0; o.backPrev = i; o.prev1IsChar = false; }
            } while (--repLen >= 2);
        }
        int normalMatchPrice = matchPrice + price0(isRep[state]);
        int len = repLens[0] >= 2 ? repLens[0] + 1 : 2;
        if (len <= lenMain) {
            int offs = 0;
            while (len > matches[offs]) offs += 2;
            for (;; len++) {
                int distance = matches[offs + 1];
                int curAndLenPrice = normalMatchPrice + posLenPrice(distance, len, posState);
                Optimal o = opt[len];
                if (curAndLenPrice < o.price) { o.price = curAndLenPrice; o.posPrev = 0; o.backPrev = distance + REPS; o.prev1IsChar = false; }
                if (len == matches[offs]) { offs += 2; if (offs == pairs) break; }
            }
        }
        int cur = 0;
        while (true) {
            cur++;
            if (cur == lenEnd) return backward(cur);
            int newLen = readMatchDistances();
            pairs = numDistancePairs;
            if (newLen >= niceLen) { longestMatchLength = newLen; longestMatchWasFound = true; return backward(cur); }
            position++;
            int posPrev = opt[cur].posPrev, st;
            if (opt[cur].prev1IsChar) {
                posPrev--;
                if (opt[cur].prev2) {
                    st = opt[opt[cur].posPrev2].state;
                    st = opt[cur].backPrev2 < REPS ? stateRep(st) : stateMatch(st);
                } else st = opt[posPrev].state;
                st = stateChar(st);
            } else st = opt[posPrev].state;
            if (posPrev == cur - 1) st = opt[cur].isShortRep() ? stateShortRep(st) : stateChar(st);
            else {
                int back;
                if (opt[cur].prev1IsChar && opt[cur].prev2) { posPrev = opt[cur].posPrev2; back = opt[cur].backPrev2; st = stateRep(st); }
                else { back = opt[cur].backPrev; st = back < REPS ? stateRep(st) : stateMatch(st); }
                Optimal o = opt[posPrev];
                if (back < REPS) {
                    if (back == 0) { dist[0] = o.back0; dist[1] = o.back1; dist[2] = o.back2; dist[3] = o.back3; }
                    else if (back == 1) { dist[0] = o.back1; dist[1] = o.back0; dist[2] = o.back2; dist[3] = o.back3; }
                    else if (back == 2) { dist[0] = o.back2; dist[1] = o.back0; dist[2] = o.back1; dist[3] = o.back3; }
                    else { dist[0] = o.back3; dist[1] = o.back0; dist[2] = o.back1; dist[3] = o.back2; }
                } else { dist[0] = back - REPS; dist[1] = o.back0; dist[2] = o.back1; dist[3] = o.back2; }
            }
            Optimal now = opt[cur];
            now.state = st; now.back0 = dist[0]; now.back1 = dist[1]; now.back2 = dist[2]; now.back3 = dist[3];
            int curPrice = now.price;
            currentByte = byteAt(-1);
            matchByte = pos - dist[0] - 2 >= 0 ? byteAt(-dist[0] - 2) : 0;
            posState = position & posMask;
            int curAnd1Price = curPrice + price0(isMatch[(st << 4) + posState])
                + literalPrice(literalBase(position, byteAt(-2)), !isChar(st), matchByte, currentByte);
            Optimal next = opt[cur + 1];
            boolean nextIsChar = false;
            if (curAnd1Price < next.price) { next.price = curAnd1Price; next.posPrev = cur; next.makeChar(); nextIsChar = true; }
            matchPrice = curPrice + price1(isMatch[(st << 4) + posState]);
            repMatchPrice = matchPrice + price1(isRep[st]);
            if (matchByte == currentByte && !(next.posPrev < cur && next.backPrev == 0)) {
                int shortRepPrice = repMatchPrice + repLen1Price(st, posState);
                if (shortRepPrice <= next.price) { next.price = shortRepPrice; next.posPrev = cur; next.makeShortRep(); nextIsChar = true; }
            }
            int availableFull = Math.min(OPTS - 1 - cur, available() + 1);
            availableBytes = availableFull;
            if (availableBytes < 2) continue;
            if (availableBytes > niceLen) availableBytes = niceLen;
            if (!nextIsChar && matchByte != currentByte) {   // a literal, then rep0
                int t = Math.min(availableFull - 1, niceLen);
                int lenTest2 = matchLen(0, dist[0], t);
                if (lenTest2 >= 2) {
                    int st2 = stateChar(st), posStateNext = (position + 1) & posMask;
                    int nextRepMatchPrice = curAnd1Price + price1(isMatch[(st2 << 4) + posStateNext]) + price1(isRep[st2]);
                    int offset = cur + 1 + lenTest2;
                    while (lenEnd < offset) opt[++lenEnd].price = INFINITY;
                    int curAndLenPrice = nextRepMatchPrice + repPrice(0, lenTest2, st2, posStateNext);
                    Optimal o = opt[offset];
                    if (curAndLenPrice < o.price) { o.price = curAndLenPrice; o.posPrev = cur + 1; o.backPrev = 0; o.prev1IsChar = true; o.prev2 = false; }
                }
            }
            int startLen = 2;
            for (int repIndex = 0; repIndex < REPS; repIndex++) {
                int lenTest = matchLen(-1, dist[repIndex], availableBytes);
                if (lenTest < 2) continue;
                int lenTestTemp = lenTest;
                do {
                    while (lenEnd < cur + lenTest) opt[++lenEnd].price = INFINITY;
                    int curAndLenPrice = repMatchPrice + repPrice(repIndex, lenTest, st, posState);
                    Optimal o = opt[cur + lenTest];
                    if (curAndLenPrice < o.price) { o.price = curAndLenPrice; o.posPrev = cur; o.backPrev = repIndex; o.prev1IsChar = false; }
                } while (--lenTest >= 2);
                lenTest = lenTestTemp;
                if (repIndex == 0) startLen = lenTest + 1;
                if (lenTest < availableFull) {   // rep, a literal, then rep0
                    int t = Math.min(availableFull - 1 - lenTest, niceLen);
                    int lenTest2 = matchLen(lenTest, dist[repIndex], t);
                    if (lenTest2 >= 2) {
                        int st2 = stateRep(st), posStateNext = (position + lenTest) & posMask;
                        int curAndLenCharPrice = repMatchPrice + repPrice(repIndex, lenTest, st, posState)
                            + price0(isMatch[(st2 << 4) + posStateNext])
                            + literalPrice(literalBase(position + lenTest, byteAt(lenTest - 2)), true,
                                byteAt(lenTest - 1 - (dist[repIndex] + 1)), byteAt(lenTest - 1));
                        st2 = stateChar(st2);
                        posStateNext = (position + lenTest + 1) & posMask;
                        int nextMatchPrice = curAndLenCharPrice + price1(isMatch[(st2 << 4) + posStateNext]);
                        int nextRepMatchPrice = nextMatchPrice + price1(isRep[st2]);
                        int offset = lenTest + 1 + lenTest2;
                        while (lenEnd < cur + offset) opt[++lenEnd].price = INFINITY;
                        int curAndLenPrice = nextRepMatchPrice + repPrice(0, lenTest2, st2, posStateNext);
                        Optimal o = opt[cur + offset];
                        if (curAndLenPrice < o.price) {
                            o.price = curAndLenPrice; o.posPrev = cur + lenTest + 1; o.backPrev = 0;
                            o.prev1IsChar = true; o.prev2 = true; o.posPrev2 = cur; o.backPrev2 = repIndex;
                        }
                    }
                }
            }
            if (newLen > availableBytes) {
                newLen = availableBytes;
                for (pairs = 0; newLen > matches[pairs]; pairs += 2) {}
                matches[pairs] = newLen;
                pairs += 2;
            }
            if (newLen >= startLen) {
                normalMatchPrice = matchPrice + price0(isRep[st]);
                while (lenEnd < cur + newLen) opt[++lenEnd].price = INFINITY;
                int offs = 0;
                while (startLen > matches[offs]) offs += 2;
                for (int lenTest = startLen;; lenTest++) {
                    int curBack = matches[offs + 1];
                    int curAndLenPrice = normalMatchPrice + posLenPrice(curBack, lenTest, posState);
                    Optimal o = opt[cur + lenTest];
                    if (curAndLenPrice < o.price) { o.price = curAndLenPrice; o.posPrev = cur; o.backPrev = curBack + REPS; o.prev1IsChar = false; }
                    if (lenTest == matches[offs]) {
                        if (lenTest < availableFull) {   // match, a literal, then rep0
                            int t = Math.min(availableFull - 1 - lenTest, niceLen);
                            int lenTest2 = matchLen(lenTest, curBack, t);
                            if (lenTest2 >= 2) {
                                int st2 = stateMatch(st), posStateNext = (position + lenTest) & posMask;
                                int curAndLenCharPrice = curAndLenPrice + price0(isMatch[(st2 << 4) + posStateNext])
                                    + literalPrice(literalBase(position + lenTest, byteAt(lenTest - 2)), true,
                                        byteAt(lenTest - (curBack + 1) - 1), byteAt(lenTest - 1));
                                st2 = stateChar(st2);
                                posStateNext = (position + lenTest + 1) & posMask;
                                int nextMatchPrice = curAndLenCharPrice + price1(isMatch[(st2 << 4) + posStateNext]);
                                int nextRepMatchPrice = nextMatchPrice + price1(isRep[st2]);
                                int offset = lenTest + 1 + lenTest2;
                                while (lenEnd < cur + offset) opt[++lenEnd].price = INFINITY;
                                curAndLenPrice = nextRepMatchPrice + repPrice(0, lenTest2, st2, posStateNext);
                                o = opt[cur + offset];
                                if (curAndLenPrice < o.price) {
                                    o.price = curAndLenPrice; o.posPrev = cur + lenTest + 1; o.backPrev = 0;
                                    o.prev1IsChar = true; o.prev2 = true; o.posPrev2 = cur; o.backPrev2 = curBack + REPS;
                                }
                            }
                        }
                        offs += 2;
                        if (offs == pairs) break;
                    }
                }
            }
        }
    }

    // ---- the stream
    void encode() {
        fillDistancesPrices(); fillAlignPrices();
        int nowPos = 0;
        if (n > 0) {   // the first byte is a literal
            readMatchDistances();
            rc.bit(isMatch, 0, 0);
            int b = buf[0] & 0xFF;
            literal(literalBase(0, 0), b);
            state = stateChar(state);
            previousByte = b;
            additionalOffset--;
            nowPos++;
        }
        while (nowPos < n) {
            int len = getOptimum(nowPos), back = backRes, posState = nowPos & posMask, complex = (state << 4) + posState;
            if (len == 1 && back == -1) {
                rc.bit(isMatch, complex, 0);
                int b = buf[nowPos] & 0xFF, base = literalBase(nowPos, previousByte);
                if (!isChar(state)) literalMatched(base, buf[nowPos - reps[0] - 1] & 0xFF, b);
                else literal(base, b);
                previousByte = b;
                state = stateChar(state);
            } else {
                rc.bit(isMatch, complex, 1);
                if (back < REPS) {
                    rc.bit(isRep, state, 1);
                    if (back == 0) { rc.bit(isRepG0, state, 0); rc.bit(isRep0Long, complex, len == 1 ? 0 : 1); }
                    else {
                        rc.bit(isRepG0, state, 1);
                        if (back == 1) rc.bit(isRepG1, state, 0);
                        else { rc.bit(isRepG1, state, 1); rc.bit(isRepG2, state, back - 2); }
                    }
                    if (len == 1) state = stateShortRep(state);
                    else { repLenCoder.encode(rc, len - MIN_LEN, posState); state = stateRep(state); }
                    int distance = reps[back];
                    if (back != 0) { for (int i = back; i >= 1; i--) reps[i] = reps[i - 1]; reps[0] = distance; }
                } else {
                    rc.bit(isRep, state, 0);
                    state = stateMatch(state);
                    lenCoder.encode(rc, len - MIN_LEN, posState);
                    distance(back - REPS, len);
                    for (int i = REPS - 1; i >= 1; i--) reps[i] = reps[i - 1];
                    reps[0] = back - REPS;
                    matchPriceCount++;
                }
                previousByte = buf[nowPos + len - 1] & 0xFF;
            }
            additionalOffset -= len;
            nowPos += len;
            if (additionalOffset == 0) {
                if (matchPriceCount >= 1 << 7) fillDistancesPrices();
                if (alignPriceCount >= ALIGN_SIZE) fillAlignPrices();
            }
        }
        // the end marker: a match of distance 0xFFFFFFFF
        int posState = nowPos & posMask;
        rc.bit(isMatch, (state << 4) + posState, 1);
        rc.bit(isRep, state, 0);
        state = stateMatch(state);
        lenCoder.encode(rc, 0, posState);
        distance(-1, MIN_LEN);
        rc.flush();
    }
    void distance(int distance, int len) {
        int slot = distance == -1 ? (1 << POS_SLOT_BITS) - 1 : posSlot(distance);
        tree(rc, posSlots, lenToPosState(len) << POS_SLOT_BITS, POS_SLOT_BITS, slot);
        if (slot >= START_POS_MODEL) {
            int footer = (slot >>> 1) - 1, base = (2 | (slot & 1)) << footer, reduced = distance - base;
            if (slot < END_POS_MODEL) reverseTree(rc, posSpecial, base - slot - 1, footer, reduced);
            else {
                rc.direct(reduced >>> ALIGN_BITS, footer - ALIGN_BITS);
                reverseTree(rc, align, 0, ALIGN_BITS, reduced & (ALIGN_SIZE - 1));
                alignPriceCount++;
            }
        }
    }

    // ---- the decoder (checks and unpacking)
    static byte[] decompress(byte[] in, int offset, int lc, int lp, int pb, int size) {
        byte[] out = new byte[size];
        int[] at = {offset + 5};
        int code = 0;
        for (int i = 1; i < 5; i++) code = code << 8 | (in[offset + i] & 0xFF);
        int[] rr = {-1, code};
        short[] isMatch = probs(STATES << 4), isRep = probs(STATES), g0 = probs(STATES), g1 = probs(STATES), g2 = probs(STATES),
            rep0Long = probs(STATES << 4), slots = probs(LEN_TO_POS_STATES << POS_SLOT_BITS),
            special = probs(FULL_DISTANCES - END_POS_MODEL + 1), align = probs(ALIGN_SIZE), lit = probs(0x300 << (lc + lp));
        short[][] lens = {probs(2), probs(POS_STATES_MAX << LOW_BITS), probs(POS_STATES_MAX << MID_BITS), probs(1 << HIGH_BITS)};
        short[][] repLens = {probs(2), probs(POS_STATES_MAX << LOW_BITS), probs(POS_STATES_MAX << MID_BITS), probs(1 << HIGH_BITS)};
        int state = 0, r0 = 0, r1 = 0, r2 = 0, r3 = 0, n = 0, pbMask = (1 << pb) - 1, lpMask = (1 << lp) - 1;
        while (n < size) {
            int posState = n & pbMask;
            if (dbit(in, at, rr, isMatch, (state << 4) + posState) == 0) {
                int prevByte = n > 0 ? out[n - 1] & 0xFF : 0;
                int base = 0x300 * (((n & lpMask) << lc) + (prevByte >>> (8 - lc))), symbol = 1;
                if (!isChar(state)) {
                    int matchByte = out[n - r0 - 1] & 0xFF;
                    while (symbol < 0x100) {
                        int matchBit = (matchByte >>> 7) & 1; matchByte <<= 1;
                        int bit = dbit(in, at, rr, lit, base + ((1 + matchBit) << 8) + symbol);
                        symbol = symbol << 1 | bit;
                        if (matchBit != bit) break;
                    }
                }
                while (symbol < 0x100) symbol = symbol << 1 | dbit(in, at, rr, lit, base + symbol);
                out[n++] = (byte) symbol;
                state = stateChar(state);
                continue;
            }
            int len;
            if (dbit(in, at, rr, isRep, state) == 1) {
                if (dbit(in, at, rr, g0, state) == 0) {
                    if (dbit(in, at, rr, rep0Long, (state << 4) + posState) == 0) {
                        state = stateShortRep(state);
                        out[n] = out[n - r0 - 1]; n++;
                        continue;
                    }
                } else {
                    int d;
                    if (dbit(in, at, rr, g1, state) == 0) d = r1;
                    else { if (dbit(in, at, rr, g2, state) == 0) d = r2; else { d = r3; r3 = r2; } r2 = r1; }
                    r1 = r0; r0 = d;
                }
                len = dlen(in, at, rr, repLens, posState);
                state = stateRep(state);
            } else {
                r3 = r2; r2 = r1; r1 = r0;
                len = dlen(in, at, rr, lens, posState);
                state = stateMatch(state);
                int slot = dtree(in, at, rr, slots, lenToPosState(len + MIN_LEN) << POS_SLOT_BITS, POS_SLOT_BITS);
                if (slot < START_POS_MODEL) r0 = slot;
                else {
                    int footer = (slot >>> 1) - 1;
                    r0 = (2 | (slot & 1)) << footer;
                    if (slot < END_POS_MODEL) r0 += dreverse(in, at, rr, special, r0 - slot - 1, footer);
                    else {
                        for (int i = footer - ALIGN_BITS; i > 0; i--) {
                            rr[0] >>>= 1;
                            if (Integer.compareUnsigned(rr[1], rr[0]) >= 0) { rr[1] -= rr[0]; r0 += 1 << (i - 1 + ALIGN_BITS); }
                            if ((rr[0] & 0xFF000000) == 0) { rr[0] <<= 8; rr[1] = rr[1] << 8 | (in[at[0]++] & 0xFF); }
                        }
                        r0 += dreverse(in, at, rr, align, 0, ALIGN_BITS);
                        if (r0 == -1) break;   // the end marker
                    }
                }
            }
            len += MIN_LEN;
            if (n - r0 - 1 < 0 || n + len > size) throw new IllegalStateException("bad LZMA data");
            for (int i = 0; i < len; i++, n++) out[n] = out[n - r0 - 1];
        }
        return out;
    }
    static int dbit(byte[] in, int[] at, int[] rr, short[] p, int i) {
        int prob = p[i], bound = (rr[0] >>> 11) * prob, bit;
        if (Integer.compareUnsigned(rr[1], bound) < 0) { rr[0] = bound; p[i] = (short) (prob + ((BIT_MODEL_TOTAL - prob) >>> MOVE_BITS)); bit = 0; }
        else { rr[0] -= bound; rr[1] -= bound; p[i] = (short) (prob - (prob >>> MOVE_BITS)); bit = 1; }
        if ((rr[0] & 0xFF000000) == 0) { rr[0] <<= 8; rr[1] = rr[1] << 8 | (at[0] < in.length ? in[at[0]++] & 0xFF : 0); }
        return bit;
    }
    static int dtree(byte[] in, int[] at, int[] rr, short[] p, int base, int bits) {
        int m = 1;
        for (int i = 0; i < bits; i++) m = m << 1 | dbit(in, at, rr, p, base + m);
        return m - (1 << bits);
    }
    static int dreverse(byte[] in, int[] at, int[] rr, short[] p, int base, int bits) {
        int m = 1, symbol = 0;
        for (int i = 0; i < bits; i++) { int bit = dbit(in, at, rr, p, base + m); m = m << 1 | bit; symbol |= bit << i; }
        return symbol;
    }
    static int dlen(byte[] in, int[] at, int[] rr, short[][] c, int posState) {
        if (dbit(in, at, rr, c[0], 0) == 0) return dtree(in, at, rr, c[1], posState << LOW_BITS, LOW_BITS);
        if (dbit(in, at, rr, c[0], 1) == 0) return LOW_SYMBOLS + dtree(in, at, rr, c[2], posState << MID_BITS, MID_BITS);
        return LOW_SYMBOLS + MID_SYMBOLS + dtree(in, at, rr, c[3], 0, HIGH_BITS);
    }
}

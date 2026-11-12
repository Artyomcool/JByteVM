package p28;

/** Double/Float toString and parsing over random bit patterns and edge values, against HotSpot. */
public final class Main {
    public static String run() {
        long seed = 0x9E3779B97F4A7C15L, h = 1;
        StringBuilder sample = new StringBuilder();
        double[] edges = {0.0, -0.0, 1.0, -1.0, 0.1, 1e7, 9999999.0, 1e-3, 9.999e-4, Double.MIN_VALUE, Double.MAX_VALUE, Double.MIN_NORMAL,
            Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 2e-323, 1.0E23, 4.35E-1, 100.0, 123456789.0, 5e-324, 1.7976931348623157E308};
        for (double d : edges) { String s = Double.toString(d); sample.append(s).append(' '); h = h * 31 + s.hashCode(); if (Double.parseDouble(s) != d && d == d) return "roundtrip " + s; }
        float[] fedges = {0f, -0f, 1f, 0.1f, 1e7f, 1e-3f, Float.MIN_VALUE, Float.MAX_VALUE, Float.MIN_NORMAL, Float.NaN, 3.4028235E38f, 1.17549435E-38f, 16777216f};
        for (float f : fedges) { String s = Float.toString(f); sample.append(s).append(' '); h = h * 31 + s.hashCode(); if (Float.parseFloat(s) != f && f == f) return "froundtrip " + s; }
        for (int i = 0; i < 100000; i++) {
            seed = seed * 6364136223846793005L + 1442695040888963407L;
            double d = Double.longBitsToDouble(seed);
            String s = Double.toString(d);
            h = h * 31 + s.hashCode();
            if (d == d && Double.parseDouble(s) != d) return "roundtrip " + s;
            float f = Float.intBitsToFloat((int) (seed >>> 17));
            String t = Float.toString(f);
            h = h * 31 + t.hashCode();
            if (f == f && Float.parseFloat(t) != f) return "froundtrip " + t;
            if (i % 20000 == 0) sample.append(s).append(' ').append(t).append(' ');
        }
        String[] inputs = {"0x1.8p1", "0X.8P-1074", "0x1p-1075", "0x1.0000000000001p0", "-0x1.fffffffffffffp1023", "0x1.fffffffffffff8p1023",
            "2.4703282292062327208828439643411068618252990130716238221279284125033775364e-324", "2.4703282292062327e-324", "4.9406564584124654e-324",
            "1.7976931348623158e308", "1.7976931348623159e308", "9007199254740993", "9007199254740993.000000000000000000000000000001",
            "  12.5e+3f ", "-0", "+.5", "5.", "1e400", "1e-400", "123456789012345678901234567890e-20", "0.1D", "NaN", "-Infinity", "1_0", "",
            "e5", ".", "0x", "0x1", "1e", "--1", "1.2.3", "0x1.8p", "Infinityx", " - 1", "1e2147483648", "1e-99999999999", "0.000000000000000000000000000000000000000000001e45"};
        for (String in : inputs) {
            String d, f;
            try { d = Double.toString(Double.parseDouble(in)); } catch (NumberFormatException e) { d = "NFE"; }
            try { f = Float.toString(Float.parseFloat(in)); } catch (NumberFormatException e) { f = "NFE"; }
            sample.append('[').append(in).append(' ').append(d).append(' ').append(f).append(']');
        }
        return sample.append(h).toString();
    }
}

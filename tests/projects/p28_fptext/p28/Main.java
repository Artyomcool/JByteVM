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
        return sample.append(h).toString();
    }
}

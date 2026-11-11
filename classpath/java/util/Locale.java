package java.util;
/** Minimal Locale: identifies a locale but formatting and case mapping always behave as
 * Locale.ROOT in this runtime ('.' decimal separator, no language-specific casing). */
public final class Locale implements java.io.Serializable {
    private final String language, country, variant;
    public static final Locale ROOT = new Locale("", "", ""), ENGLISH = new Locale("en", "", ""), US = new Locale("en", "US", ""),
        UK = new Locale("en", "GB", ""), GERMAN = new Locale("de", "", ""), GERMANY = new Locale("de", "DE", ""), FRENCH = new Locale("fr", "", ""),
        FRANCE = new Locale("fr", "FR", ""), CHINESE = new Locale("zh", "", ""), JAPANESE = new Locale("ja", "", "");
    private static Locale fallback = ROOT;
    public Locale(String language) { this(language, "", ""); }
    public Locale(String language, String country) { this(language, country, ""); }
    public Locale(String language, String country, String variant) {
        this.language = Objects.requireNonNull(language).toLowerCase(); this.country = Objects.requireNonNull(country).toUpperCase(); this.variant = Objects.requireNonNull(variant);
    }
    public static Locale of(String language) { return new Locale(language); }
    public static Locale of(String language, String country) { return new Locale(language, country); }
    public static Locale forLanguageTag(String tag) { int dash = tag.indexOf('-'); return dash < 0 ? new Locale(tag) : new Locale(tag.substring(0, dash), tag.substring(dash + 1)); }
    public static Locale getDefault() { return fallback; }
    public static void setDefault(Locale locale) { fallback = Objects.requireNonNull(locale); }
    public String getLanguage() { return language; }
    public String getCountry() { return country; }
    public String getVariant() { return variant; }
    public String toLanguageTag() { return language.isEmpty() ? "und" : country.isEmpty() ? language : language + "-" + country; }
    public boolean equals(Object o) { return o instanceof Locale l && language.equals(l.language) && country.equals(l.country) && variant.equals(l.variant); }
    public int hashCode() { return (language.hashCode() * 31 + country.hashCode()) * 31 + variant.hashCode(); }
    public String toString() { String s = country.isEmpty() ? language : language + "_" + country; return variant.isEmpty() ? s : s + "_" + variant; }
}

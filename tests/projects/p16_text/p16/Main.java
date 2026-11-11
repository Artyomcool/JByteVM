package p16;
import java.util.*;
public final class Main {
    public static String run() {
        String line = "  Give Player Diamond_Sword 3  ";
        String[] parts = line.trim().split(" ");
        StringBuilder s = new StringBuilder();
        s.append(parts.length).append(' ').append(parts[2].toLowerCase()).append(' ').append(parts[1].toUpperCase()).append(' ');
        s.append("Hello".equalsIgnoreCase("hELLO")).append(' ').append(String.join("-", parts)).append(' ');
        s.append(String.format("%5d|%-6s|%.3f|%x", 42, "ab", Math.PI, 255)).append(' ');
        s.append("a,b,,c".split(",").length).append(' ').append("x1y22z".replaceAll("[0-9]+", "#")).append(' ');
        s.append("  pad ".strip()).append('|').append(" ".isBlank()).append('|').append("abc".codePointAt(1)).append('|');
        s.append("Mod".indexOf('o')).append("Mod".lastIndexOf("d")).append("Mod".startsWith("M")).append("Mod".endsWith("x"));
        s.append(' ').append(new StringBuilder("hello").reverse().insert(0, '[').append(']').deleteCharAt(1));
        s.append(' ').append(Character.toUpperCase('q')).append(Character.isLetterOrDigit('_')).append(Character.getNumericValue('7'));
        return s.toString();
    }
}

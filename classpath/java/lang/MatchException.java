package java.lang;
/** Thrown by exhaustive pattern switches (no case matched, or a record accessor failed). */
public final class MatchException extends RuntimeException {
    public MatchException(String message,Throwable cause){super(message,cause);}
}

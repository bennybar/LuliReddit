package android.net;

import java.net.URI;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * JVM-test stand-in for android.net.Uri (the framework class is a stub that
 * throws in local unit tests). Test classes precede the mockable android.jar
 * on the test classpath, so model code that parses URLs runs for real here.
 * Covers only what the models use: parse, scheme, host, path, segments, query.
 */
public class Uri {
    private final URI uri;

    private Uri(URI uri) {
        this.uri = uri;
    }

    public static Uri parse(String s) {
        try {
            return new Uri(new URI(s));
        } catch (Exception e) {
            return new Uri(URI.create(""));
        }
    }

    public String getScheme() {
        return uri.getScheme();
    }

    public String getHost() {
        return uri.getHost();
    }

    public String getPath() {
        return uri.getPath();
    }

    public List<String> getPathSegments() {
        String p = uri.getPath();
        if (p == null || p.isEmpty()) return Collections.emptyList();
        List<String> out = new ArrayList<>();
        for (String seg : p.split("/")) if (!seg.isEmpty()) out.add(seg);
        return out;
    }

    public String getQueryParameter(String key) {
        String q = uri.getQuery();
        if (q == null) return null;
        for (String pair : q.split("&")) {
            int i = pair.indexOf('=');
            String k = i < 0 ? pair : pair.substring(0, i);
            if (k.equals(key)) return i < 0 ? "" : pair.substring(i + 1);
        }
        return null;
    }

    @Override
    public String toString() {
        return uri.toString();
    }
}

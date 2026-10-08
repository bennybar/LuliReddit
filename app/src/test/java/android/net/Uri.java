package android.net;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;

/**
 * JVM stand-in for android.net.Uri in unit tests (the android.jar stub
 * throws "not mocked"). Covers only what the code under test calls:
 * parse, scheme, host, path, pathSegments and toString. Test classes come
 * first on the test classpath, so this shadows the stub.
 */
public final class Uri {
    private final String raw;
    private final URI uri;

    private Uri(String raw) {
        this.raw = raw;
        URI u;
        try {
            u = new URI(raw);
        } catch (Exception e) {
            // Reddit URLs can carry characters java.net.URI rejects; parse by hand.
            u = null;
        }
        this.uri = u;
    }

    public static Uri parse(String s) {
        return new Uri(s);
    }

    public String getScheme() {
        if (uri != null) return uri.getScheme();
        int i = raw.indexOf("://");
        return i > 0 ? raw.substring(0, i) : null;
    }

    public String getHost() {
        if (uri != null) return uri.getHost();
        int i = raw.indexOf("://");
        if (i < 0) return null;
        String rest = raw.substring(i + 3);
        int end = rest.length();
        for (char c : new char[] {'/', '?', '#'}) {
            int j = rest.indexOf(c);
            if (j >= 0 && j < end) end = j;
        }
        return rest.substring(0, end);
    }

    public String getPath() {
        if (uri != null) return uri.getPath();
        int i = raw.indexOf("://");
        String rest = i < 0 ? raw : raw.substring(i + 3);
        int slash = rest.indexOf('/');
        if (slash < 0) return "";
        String p = rest.substring(slash);
        int q = p.indexOf('?');
        if (q >= 0) p = p.substring(0, q);
        int h = p.indexOf('#');
        if (h >= 0) p = p.substring(0, h);
        return p;
    }

    public List<String> getPathSegments() {
        List<String> out = new ArrayList<>();
        String p = getPath();
        if (p == null) return out;
        for (String s : p.split("/")) if (!s.isEmpty()) out.add(s);
        return out;
    }

    @Override
    public String toString() {
        return raw;
    }
}

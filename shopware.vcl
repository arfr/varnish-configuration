# Shopware Varnish Configuration
# Copyright © shopware AG

vcl 4.0;

import std;

backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

# ACL for purgers IP.
# Provide here IP addresses that are allowed to send PURGE requests.
# PURGE requests will be sent by the backend.
acl purgers {
    "127.0.0.1";
    "localhost";
    "::1";
}

sub vcl_recv {

    # Normalize query arguments
    set req.url = std.querysort(req.url);

    # Set a header announcing Surrogate Capability to the origin
    set req.http.Surrogate-Capability = "shopware=ESI/1.0";

    # Make sure that the client ip is forward to the client.
    if (req.http.x-forwarded-for) {
        set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    } else {
        set req.http.X-Forwarded-For = client.ip;
    }

    # Handle PURGE
    if (req.method == "PURGE") {
        if (!client.ip ~ purgers) {
            return (synth(405, "Method not allowed"));
        }

        return (purge);
    }

    # Handle BAN
    if (req.method == "BAN") {
        if (!client.ip ~ purgers) {
            return (synth(405, "Method not allowed"));
        }

        if (req.http.X-Shopware-Invalidates) {
            ban("obj.http.X-Shopware-Cache-Id ~ " + ";" + req.http.X-Shopware-Invalidates + ";");
            return (synth(200, "BAN of content connected to the X-Shopware-Cache-Id (" + req.http.X-Shopware-Invalidates + ") done."));
        } else {
            ban("req.url ~ "+req.url);
            return (synth(200, "BAN URLs containing (" + req.url + ") done."));
        }
    }

    # Normalize Accept-Encoding header
    # straight from the manual: https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
            # No point in compressing these
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unkown algorithm
            unset req.http.Accept-Encoding;
        }
    }

    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    # We only deal with GET and HEAD by default
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Don't cache Authenticate & Authorization
    if (req.http.Authenticate || req.http.Authorization) {
        return (pass);
    }

    # Don't cache selfhealing-redirect
    if (req.http.Cookie ~ "ShopwarePluginsCoreSelfHealingRedirect") {
        return (pass);
    }

    # Do not cache these paths.
    if (req.url ~ "^/backend" ||
        req.url ~ "^/backend/.*$") {

        return (pass);
    }

    # Do a standard lookup on assets
    # Note that file extension list below is not extensive, so consider completing it to fit your needs.
    if (req.method == "GET" && req.url ~ "\.(css|js|gif|jpe?g|bmp|png|tiff?|ico|img|tga|wmf|svg|swf|ico|mp3|mp4|m4a|ogg|mov|avi|wmv|zip|gz|pdf|ttf|eot|wof)$") {
        unset req.http.Cookie;
    }

    return (hash);
}

sub vcl_hash {
    ## normalize shop and currency cookie in hash to improve hitrate
    if (req.http.cookie ~ "shop=") {
        hash_data("+shop=" + regsub(req.http.cookie, "^.*?shop=([^;]*);*.*$", "\1"));
    } else {
        hash_data("+shop=1");
    }

    if (req.http.cookie ~ "currency=") {
        hash_data("+currency=" + regsub(req.http.cookie, "^.*?currency=([^;]*);*.*$", "\1"));
    } else {
        hash_data("+currency=1");
    }
    
    if (req.http.cookie ~ "x-cache-context-hash=") {
        hash_data("+context=" + regsub(req.http.cookie, "^.*?x-cache-context-hash=([^;]*);*.*$", "\1"));
    }
}

sub vcl_hit {
    if (obj.http.X-Shopware-Allow-Nocache && req.http.cookie ~ "nocache=") {
        set req.http.X-Cookie-Nocache = regsub(req.http.Cookie, "^.*?nocache=([^;]*);*.*$", "\1");
        if (std.strstr(req.http.X-Cookie-Nocache, obj.http.X-Shopware-Allow-Nocache)) {
            return (pass);
        }
    }
}

sub vcl_backend_response {
    # Enable ESI only if the backend responds with an ESI header
    # Unset the Surrogate Control header and do ESI
    if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
        unset beresp.http.Surrogate-Control;
        set beresp.do_esi = true;
        return (deliver);
    }

    # Respect the Cache-Control=private header from the backend
    if (
        beresp.http.Pragma        ~ "no-cache" ||
        beresp.http.Cache-Control ~ "no-cache" ||
        beresp.http.Cache-Control ~ "private"
    ) {
        set beresp.ttl = 0s;
        set beresp.http.X-Cacheable = "NO:Cache-Control=private";
        # set beresp.ttl = 120s;
        set beresp.uncacheable = true;
        return (deliver);
    }

    # strip the cookie before the image is inserted into cache.
    if (bereq.url ~ "\.(png|gif|jpg|swf|css|js)$") {
        unset beresp.http.set-cookie;
    }

    # Allow items to be stale if needed.
    set beresp.grace = 6h;

    # Save the bereq.url so bans work efficiently
    set beresp.http.x-url = bereq.url;
    set beresp.http.X-Cacheable = "YES";

    return (deliver);
}

sub vcl_deliver {
    ## we don't want the client to cache
    set resp.http.Cache-Control = "max-age=0, private";

    ## unset the headers, thus remove them from the response the client sees
    unset resp.http.X-Shopware-Allow-Nocache;
    unset resp.http.X-Shopware-Cache-Id;

    # Set a cache header to allow us to inspect the response headers during testing
    if (obj.hits > 0) {
        unset resp.http.set-cookie;
        set resp.http.X-Cache = "HIT";
    }  else {
        set resp.http.X-Cache = "MISS";
    }

    set resp.http.X-Cache-Hits = obj.hits;
}

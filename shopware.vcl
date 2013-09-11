# Shopware 4
# Copyright © shopware AG
#
# According to our dual licensing model, this program can be used either
# under the terms of the GNU Affero General Public License, version 3,
# or under a proprietary license.
#
# The texts of the GNU Affero General Public License with an additional
# permission and of our proprietary license can be found at and
# in the LICENSE file you have received along with this program.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# "Shopware" is a registered trademark of shopware AG.
# The licensing of the program under the AGPLv3 does not imply a
# trademark license. Therefore any rights, title and interest in
# our trademarks remain entirely with us.
#

backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

# For syslog
import std;

C{
    #include <syslog.h>
    #include <stdlib.h>
    #include <stdio.h>
    #include <string.h>
}C

# ACL for purgers IP.
# Provide here IP addresses that are allowed to send PURGE requests.
# PURGE requests will be sent by the backend.
acl purgers {
    "127.0.0.1";
    "localhost";
}

# Called at the beginning of a request, after the complete request has been received and parsed.
sub vcl_recv {
    # Set a header announcing Surrogate Capability to the origin
    set req.http.Surrogate-Capability = "shopware=ESI/1.0";

    # Make sure that the client ip is forward to the client.
    if (req.http.x-forwarded-for) {
        set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    } else {
        set req.http.X-Forwarded-For = client.ip;
    }

    # Handle BAN
    if (req.request == "PURGE") {
        if (!client.ip ~ purgers) {
            error 405 "Method not allowed";
        }

        return (lookup);
    }

    # Handle BAN
    if (req.request == "BAN") {
        if (!client.ip ~ purgers) {
            error 405 "Method not allowed";
        }

        if (req.http.X-Shopware-Invalidates) {
            ban("obj.http.X-Shopware-Cache-Id ~ " + ";" + req.http.X-Shopware-Invalidates + ";");
            error 200 "BAN of content connected to the X-Shopware-Cache-Id (" + req.http.X-Shopware-Invalidates + ") done.";
        } else {
            ban("req.url ~ "+req.url);
            error 200 "BAN URLs containing (" + req.url + ") done.";
        }
    }

    # Allow the backend to serve up stale content if it is responding slowly.
    set req.grace = 6h;

    # Normalize Accept-Encoding header
    # straight from the manual: https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unkown algorithm
            remove req.http.Accept-Encoding;
        }
    }

    if (req.request != "GET" &&
        req.request != "HEAD" &&
        req.request != "PUT" &&
        req.request != "POST" &&
        req.request != "TRACE" &&
        req.request != "OPTIONS" &&
        req.request != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    # We only deal with GET and HEAD by default
    if (req.request != "GET" && req.request != "HEAD") {
        return (pass);
    }

    # Don't cache Authenticate & Authorization
    if (req.http.Authenticate || req.http.Authorization) {
        return(pass);
    }

    # Don't cache selfhealing-redirect
    if (req.http.Cookie ~ "ShopwarePluginsCoreSelfHealingRedirect") {
        return(pass);
    }

    # Do not cache these paths.
    if (req.url ~ "^/backend" ||
        req.url ~ "^/backend/.*$") {

        return (pass);
    }

    # Do a standard lookup on assets
    # Note that file extension list below is not extensive, so consider completing it to fit your needs.
    if (req.request == "GET" && req.url ~ "\.(css|js|gif|jpe?g|bmp|png|tiff?|ico|img|tga|wmf|svg|swf|ico|mp3|mp4|m4a|ogg|mov|avi|wmv|zip|gz|pdf|ttf|eot|wof)$") {
        unset req.http.Cookie;
    }

    #unset req.http.Cookie;
    return (lookup);
}

sub vcl_hash {
    hash_data(req.url);

    if (req.http.Host) {
        hash_data(req.http.Host);
    } else {
        hash_data(server.ip);
    }

    set req.http.x-tmp-hash = "";
    ## normalize shop and currency cookie in hash to improve hitrate
    if (req.http.cookie ~ "shop=") {
        set req.http.x-tmp-hash = req.http.x-tmp-hash + "+shop=" + regsub(req.http.Cookie, "^.*?shop=([^;]*);*.*$", "\1");
    } else {
        set req.http.x-tmp-hash = req.http.x-tmp-hash + "+shop=1";
    }

    if (req.http.cookie ~ "currency=") {
        set req.http.x-tmp-hash = req.http.x-tmp-hash + "+currency=" + regsub(req.http.Cookie, "^.*?currency=([^;]*);*.*$", "\1");
    } else {
        set req.http.x-tmp-hash = req.http.x-tmp-hash + "+currency=1";
    }

    hash_data(req.http.x-tmp-hash);
    unset req.http.x-tmp-hash;

    return (hash);
}

sub vcl_hit {
    if (obj.http.X-Shopware-Allow-Nocache && req.http.cookie ~ "nocache=") {
        set req.http.X-Cookie-Nocache = regsub(req.http.Cookie, "^.*?nocache=([^;]*);*.*$", "\1");
        C{
            // 031 oct = 25 dec
            char *nocacheHeader = VRT_GetHdr(sp, HDR_OBJ, "\031X-Shopware-Allow-Nocache:");
            char *nocacheCookie = VRT_GetHdr(sp, HDR_REQ, "\021X-Cookie-Nocache:");
            char *match         = strstr(nocacheCookie, nocacheHeader);

            if (match) {
               VRT_SetHdr(sp, HDR_REQ, "\015X-Pass-Cache:", "true", vrt_magic_string_end);
            } else {
               VRT_SetHdr(sp, HDR_REQ, "\015X-Pass-Cache:", "false", vrt_magic_string_end);
            }
        }C

        if (req.http.X-Pass-Cache == "true") {
            return(pass);
        }
    }

    if (req.request == "PURGE") {
        purge;
        error 200 "Purged";
    }
}

sub vcl_miss {
    if (req.request == "PURGE") {
        purge;
        error 404 "Not in cache";
    }
}

sub vcl_pass {
    if (req.request == "PURGE") {
        error 502 "PURGE on a passed object";
    }

    return (pass);
}

# vcl_fetch is called after a document has been successfully retrieved from the backend.
# There is also a backend response, beresp. beresp will contain the HTTP headers from the backend.
sub vcl_fetch {
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
        return (hit_for_pass);
    }

    # strip the cookie before the image is inserted into cache.
    if (req.url ~ "\.(png|gif|jpg|swf|css|js)$") {
        unset beresp.http.set-cookie;
    }

    # Allow items to be stale if needed.
    set beresp.grace = 6h;

    # Save the req.url so bans work efficiently
    set beresp.http.x-url = req.url;
    set beresp.http.X-Cacheable = "YES";

    return(deliver);
}

# Called when the requested object has been retrieved from the backend
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

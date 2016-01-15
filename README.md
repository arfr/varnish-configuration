Shopware Varnish Configuration
================================

## Support
Please note that shopware AG exclusively supports Varnish cache configuration for customers with Shopware Enterprise licenses.


## Requirements
This configuration requires at least version 4.0 of Varnish and at least version 4.3.3 of shopware.

## Shopware configuration

### Disable the inbuilt reverse proxy
The PHP-based reverse proxy has to be disabled. To disable add the following section to your `config.php`:

```
'httpCache' => array(
    'enabled' => false,
),
```

### Configure Trusted Proxies
If you have a reverse proxy in front of your shopware installation you have to set the IP of the proxy in the `trustedProxies` section in your `config.php`:

```
'trustedProxies' => array(
    '127.0.0.1'
)
```


### TLS Termination

Varnish does not support SSL/TLS ([Why no SSL?](https://www.varnish-cache.org/docs/trunk/phk/ssl.html#phk-ssl)).
To support TLS requests a [TLS termination proxy](https://en.wikipedia.org/wiki/TLS_termination_proxy) like nginx or HAProxy has to n to handle incoming TLS connections and forward them to Varnish.

You can put Varnish on port 80 and handle unencrypted requests directly.


```
# /etc/default/varnish
DAEMON_OPTS="-a :80 \
             -T localhost:6082 \
             -f /etc/varnish/default.vcl \
             -S /etc/varnish/secret \
             -s malloc,256m"
```

**Traffic flow:**

```
Internet ▶ 0.0.0.0:443 (nginx/TLS Termination) ▶ 0.0.0.0:80 (Varnish Cache) ▶ 127.0.0.1:8080 (Apache/Shopware)
Internet ▶ 0.0.0.0:80 (Varnish/Caching) ▶ 127.0.0.1:8080 (Apache/Shopware)
```

Or you can forward unencrypted traffic to the secure port via HTTP 301. In this case all incoming traffic is handled by the reverse proxy upfront and Varnish can run on Port 6081 on localhost.


```
# /etc/default/varnish
DAEMON_OPTS="-a :6081 \
             -T localhost:6082 \
             -f /etc/varnish/default.vcl \
             -S /etc/varnish/secret \
             -s malloc,256m"
```

**Traffic flow:**

```
Internet ▶ 0.0.0.0:80 (nginx/forward to TLS) ▶ 0.0.0.0:443 via HTTP 301 (TLS Only)
Internet ▶ 0.0.0.0:443 (nginx/TLS Termination) ▶ 127.0.0.1:6081 (Varnish Cache) ▶ 127.0.0.1:8080 (Apache/Shopware)
```

#### Forward HTTP Headers
The reverse proxy has to forward headers to to Varnish:

```nginx
server {
   listen         80;
   server_name    example.com www.example.com;
   return         301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name example.com;

    # Server certificate and key.
    ssl_certificate /etc/nginx/ssl/example.com.crt;
    ssl_certificate_key /etc/nginx/ssl/example.com.crt;

    location / {
        # Forward request to Varnish.
        proxy_pass  http://127.0.0.1:6081; // change to port 80 if varnish is running upfront
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_redirect off;
    }
}
```

For a secure TLS(SSL) you can use the [Mozilla SSL Configuration Generator](https://mozilla.github.io/server-side-tls/ssl-config-generator/).


### Enable cache plugin
The Shopware HTTP-Cache-Plugin has to be activated, to activate follow the these steps in your Shopware Backend:

`Einstellungen -> Caches / Performance -> Einstellungen -> HttpCache atkivieren`

## Varnish configuration
A Varnish VCL for shopware is available here: [shopware.vcl](shopware.vcl).

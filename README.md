Shopware Varnish Configuration
================================

## Attention
Please note that Varnish configuration is supported and enabled exclusively by shopware AG’s Enterprise platforms.

Operating Varnish with other Shopware editions is neither possible nor guaranteed.

## Requirements
This configuration requires at least version 4.0 of Varnish and at least version 4.3.3 of shopware.

## Shopware configuration

### Disable reverse proxy
The PHP-based reverse proxy has to be disabled. To disable add the following section to your `config.php`:

```
'httpCache' => array(
    'enabled' => false,
),
```

### Configure trusted proxies
If you have a reverse proxy in front of your shopware installation you have to set the IP of the proxy in the `trustedProxies` section in your `config.php`:

```
'trustedProxies' => array(
    '127.0.0.1'
)
```

### Enable cache plugin
The Shopware HTTP-Cache-Plugin has to be activated, to activate follow the these steps in your Shopware Backend:

`Einstellungen -> Caches / Performance -> Einstellungen -> HttpCache atkivieren`

## Varnish configuration
A Varnish VCL for shopware is available here: [shopware.vcl](shopware.vcl).

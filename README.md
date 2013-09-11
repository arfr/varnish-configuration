Shopware 4 Varnish Configuration
================================

## Achtung
Please note that Varnish configuration is supported and enabled exclusively by shopware AG’s Enterprise platforms.

Operating Varnish with other Shopware editions is neither possible nor guaranteed.

## Requirements
This configuration requires at least version 3.0 of Varnish and at lease version 4.1 of shopware.

## Shopware configuration

### Disable reverse proxy
The PHP-based reverse proxy has to be disabled. To disable add the following section to your `config.php`:

```
'httpCache' => array(
    'enabled' => false,
),
```

### Enable cache plugin
The Shopware HTTP-Cache-Plugin has to be activated, to activate follow the these steps in your Shopware Backend:

`Einstellungen -> Caches / Performance -> Einstellungen -> HttpCache atkivieren`

## Varnish configuration
A Varnish VCL for shopware is available here: [shopware.vcl](shopware.vcl).

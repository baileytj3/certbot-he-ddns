# Certbot DNS-01 Validation Hook for Hurricane Electric Dynamic TXT

This script is to be used as a validation hook for Certbot. It will update the
appropriate TXT records by using Hurricane Electric's Dynamic TXT update
feature. See the script for a more detailed description and usage examples.

## Example usage

```bash
HE_DDNS_PASSWORD="<password>" certbot certonly
    --agree-tos \
    --email=example@example.com \
    --preferred-challenges dns-01 \
    --manual \
    --manual-auth-hook /path/to/certbot-he-ddns.sh \
    --manual-cleanup-hook /path/to/certbot-he-ddns.sh \
    -d example.com
```

#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

if [[ -z ${CERTBOT_DOMAIN:-} ]] || [[ -z ${CERTBOT_VALIDATION:-} ]]; then
    cat <<USAGE
This script is used to validate domains hosted by Hurricane Electric via Certbot.


= Description =

The Dynamic TXT record feature provided by Hurricane Electric is utilized by
this script to update the TXT record for domains that are being validated by
Certbot. The password generated on Hurricane Electric's website only gives
update permissions to a single record instead of requiring the admin username
and password for the account.

When passed to Certbot via the --manual-auth-hook option, this script will
update the TXT record for the domain that is being validated by Certbot to the
value provided by Certbot. The script will then wait for a period of time
while checking for the TXT record to return the proper value.

When passed to Certbot via the --manual-cleanup-hook option, this script will 
reset the TXT record value to a default value. The default value can be
specified via environment variable or config file.


= Limitations =

Due to the way the Dynamic TXT Record feature is implemented by Hurricane
Electric, the TXT record for the domains being validated must exist prior to
the script being ran.

Again because of the implementation of the Dynamic TXT Record feature, only a
single TXT record per domain can be updated. This means that this script is
unable to validate a wildcard domain and the base domain at the same time; eg.
*.example.com, example.com.

There may be some instances where the user attempts to validate a domain
multiple times. While this script will attempt to verify that the TXT record is
updated and not stale in DNS cache, there is no guaruntee that the record won't
be cached elsewhere.


= Usage Examples =

Single Domain w/o Config File:
    HE_DDNS_PASSWORD="ddns password" certbot certonly \\
        --agree-tos \\
        --email=example@example.com \\
        --preferred-challenges dns-01 \\
        --manual \\
        --manual-auth-hook /path/to/certbot-he-ddns.sh \\
        --manual-cleanup-hook /path/to/certbot-he-ddns.sh \\
        -d example.com

Single Domain w/ custom Config File location:
    HE_DDNS_CONF="<path to config file>" certbot certonly \\
        --agree-tos \\
        --email=example@example.com \\
        --preferred-challenges dns-01 \\
        --manual \\
        --manual-auth-hook /path/to/certbot-he-ddns.sh \\
        --manual-cleanup-hook /path/to/certbot-he-ddns.sh \\
        -d example.com

Multiple Domain w/ default config file location:
    Note: Multiple domains require the use of the HE_DDNS_AUTH variable! See
    the 'Example Config File - Multiple Domains' section.

    certbot certonly \\
        --agree-tos \\
        --email=example@example.com \\
        --preferred-challenges dns-01 \\
        --manual \\
        --manual-auth-hook /path/to/certbot-he-ddns.sh \\
        --manual-cleanup-hook /path/to/certbot-he-ddns.sh \\
        -d example.com \\
        -d test.example.com


= Script Options =

    HE_DDNS_DEFAULT
        The default value to set for the TXT record during cleanup. The default
        value is 'Acme challenge key'.

    HE_DDNS_PASSWORD
        The ddns password to use when updating the TXT record for the domain.
        Only use when authenticating a single domain.

    HE_DDNS_AUTH
        An associative array mapping TXT records to ddns passwords. Since the
        ddns password provided by Hurricane Electric is per record, when
        performing validation for multiple domains each record must have a
        password. This can be used with single domain validation as well as
        multi-domain validation.

    HE_DDNS_RETRY_INTERVAL
        An integer that controls how often to check for the updated record
        after updating it. The script will attempt a 'dig' against the domain
        every HE_DDNS_RETRY_INTERVAL seconds until HE_DDNS_RETYR_TIMEOUT is
        reached. Once the value returned for the TXT record matches the
        CERTBOT_VALIDATION value or the HE_DDNS_RETRY_TIMEOUT is reached the
        script will continue. The default value is 5.

    HE_DDNS_RETRY_TIMEOUT
        The number of seconds, as an integer, that controls how long the script
        will wait for the TXT record to become active. If the TXT record is
        cached in DNS the validation might fail. This timeout will attempt to
        wait out the TTL of the record until the old value times out of cache.
        To disable this feature set HE_DDNS_RETRY_TIMEOUT to 0. The default
        value is 300.


= Config File =

All of the script options can be passed to the script as an environment
variable, but for ease of use they can be specified in a config file as well.
The config file location can be passed to the script via the environment
variable HE_DDNS_CONFIG.  The default location for the config file is
"\${HOME}/.certbot-he-ddns.conf".

Config File Example - Single Domain:
HE_DDNS_DEFAULT="Custom default"
HE_DDNS_PASSWORD="ddns password"
HE_DDNS_RETRY_INTERVAL=10
HE_DDNS_RETRY_TIMEOUT=400

Config File Example - Multiple Domains:
HE_DDNS_DEFAULT="Custom default"
HE_DDNS_AUTH["example.com"]="unique password 1"
HE_DDNS_AUTH["test.example.com"]="unique password 2"
HE_DDNS_RETRY_INTERVAL=10
HE_DDNS_RETRY_TIMEOUT=400

USAGE
 exit 1
fi

declare -A HE_DDNS_AUTH

conf_file=${HE_DDNS_CONF:-"${HOME}/.certbot-he-ddns.conf"}
conf_file_abs=$(realpath "${conf_file}")

if [[ -f "${conf_file_abs}" ]]; then
    source "${conf_file_abs}"
fi

acme_subdomain="_acme-challenge"
ddns_default=${HE_DDNS_DEFAULT:-"Acme challenge key"}
ddns_domain="${acme_subdomain}.${CERTBOT_DOMAIN}"
ddns_password=${HE_DDNS_AUTH[${CERTBOT_DOMAIN}]:-${HE_DDNS_PASSWORD:-}}
ddns_url="https://dyn.dns.he.net/nic/update"
re_good="^good|^nochg"
retry_interval=${HE_DDNS_RETRY_INTERVAL:-5}
retry_timeout=${HE_DDNS_RETRY_TIMEOUT:-300}

# Should indicate auth_hook
if [[ -z ${CERTBOT_AUTH_OUTPUT:-} ]]; then

    echo "Performing auth for ${CERTBOT_DOMAIN}"
    result=$( \
        curl "${ddns_url}" \
            --silent \
            --data "hostname=${ddns_domain}" \
            --data "password=${ddns_password}" \
            --data "txt=${CERTBOT_VALIDATION}" \
        )

    if [[ "${result}" =~ ${re_good} ]]; then

        echo "Waiting up to ${retry_timeout} seconds for dns update"
        end_seconds=$((SECONDS + retry_timeout))

        while [[ ${SECONDS} -lt ${end_seconds} ]]; do

            # Sleep first to give update time to propogate
            sleep $retry_interval

            record_result=$(dig ${ddns_domain} TXT +short)
            if [[ ${record_result} =~ ${CERTBOT_VALIDATION} ]]; then
                break
            fi
        done
    fi
# cleanup_hook
else
    echo "Performing cleanup for ${CERTBOT_DOMAIN}"
    result=$( \
        curl "${ddns_url}" \
            --silent \
            --data "hostname=${ddns_domain}" \
            --data "password=${ddns_password}" \
            --data "txt=${ddns_default}" \
        )
fi

if [[ ! "${result}" =~ ${re_good} ]]; then
    echo "Update for ${ddns_domain} failed with: ${result}"
fi

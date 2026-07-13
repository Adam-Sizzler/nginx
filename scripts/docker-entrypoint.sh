#!/usr/bin/env bash
set -euo pipefail

/usr/local/bin/update_geolite.sh

test -s /etc/nginx/geolite2/GeoLite2-Country.mmdb
test -s /etc/nginx/geolite2/GeoLite2-City.mmdb
test -s /etc/nginx/geolite2/GeoLite2-ASN.mmdb

exec supervisord -c /etc/supervisor/supervisord.conf -n

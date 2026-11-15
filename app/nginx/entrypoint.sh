#!/bin/sh
set -eu
# Expand only the two upstream settings, leaving NGINX variables intact.
# shellcheck disable=SC2016
envsubst '${PHP_FPM_UPSTREAM} ${FPM_STATUS_UPSTREAM}' \
  < /etc/nginx/default.conf.template > /tmp/default.conf
exec nginx -g 'daemon off;'

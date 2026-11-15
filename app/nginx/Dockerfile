ARG BASE_REGISTRY=docker.arvancloud.ir
FROM ${BASE_REGISTRY}/library/nginx:1.30.6-alpine@sha256:583b7f2fce1cdb8da5ad5c39ebd3c33b98b87d493190e548bdee1fa8c619c311
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf.template /etc/nginx/default.conf.template
COPY trusted-proxies.conf /etc/nginx/trusted-proxies.conf
COPY --chmod=0755 entrypoint.sh /usr/local/bin/lab-entrypoint
ENV PHP_FPM_UPSTREAM=php-fpm:9000 FPM_STATUS_UPSTREAM=php-fpm:9001
USER 101:101
EXPOSE 8080 8081
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]

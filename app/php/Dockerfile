ARG BASE_REGISTRY=docker.arvancloud.ir
FROM ${BASE_REGISTRY}/library/php:8.4.27-fpm-alpine3.23@sha256:2ad688857a54c3ce8cae9c1bdc439f674ff5ede01102b9610d0e2b0c6927c36c
RUN rm /usr/local/etc/php-fpm.d/*.conf
COPY php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY php.ini /usr/local/etc/php/conf.d/lab.ini
COPY index.php /var/www/html/index.php
USER 82:82
EXPOSE 9000 9001
CMD ["php-fpm", "-F"]

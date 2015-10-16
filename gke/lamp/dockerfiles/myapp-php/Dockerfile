FROM bitnami/php-fpm:5.5.30-0
ENV MYAPP_DIR=/app

COPY rootfs/ /
COPY code/ ${MYAPP_DIR}/

WORKDIR $MYAPP_DIR

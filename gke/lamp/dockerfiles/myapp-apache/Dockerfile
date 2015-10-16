FROM bitnami/apache:2.4.17-0
ENV MYAPP_DIR=/app

COPY rootfs/ /
COPY code/ ${MYAPP_DIR}/

WORKDIR $MYAPP_DIR

FROM bitnami/apache:2.4.12-4-r01
ENV WORDPRESS_VERSION=4.3.1 \
    WORDPRESS_INSTALL_DIR=/app

RUN curl -L https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz -o /tmp/wordpress-${WORDPRESS_VERSION}.tar.gz \
 && mkdir -p $WORDPRESS_INSTALL_DIR \
 && tar -xf /tmp/wordpress-${WORDPRESS_VERSION}.tar.gz --strip=1 -C $WORDPRESS_INSTALL_DIR \
 && chown -R $BITNAMI_APP_USER:$BITNAMI_APP_USER $WORDPRESS_INSTALL_DIR \
 && rm -rf /tmp/*

COPY rootfs/ /

WORKDIR $WORDPRESS_INSTALL_DIR

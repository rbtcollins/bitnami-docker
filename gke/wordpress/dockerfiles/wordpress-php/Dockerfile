FROM bitnami/php-fpm:5.5.30-0
ENV WORDPRESS_VERSION=4.3.1 \
    WORDPRESS_INSTALL_DIR=/app \
    S3_OFFLOAD_PLUGIN_VERSION=0.9.6

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y unzip \
 && curl -L https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz -o /tmp/wordpress-${WORDPRESS_VERSION}.tar.gz \
 && mkdir -p $WORDPRESS_INSTALL_DIR \
 && tar -xf /tmp/wordpress-${WORDPRESS_VERSION}.tar.gz --strip=1 -C $WORDPRESS_INSTALL_DIR \
 && cp $WORDPRESS_INSTALL_DIR/wp-config-sample.php $WORDPRESS_INSTALL_DIR/wp-config.php \
 && curl -L https://downloads.wordpress.org/plugin/amazon-web-services.zip -o /tmp/wp2cloud-amazon-web-services.zip \
 && curl -L https://downloads.wordpress.org/plugin/amazon-s3-and-cloudfront.${S3_OFFLOAD_PLUGIN_VERSION}.zip -o /tmp/amazon-s3-and-cloudfront.${S3_OFFLOAD_PLUGIN_VERSION}.zip \
 && unzip /tmp/wp2cloud-amazon-web-services.zip -d $WORDPRESS_INSTALL_DIR/wp-content/plugins/ \
 && unzip /tmp/amazon-s3-and-cloudfront.${S3_OFFLOAD_PLUGIN_VERSION}.zip -d $WORDPRESS_INSTALL_DIR/wp-content/plugins/ \
 && chown -R $BITNAMI_APP_USER:$BITNAMI_APP_USER $WORDPRESS_INSTALL_DIR \
 && rm -rf /var/lib/apt /var/cache/apt/archives/* /tmp/*

COPY rootfs/ /

WORKDIR $WORDPRESS_INSTALL_DIR

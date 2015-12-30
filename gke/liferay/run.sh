#!/bin/bash
set -e

# automatically fetch database parameters from bitnami/mariadb
DATABASE_HOST=${DATABASE_HOST:-${MARIADB_PORT_3306_TCP_ADDR}}
DATABASE_PORT=${DATABASE_PORT:-${MARIADB_PORT_3306_TCP_PORT}}
DATABASE_NAME=${DATABASE_NAME:-${MARIADB_ENV_MARIADB_DATABASE}}
DATABASE_USER=${DATABASE_USER:-${MARIADB_ENV_MARIADB_USER}}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-${MARIADB_ENV_MARIADB_PASSWORD}}

# lookup LIFERAY_PASSWORD configuration in secrets volume
if [[ -z ${LIFERAY_PASSWORD} && -f /etc/liferay-secrets/liferay-password ]]; then
  LIFERAY_PASSWORD=$(cat /etc/liferay-secrets/liferay-password)
fi

# lookup DATABASE_PASSWORD configuration in secrets volume
if [[ -z ${DATABASE_PASSWORD} && -f /etc/liferay-secrets/database-password ]]; then
  DATABASE_PASSWORD=$(cat /etc/liferay-secrets/database-password)
fi

echo ${DATABASE_HOST}
echo ${DATABASE_PORT}
echo ${DATABASE_NAME}
echo ${DATABASE_USER}
echo ${DATABASE_PASSWORD}

if [[ -z ${DATABASE_HOST} || -z ${DATABASE_PORT} || -z ${DATABASE_NAME} || \
      -z ${DATABASE_USER} || -z ${DATABASE_PASSWORD} ]]; then
  echo "ERROR: "
  echo "  Please configure the database connection."
  echo "  Cannot continue without a database. Aborting..."
  exit 1
fi

# s3 / google cloud storage configuration (uploads)
S3_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID:-}
S3_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY:-}
S3_BUCKET=${S3_BUCKET:-}
S3_ENDPOINT=${S3_ENDPOINT:-storage.googleapis.com}

# lookup S3_ACCESS_KEY_ID configuration in secrets volume
if [[ -z ${S3_ACCESS_KEY_ID} && -f /etc/liferay-secrets/s3-access-key-id ]]; then
  S3_ACCESS_KEY_ID=$(cat /etc/liferay-secrets/s3-access-key-id)
fi

# lookup S3_SECRET_ACCESS_KEY configuration in secrets volume
if [[ -z ${S3_SECRET_ACCESS_KEY} && -f /etc/liferay-secrets/s3-secret-access-key ]]; then
  S3_SECRET_ACCESS_KEY=$(cat /etc/liferay-secrets/s3-secret-access-key)
fi

#if [[ -z ${S3_ACCESS_KEY_ID} || -z ${S3_SECRET_ACCESS_KEY} ||
#      -z ${S3_BUCKET} || -z ${S3_ENDPOINT} ]]; then
#  echo "ERROR: "
#  echo "  Please configure a s3 / google cloud storage bucket."
#  echo "  Cannot continue. Aborting..."
#  exit 1
#fi

# configure liferay settings
cat > $BITNAMI_APP_DIR/webapps/liferay/WEB-INF/classes/portal-ext.properties <<EOF
portal.ctx=/liferay
auto.deploy.dest.dir=$BITNAMI_APP_DIR/webapps
auto.deploy.deploy.dir=$BITNAMI_PREFIX/apps/liferay/data/deploy
lucene.dir=$BITNAMI_PREFIX/apps/liferay/data/lucene
jcr.jackrabbit.repository.root=$BITNAMI_PREFIX/apps/liferay/data/jackrabbit
resource.repositories.root=$BITNAMI_PREFIX/apps/liferay/data
jdbc.default.driverClassName=com.mysql.jdbc.Driver
jdbc.default.url=jdbc:mysql://$DATABASE_HOST:$DATABASE_PORT/$DATABASE_NAME?useUnicode=true&characterEncoding=UTF-8&useFastDateParsing=false
jdbc.default.username=$DATABASE_USER
jdbc.default.password=$DATABASE_PASSWORD
include-and-override=$BITNAMI_PREFIX/apps/liferay/data/portal-setup-wizard.properties
browser.launcher.url=
redirect.url.security.mode=ip
redirect.url.domains.allowed=
redirect.url.ips.allowed=127.0.0.1,SERVER_IP
EOF
chown tomcat:tomcat $BITNAMI_APP_DIR/webapps/liferay/WEB-INF/classes/portal-ext.properties

# configure wizard settings
cat > $BITNAMI_PREFIX/apps/liferay/data/portal-setup-wizard.properties <<EOF
dmin.email.from.name=$LIFERAY_USERNAME
default.admin.first.name=$LIFERAY_USERNAME
default.admin.last.name=
company.default.name=Liferay
default.admin.email.address.prefix=$LIFERAY_USER
company.default.locale=en_US
admin.email.from.address=$LIFERAY_USER@liferay.com
setup.wizard.enabled=false
default.admin.screen.name=$LIFERAY_USER
default.admin.password=$LIFERAY_PASSWORD
EOF
chmod 700 $BITNAMI_PREFIX/apps/liferay/data/portal-setup-wizard.properties
chown tomcat:tomcat $BITNAMI_PREFIX/apps/liferay/data/portal-setup-wizard.properties

harpoon start tomcat --foreground

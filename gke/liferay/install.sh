#!/bin/bash

LIFERAY_TMP_DIR=/tmp/liferay-sources
LIFERAY_ZIP_NAME=liferay-portal-tomcat.zip

mkdir $LIFERAY_TMP_DIR

unzip -q /tmp/$LIFERAY_ZIP_NAME -d $LIFERAY_TMP_DIR
mkdir -p $LIFERAY_TMP_DIR/webapps
mkdir -p $LIFERAY_TMP_DIR/lib/ext
mkdir -p $LIFERAY_TMP_DIR/temp
cp -R $LIFERAY_TMP_DIR/liferay-portal-*/tomcat-*/webapps/* $LIFERAY_TMP_DIR/webapps
cp -R $LIFERAY_TMP_DIR/liferay-portal-*/tomcat-*/lib/ext/* $LIFERAY_TMP_DIR/lib/ext
cp -R $LIFERAY_TMP_DIR/liferay-portal-*/tomcat-*/temp/liferay $LIFERAY_TMP_DIR/temp
sudo rm -R $LIFERAY_TMP_DIR/liferay*
sudo mv $LIFERAY_TMP_DIR/webapps/ROOT $LIFERAY_TMP_DIR/webapps/liferay
cp -rf $LIFERAY_TMP_DIR/webapps/* $BITNAMI_APP_DIR/webapps.defaults
cp -rf $LIFERAY_TMP_DIR/lib/ext $BITNAMI_APP_DIR/lib
rm $BITNAMI_APP_DIR/lib/ext/ccpp.jar
cp -rf $LIFERAY_TMP_DIR/temp/liferay $BITNAMI_APP_DIR/temp
sed -i s/common.loader=/'common.loader=\$\{catalina.home\}\/lib\/ext,\$\{catalina.home\}\/lib\/ext\/*.jar,'/g $BITNAMI_APP_DIR/conf.defaults/catalina.properties \

mkdir -p $BITNAMI_PREFIX/apps/liferay/data
mkdir $BITNAMI_PREFIX/apps/liferay/logs
chown -R tomcat:tomcat $BITNAMI_APP_DIR/webapps.defaults/* $BITNAMI_APP_DIR/temp $BITNAMI_PREFIX/apps/liferay
rm -rf /tmp/liferay*



FROM gcr.io/bitnami-k8s/bitnami-tomcat

#######################################
# TEMP
ENV TERM=screen-256color
#######################################

RUN apt-get update \
    && apt-get install -y unzip \
    && apt-get install -y vim \
    && export TERM=screen-256color

ENV LIFERAY_VERSION=6.2 \
    LIFERAY_SUBVERSION=3 \
    LIFERAY_URL_FOLDER=GA4 \
    LIFERAY_URL_FOLDER_DC=ga4 \
    LIFERAY_TIMESTAMP=20150416163831865 \
    LIFERAY_ZIP_NAME=liferay-portal-tomcat.zip

RUN curl -L http://downloads.sourceforge.net/project/lportal/Liferay%20Portal/$LIFERAY_VERSION.$LIFERAY_SUBVERSION%20$LIFERAY_URL_FOLDER/liferay-portal-tomcat-$LIFERAY_VERSION-ce-$LIFERAY_URL_FOLDER_DC-$LIFERAY_TIMESTAMP.zip -o /tmp/$LIFERAY_ZIP_NAME
    
COPY install.sh /opt/bitnami/apps/liferay/
RUN /opt/bitnami/apps/liferay/install.sh

COPY run.sh /opt/bitnami/apps/liferay/
CMD /opt/bitnami/apps/liferay/run.sh

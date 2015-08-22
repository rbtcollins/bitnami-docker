FROM bitnami/ruby:2.2.3-0
ENV REDMINE_VERSION=3.0.4

RUN curl -L http://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz \
      -o /tmp/redmine-${REDMINE_VERSION}.tar.gz \
 && mkdir -p /home/$BITNAMI_APP_USER/redmine/ \
 && tar -xf /tmp/redmine-${REDMINE_VERSION}.tar.gz --strip=1 -C /home/$BITNAMI_APP_USER/redmine/ \
 && cd /home/$BITNAMI_APP_USER/redmine \
 && cp -a config/database.yml.example config/database.yml \
 && bundle install --without development test \
 && chown -R $BITNAMI_APP_USER:$BITNAMI_APP_USER /home/$BITNAMI_APP_USER/redmine/ \
 && rm -rf /tmp/redmine-${REDMINE_VERSION}.tar.gz

COPY run.sh /home/$BITNAMI_APP_USER/redmine/run.sh
RUN sudo chmod 755 /home/$BITNAMI_APP_USER/redmine/run.sh

WORKDIR /home/$BITNAMI_APP_USER/redmine/
CMD ["/home/bitnami/redmine/run.sh"]

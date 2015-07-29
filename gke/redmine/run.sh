#!/bin/bash
set -e

REDMINE_SESSION_TOKEN=${REDMINE_SESSION_TOKEN:-}

# lookup REDMINE_SESSION_TOKEN configuration in secrets volume
if [[ -z ${REDMINE_SESSION_TOKEN} && -f /etc/redmine-secrets/redmine-session-token ]]; then
  REDMINE_SESSION_TOKEN=$(cat /etc/redmine-secrets/redmine-session-token)
fi

if [[ -z ${REDMINE_SESSION_TOKEN} ]]; then
  echo "ERROR: "
  echo "  Please configure a secret session token."
  echo "  Cannot continue. Aborting..."
  exit 1
fi

# automatically fetch database parameters from bitnami/mariadb
DATABASE_MASTER_HOST=${DATABASE_MASTER_HOST:-${MARIADB_MASTER_PORT_3306_TCP_ADDR}}
DATABASE_SLAVE_HOST=${DATABASE_SLAVE_HOST:-${MARIADB_SLAVE_PORT_3306_TCP_ADDR}}
DATABASE_NAME=${DATABASE_NAME:-${MARIADB_MASTER_ENV_MARIADB_DATABASE}}
DATABASE_USER=${DATABASE_USER:-${MARIADB_MASTER_ENV_MARIADB_USER}}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-${MARIADB_MASTER_ENV_MARIADB_PASSWORD}}

# lookup DATABASE_PASSWORD configuration in secrets volume
if [[ -z ${DATABASE_PASSWORD} && -f /etc/redmine-secrets/database-password ]]; then
  DATABASE_PASSWORD=$(cat /etc/redmine-secrets/database-password)
fi

if [[ -z ${DATABASE_MASTER_HOST} || -z ${DATABASE_SLAVE_HOST} || \
      -z ${DATABASE_NAME} || -z ${DATABASE_USER} || -z ${DATABASE_PASSWORD} ]]; then
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
if [[ -z ${S3_ACCESS_KEY_ID} && -f /etc/redmine-secrets/s3-access-key-id ]]; then
  S3_ACCESS_KEY_ID=$(cat /etc/redmine-secrets/s3-access-key-id)
fi

# lookup S3_SECRET_ACCESS_KEY configuration in secrets volume
if [[ -z ${S3_SECRET_ACCESS_KEY} && -f /etc/redmine-secrets/s3-secret-access-key ]]; then
  S3_SECRET_ACCESS_KEY=$(cat /etc/redmine-secrets/s3-secret-access-key)
fi

if [[ -z ${S3_ACCESS_KEY_ID} || -z ${S3_SECRET_ACCESS_KEY} ||
      -z ${S3_BUCKET} || -z ${S3_ENDPOINT} ]]; then
  echo "ERROR: "
  echo "  Please configure a s3 / google cloud storage bucket."
  echo "  Cannot continue. Aborting..."
  exit 1
fi

# configure redmine database connection settings
cat > config/database.yml <<EOF
production:
  adapter: 'mysql2_makara'
  database: ${DATABASE_NAME}
  username: ${DATABASE_USER}
  password: "${DATABASE_PASSWORD}"
  encoding: utf8

  blacklist_duration: 5
  master_ttl: 5
  sticky: true
  makara:
    connections:
      - role: master
        host: ${DATABASE_MASTER_HOST}
      - role: slave
        host: ${DATABASE_SLAVE_HOST}
EOF

# configure cloud storage settings
cat > config/s3.yml <<EOF
production:
  access_key_id: ${S3_ACCESS_KEY_ID}
  secret_access_key: ${S3_SECRET_ACCESS_KEY}
  bucket: ${S3_BUCKET}
  endpoint: ${S3_ENDPOINT}
EOF

# create the secret session token file
cat > config/initializers/secret_token.rb <<EOF
RedmineApp::Application.config.secret_key_base = '${REDMINE_SESSION_TOKEN}'
EOF

echo "Running database migrations..."
bundle exec rake db:migrate RAILS_ENV=production

echo "Starting redmine server..."
exec bundle exec rails server -b 0.0.0.0 -p 3000 -e production

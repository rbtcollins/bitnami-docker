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
DATABASE_HOST=${DATABASE_HOST:-${MARIADB_PORT_3306_TCP_ADDR}}
DATABASE_NAME=${DATABASE_NAME:-${MARIADB_ENV_MARIADB_DATABASE}}
DATABASE_USER=${DATABASE_USER:-${MARIADB_ENV_MARIADB_USER}}
DATABASE_PASSWORD=${DATABASE_PASSWORD:-${MARIADB_ENV_MARIADB_PASSWORD}}

# lookup DATABASE_PASSWORD configuration in secrets volume
if [[ -z ${DATABASE_PASSWORD} && -f /etc/redmine-secrets/database-password ]]; then
  DATABASE_PASSWORD=$(cat /etc/redmine-secrets/database-password)
fi

if [[ -z ${DATABASE_HOST} || -z ${DATABASE_NAME} || \
      -z ${DATABASE_USER} || -z ${DATABASE_PASSWORD} ]]; then
  echo "ERROR: "
  echo "  Please configure the database connection."
  echo "  Cannot continue without a database. Aborting..."
  exit 1
fi

# configure redmine database connection settings
cat > config/database.yml <<EOF
production:
  adapter: mysql2
  database: ${DATABASE_NAME}
  host: ${DATABASE_HOST}
  username: ${DATABASE_USER}
  password: "${DATABASE_PASSWORD}"
  encoding: utf8
EOF

# create the secret session token file
cat > config/initializers/secret_token.rb <<EOF
RedmineApp::Application.config.secret_key_base = '${REDMINE_SESSION_TOKEN}'
EOF

echo "Running database migrations..."
bundle exec rake db:migrate RAILS_ENV=production

echo "Starting redmine server..."
exec bundle exec rails server -b 0.0.0.0 -p 3000 -e production

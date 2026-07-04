#!/usr/bin/env bash
set -e

cd /var/www/discourse

echo "Generating config/discourse.conf..."

cat > config/discourse.conf <<EOF
hostname = ${DISCOURSE_HOSTNAME:-discourse.rs.com}
developer_emails = ${DISCOURSE_DEVELOPER_EMAILS:-admin@example.com}

db_host = postgres
db_port = 5432
db_name = discourse
db_username = discourse
db_password = discourse

redis_host = redis
redis_port = 6379
redis_db = 0

message_bus_redis_host = redis
message_bus_redis_port = 6379
message_bus_redis_db = 0

smtp_address =
smtp_port = 587
smtp_user_name =
smtp_password =

# 测试/内网环境关闭邮件发送
disable_emails = yes
EOF

echo "Generating config/database.yml..."

cat > config/database.yml <<EOF
production:
  prepared_statements: false
  adapter: postgresql
  database: discourse
  username: discourse
  password: discourse
  host: postgres
  port: 5432
  min_messages: warning
  pool: 8
  checkout_timeout: 5
  host_names:
    - ${DISCOURSE_DOMAIN:-discourse.rs.com}

development:
  prepared_statements: false
  adapter: postgresql
  database: discourse_development
  username: discourse
  password: discourse
  host: postgres
  port: 5432
  min_messages: warning
  pool: 5
  checkout_timeout: 5
  host_names:
    - ${DISCOURSE_DOMAIN:-discourse.rs.com}

test:
  prepared_statements: false
  adapter: postgresql
  database: discourse_test
  username: discourse
  password: discourse
  host: postgres
  port: 5432
  min_messages: warning
  pool: 2
  reaping_frequency: 0
  checkout_timeout: 5
  host_names:
    - ${DISCOURSE_DOMAIN:-discourse.rs.com}
EOF

git config --global --add safe.directory /var/www/discourse || true

echo "Waiting for postgres..."
until nc -z postgres 5432; do
  sleep 2
done

echo "Waiting for redis..."
until nc -z redis 6379; do
  sleep 2
done

echo "Preparing production database..."

bundle exec rake db:create
bundle exec rake db:migrate

echo "Applying site settings and activating admin user..."

bundle exec rails runner "
  admin_email = ENV.fetch('DISCOURSE_DEVELOPER_EMAILS', 'admin@example.com').split(',').first.strip
  admin_password = ENV.fetch('DISCOURSE_ADMIN_PASSWORD', 'Admin@1234567890')

  SiteSetting.must_approve_users = false if SiteSetting.respond_to?(:must_approve_users=)
  SiteSetting.disable_emails = 'yes' if SiteSetting.respond_to?(:disable_emails=)
  SiteSetting.enable_local_logins = true if SiteSetting.respond_to?(:enable_local_logins=)
  SiteSetting.login_required = false if SiteSetting.respond_to?(:login_required=)

  user = User.find_by_email(admin_email)

  if user.nil?
    username = admin_email.split('@').first.gsub(/[^a-zA-Z0-9_]/, '_')

    puts \"Admin user not found, creating: #{admin_email}\"

    user = User.new(
      username: username,
      name: 'Admin',
      email: admin_email,
      active: true,
      approved: true,
      admin: true,
      moderator: true
    )

    user.save!(validate: false)
  else
    puts \"Admin user found: #{admin_email}\"
  end

  user.update_columns(
    active: true,
    approved: true,
    approved_at: Time.now,
    approved_by_id: -1,
    admin: true,
    moderator: true
  )

  begin
    if defined?(UserEmail)
      existing = UserEmail.find_by(user_id: user.id, email: admin_email)

      if existing
        existing.update_columns(primary: true)
      else
        UserEmail.create!(
          user_id: user.id,
          email: admin_email,
          primary: true
        )
      end
    end
  rescue => e
    puts \"Skip updating admin UserEmail: #{e.class}: #{e.message}\"
  end

  begin
    if defined?(EmailToken)
      EmailToken.where(user_id: user.id, email: admin_email).update_all(
        confirmed: true,
        expired: false
      )

      EmailToken.where(user_id: user.id).update_all(
        confirmed: true,
        expired: false
      )
    end
  rescue => e
    puts \"Skip updating admin EmailToken: #{e.class}: #{e.message}\"
  end

  begin
    user.activate if user.respond_to?(:activate)
  rescue => e
    puts \"Skip user.activate: #{e.class}: #{e.message}\"
  end

  begin
    if defined?(PasswordResetter)
      PasswordResetter.new(user).reset_password(admin_password)
      puts \"Admin password reset by PasswordResetter\"
    else
      puts \"PasswordResetter not defined, skip password reset\"
    end
  rescue => e
    puts \"Skip password reset: #{e.class}: #{e.message}\"
  end

  User.where(active: false).find_each do |u|
    begin
      u.update_columns(
        active: true,
        approved: true,
        approved_at: Time.now,
        approved_by_id: -1
      )

      if defined?(EmailToken)
        EmailToken.where(user_id: u.id).update_all(
          confirmed: true,
          expired: false
        )
      end

      puts \"Activated user: #{u.id} / #{u.email}\"
    rescue => e
      puts \"Skip user #{u.id}: #{e.class}: #{e.message}\"
    end
  end

  puts \"Admin ready: #{admin_email} / #{admin_password}\"
"

echo "Cleaning frontend build cache..."
rm -rf frontend/discourse/node_modules/.embroider
rm -rf tmp/cache

if [ ! -f public/assets/manifest.json ] && [ -z "$(ls public/assets/.sprockets-manifest-* 2>/dev/null)" ]; then
  echo "Assets manifest not found, precompiling assets..."
  bundle exec rake assets:precompile
else
  echo "Assets already precompiled, skip assets:precompile"
fi

echo "Testing nginx config..."
nginx -t

echo "Starting Discourse Pitchfork app on 127.0.0.1:9292..."

export UNICORN_PORT=9292
export UNICORN_WORKERS="${UNICORN_WORKERS:-2}"
export UNICORN_SIDEKIQS="${UNICORN_SIDEKIQS:-1}"

bundle exec pitchfork -c config/pitchfork.conf.rb &
APP_PID=$!

sleep 5

if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "Discourse Pitchfork app failed to start"
  exit 1
fi

echo "Starting nginx on 0.0.0.0:80..."

exec nginx -g "daemon off;"
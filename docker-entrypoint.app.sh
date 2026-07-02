#!/usr/bin/env bash
set -e

cd /var/www/discourse

cat > config/discourse.conf <<'EOF'
hostname = localhost
developer_emails = admin@example.com

redis_host = redis
redis_port = 6379
redis_db = 0

message_bus_redis_host = redis
message_bus_redis_port = 6379
message_bus_redis_db = 0
EOF

cat > config/database.yml <<'EOF'
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
    - localhost

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
    - test.localhost
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

bundle exec rake db:create db:migrate

# 开发环境：禁用邮件发送、取消人工审批、自动激活未激活用户
bundle exec rails runner "
  SiteSetting.must_approve_users = false if SiteSetting.respond_to?(:must_approve_users=)
  SiteSetting.disable_emails = 'yes' if SiteSetting.respond_to?(:disable_emails=)

  User.where(active: false).find_each do |u|
    begin
      u.update_columns(
        active: true,
        approved: true,
        approved_at: Time.now,
        approved_by_id: -1
      )
      u.email_tokens.update_all(confirmed: true) if u.respond_to?(:email_tokens)
    rescue => e
      puts \"Skip user #{u.id}: #{e.message}\"
    end
  end
"

bundle exec rails server -b 0.0.0.0 -p 3000
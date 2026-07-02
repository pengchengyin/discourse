#!/usr/bin/env bash
set -e

cd /var/www/discourse

echo "Generating config/discourse.conf..."

cat > config/discourse.conf <<'EOF'
hostname = localhost
developer_emails = admin@example.com

redis_host = redis
redis_port = 6379
redis_db = 0

message_bus_redis_host = redis
message_bus_redis_port = 6379
message_bus_redis_db = 0

# 开发环境关闭邮件发送，避免未配置 SMTP 时卡在激活邮件
smtp_address =
smtp_port = 587
smtp_user_name =
smtp_password =
EOF

echo "Generating config/database.yml..."

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

echo "Preparing database..."
bundle exec rake db:create db:migrate

echo "Applying development site settings and activating users..."

bundle exec rails runner "
  admin_email = ENV.fetch('DISCOURSE_DEVELOPER_EMAILS', 'admin@example.com').split(',').first.strip
  admin_password = ENV.fetch('DISCOURSE_ADMIN_PASSWORD', 'Admin@123456')

  # 关闭人工审批
  if SiteSetting.respond_to?(:must_approve_users=)
    SiteSetting.must_approve_users = false
  end

  # 禁用邮件发送
  if SiteSetting.respond_to?(:disable_emails=)
    SiteSetting.disable_emails = 'yes'
  end

  # 允许本地账号登录
  if SiteSetting.respond_to?(:enable_local_logins=)
    SiteSetting.enable_local_logins = true
  end

  # 不强制登录浏览
  if SiteSetting.respond_to?(:login_required=)
    SiteSetting.login_required = false
  end

  # 开发环境下避免部分邮件相关流程阻塞
  if SiteSetting.respond_to?(:email_editable=)
    SiteSetting.email_editable = true
  end

  user = User.find_by_email(admin_email)

  if user.nil?
    puts \"Admin user not found, creating: #{admin_email}\"

    username = admin_email.split('@').first.gsub(/[^a-zA-Z0-9_]/, '_')

    user = User.new(
      username: username,
      name: 'Admin',
      email: admin_email,
      password: admin_password,
      password_confirmation: admin_password,
      active: true,
      approved: true,
      admin: true,
      moderator: true
    )

    user.save!
  else
    puts \"Admin user found: #{admin_email}\"

    user.password = admin_password
    user.password_confirmation = admin_password
    user.admin = true
    user.moderator = true
    user.active = true
    user.approved = true
    user.save!
  end

  # 强制激活 admin
  user.update_columns(
    active: true,
    approved: true,
    approved_at: Time.now,
    approved_by_id: -1,
    admin: true,
    moderator: true
  )

  # 确认 admin 邮箱 token
  begin
    user.email_tokens.update_all(confirmed: true) if user.respond_to?(:email_tokens)
  rescue => e
    puts \"Skip confirming admin email_tokens: #{e.message}\"
  end

  # 确认 user_emails，兼容新版 Discourse 结构
  begin
    if user.respond_to?(:user_emails)
      user.user_emails.update_all(primary: true)
    end
  rescue => e
    puts \"Skip updating admin user_emails: #{e.message}\"
  end

  puts \"Admin user ready: #{admin_email} / #{admin_password}\"

  # 激活其他未激活用户
  User.where(active: false).find_each do |u|
    begin
      u.update_columns(
        active: true,
        approved: true,
        approved_at: Time.now,
        approved_by_id: -1
      )

      u.email_tokens.update_all(confirmed: true) if u.respond_to?(:email_tokens)

      puts \"Activated user: #{u.id} / #{u.email}\"
    rescue => e
      puts \"Skip user #{u.id}: #{e.message}\"
    end
  end
"

echo "Starting Discourse Rails server..."

exec bundle exec rails server -b 0.0.0.0 -p 3000
# Discourse Docker Compose 部署文档

## 1. 部署目标

本文档用于部署基于自定义源码构建的 Discourse 服务，采用 Docker Compose 方式启动，包含：

- Discourse Web 服务
- Nginx 反向代理
- PostgreSQL 数据库，带 pgvector 扩展
- Redis 缓存服务
- 自动初始化数据库
- 自动创建管理员账号
- 支持管理员密码首次初始化与按需重置
- 支持通过 `.env` 配置访问域名、端口、管理员账号等参数
- 数据目录使用宿主机 bind mount，便于迁移和备份

整体访问链路如下：

```text
浏览器
  ↓
宿主机端口，例如 13000
  ↓
容器内 Nginx 80
  ↓
Discourse Pitchfork 127.0.0.1:9292
  ↓
PostgreSQL / Redis
```

---

如果直接使用harbor已有的镜像启动,无需源码,直接跳到[10. 启动服务](#10-启动服务)

## 2. 目录结构

项目根目录建议如下：

```text
discourse/
├── docker-compose.yml
├── Dockerfile.app
├── docker-entrypoint.app.sh
├── nginx-discourse.conf
├── .env
├── .dockerignore
└── data/
    ├── postgres/
    ├── redis/
    └── uploads/
```

其中：

| 路径 | 说明 |
|---|---|
| `docker-compose.yml` | Docker Compose 编排文件 |
| `Dockerfile.app` | Discourse Web 镜像构建文件 |
| `docker-entrypoint.app.sh` | Web 容器启动脚本 |
| `nginx-discourse.conf` | Nginx 配置文件 |
| `.env` | 部署参数配置(复制.env.default) |
| `.dockerignore` | Docker 构建忽略规则 |
| `data/postgres` | PostgreSQL 数据目录 |
| `data/redis` | Redis 数据目录 |
| `data/uploads` | Discourse 上传文件目录 |

---

## 3. 环境要求

目标服务器需要安装：

- Docker
- Docker Compose

验证命令：

```bash
docker version
docker-compose version
```

如果使用新版 Docker Compose 插件，也可以用：

```bash
docker compose version
```

本文档示例默认使用：

```bash
docker-compose
```

---

## 4. 常见访问场景

### 场景 1：直接访问宿主机 13000 端口

浏览器访问：

```text
http://discourse.rs.com:13000
```

`.env` 配置：

```env
DISCOURSE_DOMAIN=discourse.rs.com
DISCOURSE_EXTERNAL_PORT=13000
DISCOURSE_HOSTNAME=discourse.rs.com:13000
```

### 场景 2：直接访问标准 80 端口

浏览器访问：

```text
http://discourse.rs.com
```

`.env` 配置：

```env
DISCOURSE_DOMAIN=discourse.rs.com
DISCOURSE_EXTERNAL_PORT=80
DISCOURSE_HOSTNAME=discourse.rs.com
```

### 场景 3：外部 80 端口转发到宿主机 13000

浏览器访问：

```text
http://discourse.rs.com
```

防火墙或端口映射：

```text
外部 80 -> 宿主机 13000 -> 容器 80
```

`.env` 配置：

```env
DISCOURSE_DOMAIN=discourse.rs.com
DISCOURSE_EXTERNAL_PORT=13000
DISCOURSE_HOSTNAME=discourse.rs.com
```

注意：

```text
DISCOURSE_EXTERNAL_PORT 是 Docker 宿主机监听端口。
DISCOURSE_HOSTNAME 是浏览器地址栏中用户实际访问的 Host。
```

---

## 5. 域名设置

可以使用公开域名或者私有域名, 私有域名需配置本地hosts

如果域名没有配置 DNS，需要在访问电脑上配置 hosts。

Windows hosts 文件路径：

```text
C:\Windows\System32\drivers\etc\hosts
```

Linux hosts 文件路径：

```text
/etc/hosts
```

示例：

```text
172.25.3.41 discourse.rs.com
```

其中 `172.25.3.41` 替换为实际服务器 IP。

服务器本机也建议配置：

```bash
echo "172.25.3.41 discourse.rs.com" >> /etc/hosts
```

---

## 6. docker-compose.yml 说明

说明：

- Web 镜像名为 `harbor.rs.com/discourse/discourse-web:latest`
- 容器名仍为 `discourse-web`
- PostgreSQL、Redis 不对外暴露端口
- Web 服务只暴露 `.env` 中配置的端口
- 数据通过 `./data` 目录持久化，便于迁移

---

## 7. .dockerignore 说明

说明：

`.dockerignore` 只影响 Docker build 阶段的 `COPY .`，不会影响 `docker-compose.yml` 中的目录挂载。

---

## 8. 初始化数据目录

首次部署前创建数据目录(会自动创建)：

```bash
mkdir -p data/postgres data/redis data/uploads
```

如果出现权限问题，可先执行：

```bash
chmod -R 755 data/redis data/uploads
chmod -R 700 data/postgres
```

测试环境如果仍有权限问题，可临时放宽：

```bash
chmod -R 777 data/postgres data/redis data/uploads
```

生产环境不建议长期使用 `777` 权限。

---

## 9. 构建镜像(直接使用harbor已有的镜像可忽略)

执行：

```bash
docker-compose build web
```

如需完全重新构建：

```bash
docker-compose build --no-cache web
```

查看镜像：

```bash
docker images | grep harbor.rs.com/discourse/discourse-web
```

---

## 10. 启动服务

部署目录建议如下：

```text
discourse/
├── docker-compose.yml
├── .env(复制.env.default)
└── data/(自动创建)
    ├── postgres/
    ├── redis/
    └── uploads/
```


```bash
docker-compose up -d
```

查看容器状态：

```bash
docker-compose ps -a
```

查看日志：

```bash
docker-compose logs -f web
```

正常情况下日志应出现类似内容：

```text
Preparing production database...
Applying site settings and activating admin user...
Assets already precompiled, skip assets:precompile
Testing nginx config...
nginx: configuration file /etc/nginx/nginx.conf test is successful
Starting Discourse Pitchfork app on 127.0.0.1:9292...
Waiting for Discourse app port 9292...
Discourse app is listening on 127.0.0.1:9292
Starting nginx on 0.0.0.0:80...
```

---

## 11. 访问系统

根据 `.env` 配置访问。

例如：

```text
http://discourse.rs.com:13000
```

首次管理员账号：

```text
账号：admin@example.com
密码：Admin@1234567890
```

具体以 `.env` 中配置为准。

---

## 12. 管理员密码机制

启动脚本会自动处理管理员账号：

| 场景 | 行为 |
|---|---|
| 数据库为空，管理员不存在 | 自动创建管理员并设置默认密码 |
| 管理员已存在且已有密码 | 不覆盖密码 |
| 管理员已存在但没有密码 | 自动补充默认密码 |
| `RESET_ADMIN_PASSWORD=true` | 强制重置管理员密码 |

默认配置：

```env
RESET_ADMIN_PASSWORD=false
```

需要强制重置密码时，修改 `.env`：

```env
RESET_ADMIN_PASSWORD=true
```

然后重启：

```bash
docker-compose down
docker-compose up -d
docker-compose logs -f web
```

看到类似日志后说明重置成功：

```text
Admin password set because: RESET_ADMIN_PASSWORD=true
```

重置完成后，建议立即改回：

```env
RESET_ADMIN_PASSWORD=false
```

避免后续重启覆盖管理员在页面中修改的新密码。

---

## 13. 常用运维命令

### 查看所有容器

```bash
docker-compose ps -a
```

### 查看 Web 日志

```bash
docker-compose logs -f web
```

### 查看 PostgreSQL 日志

```bash
docker-compose logs -f postgres
```

### 查看 Redis 日志

```bash
docker-compose logs -f redis
```

### 重启 Web 服务

```bash
docker-compose restart web
```

### 停止全部服务

```bash
docker-compose down
```

### 启动全部服务

```bash
docker-compose up -d
```

---

## 14. 验证服务

### 验证 Web 端口

```bash
curl -I http://discourse.rs.com:13000/
```

正常返回应包含：

```text
HTTP/1.1 200 OK
```

或登录页相关返回。

### 验证容器内 Nginx

```bash
docker-compose exec web nginx -t
```

正常输出：

```text
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### 验证 Pitchfork 监听

```bash
docker-compose exec web bash -lc 'nc -z 127.0.0.1 9292 && echo ok'
```

正常输出：

```text
ok
```

### 验证数据库

```bash
docker-compose exec postgres psql -U discourse -d discourse -c "select now();"
```

---

## 15. 推送镜像到 Harbor

如果需要把 Web 镜像推送到 Harbor：

```bash
docker login harbor.rs.com
docker-compose build web
docker push harbor.rs.com/discourse/discourse-web:latest
```

建议正式交付时使用版本号：

```yaml
image: harbor.rs.com/discourse/discourse-web:v2026.7.0-rs
```

然后：

```bash
docker-compose build web
docker push harbor.rs.com/discourse/discourse-web:v2026.7.0-rs
```

---

## 16. 清理悬空镜像

查看悬空镜像：

```bash
docker images -f "dangling=true"
```

只删除 `<none>:<none>` 镜像：

```bash
docker image prune -f
```

清理构建缓存：

```bash
docker builder prune -f
```

注意不要随意执行：

```bash
docker image prune -a -f
```

该命令会删除所有未被容器使用的镜像，包括有 tag 的镜像。

---

## 17. 迁移部署

由于数据使用宿主机目录挂载，迁移时直接迁移项目目录即可。

### 17.1 源环境停服务

```bash
docker-compose down
```

### 17.2 打包项目目录

```bash
cd ..
tar czf discourse-deploy.tar.gz discourse/
```

确保包含：

```text
docker-compose.yml
.env
Dockerfile.app
docker-entrypoint.app.sh
nginx-discourse.conf
.dockerignore
data/
```

### 17.3 目标环境解压

```bash
mkdir -p /opt
tar xzf discourse-deploy.tar.gz -C /opt
cd /opt/discourse
```

### 17.4 导入镜像

如果目标环境无法联网，需要提前导出镜像。

源环境导出：

```bash
docker save -o discourse-images.tar \
  harbor.rs.com/discourse/discourse-web:latest \
  harbor.rs.com/repo/pgvector:pg15 \
  harbor.rs.com/repo/redis:7
```

目标环境导入：

```bash
docker load -i discourse-images.tar
```

### 17.5 修改目标环境配置

根据目标环境修改 `.env`：

```env
DISCOURSE_DOMAIN=discourse.rs.com
DISCOURSE_EXTERNAL_PORT=13000
DISCOURSE_HOSTNAME=discourse.rs.com:13000
```

同时配置目标访问机器的 hosts：

```text
目标服务器IP discourse.rs.com
```

### 17.6 启动目标环境

```bash
docker-compose up -d
docker-compose logs -f web
```

---

## 18. 备份建议

### 18.1 停机备份

```bash
docker-compose down
tar czf discourse-data-backup.tar.gz data/
docker-compose up -d
```

### 18.2 PostgreSQL 逻辑备份

运行状态下导出数据库：

```bash
mkdir -p backup

docker-compose exec -T postgres pg_dump \
  -U discourse \
  -d discourse \
  -Fc \
  -f /tmp/discourse.dump

docker cp discourse-postgres:/tmp/discourse.dump backup/discourse.dump
```

恢复时：

```bash
docker cp backup/discourse.dump discourse-postgres:/tmp/discourse.dump

docker-compose exec postgres psql -U discourse -d discourse -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

docker-compose exec postgres pg_restore \
  -U discourse \
  -d discourse \
  --clean \
  --if-exists \
  /tmp/discourse.dump
```

---

## 19. 常见问题

### 19.1 登录成功后跳转丢失端口

现象：

```text
http://discourse.rs.com:13000 登录后跳转到 http://discourse.rs.com/
```

原因：

```text
DISCOURSE_HOSTNAME 未配置为浏览器实际访问地址。
```

修复：

```env
DISCOURSE_HOSTNAME=discourse.rs.com:13000
```

然后重启：

```bash
docker-compose down
docker-compose up -d
```

### 19.2 Nginx 502 Bad Gateway

查看日志：

```bash
docker-compose logs -f web
```

如果看到：

```text
connect() failed (111: Connection refused) while connecting to upstream
```

说明 Nginx 转发到 `127.0.0.1:9292` 时，Pitchfork 尚未监听或已退出。

处理：

```bash
docker-compose restart web
docker-compose logs -f web
```

重点查看 Pitchfork 是否有 Ruby 异常。

### 19.3 MiniRacer::ParseError

如果出现：

```text
MiniRacer::ParseError: Unexpected token ';'
```

通常是数据库 `site_settings` 中存在未展开变量，例如：

```text
${DISCOURSE_HOSTNAME:-discourse.rs.com}
```

查询：

```bash
docker-compose exec postgres psql -U discourse -d discourse -c "
select name, value
from site_settings
where value like '%\${%';
"
```

删除错误值：

```bash
docker-compose exec postgres psql -U discourse -d discourse -c "
delete from site_settings
where value like '%\${%';
"
```

清缓存：

```bash
docker-compose exec web bash -lc 'cd /var/www/discourse && bundle exec rails runner - <<'"'"'RUBY'"'"'
Discourse.cache.clear
SiteSetting.clear_cache! if SiteSetting.respond_to?(:clear_cache!)
puts "cache cleared"
RUBY'
```

### 19.4 MaxMind 警告

日志：

```text
MaxMind IP database download requires an account ID and a license key
```

这是 IP 地理位置库提示，不影响系统启动、登录、发帖。内网测试环境可以忽略。

### 19.5 hostname 带端口的邮件域名警告

日志：

```text
WARNING: Discourse hostname: discourse.rs.com:13000 is not a valid domain for emails!
```

原因是 hostname 带端口，对邮件域名不是合法格式。当前测试环境已关闭邮件发送：

```conf
disable_emails = yes
```

可以忽略。

---

## 20. 交付检查清单

部署完成后检查：

```text
[ ] docker-compose ps 显示 postgres、redis、web 均为 Up
[ ] web 日志无 Pitchfork BootFailure
[ ] nginx -t 成功
[ ] 127.0.0.1:9292 监听正常
[ ] 浏览器可访问 http://discourse.rs.com:端口
[ ] 管理员账号可登录
[ ] 登录后地址不会丢失端口
[ ] 发帖、上传附件功能正常
[ ] data/postgres、data/redis、data/uploads 有数据写入
[ ] .env 中 RESET_ADMIN_PASSWORD 已恢复为 false
```

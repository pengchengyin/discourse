FROM discourse/base:release

ENV APP_ROOT=/var/www/discourse
ENV RAILS_ENV=development
ENV RACK_ENV=development
ENV NODE_ENV=development
ENV DISCOURSE_HOSTNAME=localhost
ENV CI=true

USER root

RUN apt-get update && apt-get install -y \
    git \
    netcat-openbsd \
    postgresql-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_ROOT}

COPY . ${APP_ROOT}

# 解决 Git dubious ownership 问题
RUN git config --global --add safe.directory ${APP_ROOT} || true

# 安装 Ruby 依赖
RUN bundle config set path vendor/bundle \
    && bundle install --jobs 4 --retry 3

# 避免把宿主机 node_modules 带进镜像后，pnpm 在无 TTY 环境中删除失败
RUN rm -rf node_modules app/assets/javascripts/*/node_modules \
    && corepack enable || true; \
    if [ -f pnpm-lock.yaml ]; then \
      CI=true pnpm install --frozen-lockfile; \
    elif [ -f yarn.lock ]; then \
      CI=true yarn install --frozen-lockfile; \
    else \
      CI=true yarn install; \
    fi

EXPOSE 3000

CMD ["bash", "-lc", "\
  git config --global --add safe.directory /var/www/discourse || true; \
  echo 'Waiting for postgres...'; \
  until nc -z postgres 5432; do sleep 2; done; \
  echo 'Waiting for redis...'; \
  until nc -z redis 6379; do sleep 2; done; \
  bundle exec rake db:create db:migrate; \
  bundle exec rails server -b 0.0.0.0 -p 3000 \
"]
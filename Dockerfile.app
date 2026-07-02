FROM discourse/base:release

ENV APP_ROOT=/var/www/discourse
ENV RAILS_ENV=development
ENV RACK_ENV=development
ENV NODE_ENV=development
ENV DISCOURSE_HOSTNAME=localhost
ENV CI=true

# 关键：不要排除 development/test 依赖
ENV BUNDLE_WITHOUT=""
ENV BUNDLE_DEPLOYMENT=false

USER root

RUN apt-get update && apt-get install -y \
    git \
    netcat-openbsd \
    postgresql-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_ROOT}

COPY . ${APP_ROOT}

RUN git config --global --add safe.directory ${APP_ROOT} || true

# 清理基础镜像或源码中可能继承的 bundler 排除配置，确保 development 依赖被安装
RUN rm -rf .bundle \
    && bundle config unset without || true \
    && bundle config unset deployment || true \
    && bundle config set path vendor/bundle \
    && bundle add liquid \
    && bundle install --jobs 4 --retry 3

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

COPY docker-entrypoint.app.sh /usr/local/bin/docker-entrypoint.app.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.app.sh

CMD ["/usr/local/bin/docker-entrypoint.app.sh"]
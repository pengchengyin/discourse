FROM discourse/base:release

ENV APP_ROOT=/var/www/discourse
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV NODE_ENV=production
ENV DISCOURSE_HOSTNAME=localhost
ENV CI=true

# production 环境不安装 development/test 依赖
ENV BUNDLE_WITHOUT="development:test"
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

# 安装 Ruby 依赖
# liquid 是 discourse-workflows 插件需要的依赖，建议后续正式写进 Gemfile 或插件依赖中
RUN rm -rf .bundle \
    && bundle config unset without || true \
    && bundle config unset deployment || true \
    && bundle config set path vendor/bundle \
    && (grep -q 'gem "liquid"' Gemfile || echo 'gem "liquid"' >> Gemfile) \
    && bundle install --jobs 4 --retry 3

# 清理所有可能从宿主机复制进来的前端依赖和构建缓存，然后重新安装
RUN find . -name node_modules -type d -prune -exec rm -rf '{}' + \
    && find . -name .embroider -type d -prune -exec rm -rf '{}' + \
    && rm -rf public/assets app/assets/builds tmp/cache \
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
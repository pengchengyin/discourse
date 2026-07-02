FROM discourse/base:release

ENV APP_ROOT=/var/www/discourse
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV NODE_ENV=production
ENV DISCOURSE_HOSTNAME=localhost
ENV CI=true

# production 环境不需要 development/test 依赖
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

# 如果插件 discourse-workflows 依赖 liquid，建议源码 Gemfile 中正式加入：
# gem "liquid"
# 这里保留兜底，避免缺失 liquid 导致启动失败
RUN rm -rf .bundle \
    && bundle config unset without || true \
    && bundle config unset deployment || true \
    && bundle config set path vendor/bundle \
    && grep -q 'gem "liquid"' Gemfile || echo 'gem "liquid"' >> Gemfile \
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
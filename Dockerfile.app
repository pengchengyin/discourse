FROM discourse/base:release

ENV APP_ROOT=/var/www/discourse
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV NODE_ENV=production
ENV DISCOURSE_HOSTNAME=discourse.rs.com
ENV CI=true

ENV BUNDLE_WITHOUT="development:test"
ENV BUNDLE_DEPLOYMENT=false

USER root

RUN apt-get update && apt-get install -y \
    git \
    nginx \
    netcat-openbsd \
    postgresql-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/nginx /var/lib/nginx /run/nginx \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
    
WORKDIR ${APP_ROOT}

COPY . ${APP_ROOT}

RUN git config --global --add safe.directory ${APP_ROOT} || true

RUN rm -f /etc/nginx/sites-enabled/default \
    && rm -f /etc/nginx/conf.d/default.conf || true

COPY nginx-discourse.conf /etc/nginx/conf.d/discourse.conf

RUN find bin script -type f -exec sed -i 's/\r$//' {} \; \
    && find bin script -type f -exec chmod +x {} \;

RUN rm -rf .bundle \
    && bundle config unset without || true \
    && bundle config unset deployment || true \
    && bundle config set path vendor/bundle \
    && if ! grep -q 'gem "liquid"' Gemfile; then echo 'gem "liquid"' >> Gemfile; fi \
    && bundle install --jobs 4 --retry 3

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

EXPOSE 80

COPY docker-entrypoint.app.sh /usr/local/bin/docker-entrypoint.app.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.app.sh

CMD ["/usr/local/bin/docker-entrypoint.app.sh"]
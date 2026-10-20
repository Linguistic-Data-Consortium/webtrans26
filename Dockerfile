# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t webtrans26 .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name webtrans26 webtrans26

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

### more
RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends apt-transport-https netcat-openbsd libpq5 libpq-dev unzip
# Install Node 22 from NodeSource. Use `curl -fsSL` so a failed download aborts
# the build instead of silently falling back to Debian's Node 18, and assert the
# resulting major version so a stale/broken layer can never ship an old Node again.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends nodejs && \
    node -v && \
    node -e 'process.exit(parseInt(process.versions.node) >= 20 ? 0 : 1)'

# use bun instead of node
RUN curl -fsSL https://bun.sh/install | bash
ENV BUN_INSTALL="/root/.bun"
ENV PATH="$BUN_INSTALL/bin:$PATH"
# end base


# Throw-away build stage to reduce size of final image
### build stage was broken up into gem, lock, bundled, and build stages
FROM base AS gem
# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
# end gem


### when changing the Gemfile, target lock in the compose file
FROM gem AS lock
RUN apt-get update -qq && apt-get install -y ca-certificates && update-ca-certificates
RUN bundle config set --global ssl_verify_mode 0
RUN bundle install
RUN bundle lock --add-platform x86_64-linux
# end lock


FROM gem AS bundled
# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

RUN apt-get update -qq && apt-get install -y ca-certificates && update-ca-certificates
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Install node_modules INSIDE the container so its binaries are linux-arch
# matched. Don't rely on the host's node_modules being COPYed in via the
# `COPY . .` above — those would be macOS-built and either crash or trigger
# vite-ruby to fall back to invoking `bun` (which then has its own PATH
# discovery issues in spawned sub-processes).
RUN bun install --frozen-lockfile

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/
# end bundled


FROM bundled AS build
# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN echo "PATH=$PATH" && \
    which bun || echo "bun NOT on PATH" && \
    ls -la /root/.bun/bin/bun 2>&1 || echo "bun NOT at /root/.bun/bin/bun" && \
    ls -la /rails/node_modules/.bin/vite 2>&1 || echo "vite NOT in node_modules/.bin" && \
    test -d /rails/node_modules && echo "node_modules exists ($(ls /rails/node_modules | wc -l) entries)" || echo "node_modules DOES NOT EXIST"
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
# end build


### create a dev version
# The bundled stage installs gems with BUNDLE_WITHOUT="development", so the
# dev-group gems (debug, web-console, etc.) aren't there. Override here and
# re-run bundle install — Bundler adds the missing groups without disturbing
# what's already installed. Same env override for runtime so RAILS_ENV is dev.
FROM bundled AS dev
ENV RAILS_ENV="development" \
    BUNDLE_DEPLOYMENT="" \
    BUNDLE_WITHOUT=""
RUN bundle install
# ENTRYPOINT ["./docker-entrypoint.sh"]
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bin/rails", "s", "-b", "0.0.0.0"]
#CMD ["sleep", "300"]
# end dev


# Final stage for app image
FROM base
# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
   useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
   chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]

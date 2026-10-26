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
# Node and bun are NOT installed in this stage. They are build-time only —
# the asset build needs them, production runs neither — and the final stage
# starts FROM base, so whatever is here ships. They live in `gem` instead,
# which every stage needing them descends from. Worth ~335 MB of image.
# end base


# Throw-away build stage to reduce size of final image
### build stage was broken up into gem, lock, bundled, and build stages
FROM base AS gem

# Node and bun, moved out of `base` so the final image does not carry them:
# nodejs is ~228 MB and the bun install ~107 MB, and production runs neither.
# Every stage that needs them — lock, bundled, build, dev — descends from here.
# `unzip`, which the bun installer requires, stays in base's apt line.
# Install Node 22 from NodeSource. Use `curl -fsSL` so a failed download aborts
# the build instead of silently falling back to Debian's Node 18, and assert the
# resulting major version so a stale/broken layer can never ship an old Node again.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends nodejs && \
    node -v && \
    node -e 'process.exit(parseInt(process.versions.node) >= 20 ? 0 : 1)'

# use bun instead of node
# The `| bash` is why this needs a check: `curl -f` on a failure writes nothing,
# bash reads empty input and exits 0, so the layer "succeeds" with bun never
# installed — and the build goes on to fail fifty lines later with
# `bun: not found`, pointing at the wrong line. Seen for real: the script said
# "error: unzip is required to install bun" and the build carried on.
#
# Asking bun its version is what turns that into a failure here, where the
# install is. (unzip comes from the apt line above; the script needs it.)
RUN curl -fsSL https://bun.sh/install | bash && \
    "$HOME/.bun/bin/bun" --version
ENV BUN_INSTALL="/root/.bun"
ENV PATH="$BUN_INSTALL/bin:$PATH"

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

# node_modules exists only to build the assets. Production serves them from
# public/vite and never runs vite: autoBuild is false there (config/vite.json
# sets it for development, test and repl only, and vite_ruby's own default is
# false), and nothing in the app shells out to node or bun at runtime.
#
# It is removed *here*, in the build stage, rather than in the final stage,
# because deleting files in a later layer does not shrink the image — the bytes
# stay in the layer that added them. The final stage copies what is left.
#
# Worth ~650 MB, of which @huggingface/transformers' dependencies are ~440 MB
# (onnxruntime-web 140 MB, and onnxruntime-node 289 MB, which a browser build
# never imports).
RUN rm -rf node_modules
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

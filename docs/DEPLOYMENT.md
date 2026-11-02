# Deploying with Kamal

The Quick start in the repository's `README.md` runs the app locally under
Docker Compose. This is about putting it on a server.

Deployment uses [Kamal](https://kamal-deploy.org), which can target **any
machine you can reach over SSH and run Docker on** — a cloud VM, a rented
server, a box under a desk. It builds the image on your own machine, pushes it
to a registry Kamal starts there for the occasion, and runs it on the host over
SSH — so no registry account is involved and the image never leaves your
network. There is no Kubernetes, no agent on the server,
and nothing to install there beyond Docker. The rest of this document describes
that process and what each piece is for.

**This guide assumes you are serving the app over HTTPS**, because annotators
sign in with a password and the app is not worth deploying without it. That
makes one decision worth settling before anything else: **does the machine you
are deploying to have a hostname?** With one, the proxy obtains and renews a
certificate for you; without one, you browse to the IP address and supply a
self-signed certificate you generate. Both are described under [SSL](#ssl),
and the repository ships a ready-made deploy file for each answer — so once you
have decided, most of the configuration is copying one file and replacing a few
placeholders. The rest of the setup is identical either way.

## If you want to create a VM on AWS EC2

**Follow `aws/deploying_to_aws.md` in this repository instead.** It is a
step-by-step walkthrough — network, security groups, SSH key, launch template,
instance — and it ends by setting the Kamal values and deploying, so you should
not need to come back here.

Come back if something doesn't fit, or if you want to know *why* a particular
setting is needed. EC2 is one way to get a machine that meets the requirements
below; nothing in the app assumes AWS.

## What the deployment machine has to be

Any machine you can reach over SSH and run Docker on. A cloud VM, a rented
server, a box under a desk — Kamal does not care. The requirements are:

| | |
| --- | --- |
| **Docker** | installed and running. Kamal does the rest. |
| **SSH access** | key-based, as a user in the `docker` group. Kamal runs `docker` over SSH, so a user who needs `sudo` for it will not work. |
| **Ports 80 and 443 reachable** | the app's proxy terminates HTTP/HTTPS. 443 is only needed if you let it get a certificate (below). |
| **Outbound HTTPS** | only to reach Let's Encrypt, if you use `proxy.ssl`. **Not for the image** — the deploy files use a local registry and send it over the SSH connection, so the server needs no route to a registry. See [The registry](#the-registry). |
| **A disk that survives redeploys** | the database is SQLite in `/rails/storage`, mounted from a Docker volume. See [Persistence](#persistence). |
| **Architecture matching your build** | an image built on an Apple Silicon Mac will not run on an x86_64 server unless you build for it. See [Architecture](#architecture). |

Memory and CPU depend on your transcription load. The app itself is a single
Puma process plus Solid Queue in-process; the audio work happens in the
annotator's browser, not on the server.

`aws/deploying_to_aws.md` produces a machine that meets all of this: its
cloud-init config installs Docker and adds the login user to the `docker` group,
and its security groups open 80 and 443 while restricting SSH.

## First: make your own credentials

**A fresh clone has no credentials and cannot boot until you make some.** This
repository deliberately ships neither `config/credentials.yml.enc` nor
`config/master.key`, so there is one command to run before anything else:

```sh
bin/rails credentials:edit
```

That writes both files: a new `config/master.key` and a new
`config/credentials.yml.enc` containing a freshly generated `secret_key_base`.
Save the editor and you are done.

**Why it isn't shipped.** `secret_key_base` signs every session cookie, so it
has to differ between instances — if two deployments shared one, a cookie
minted by either would be accepted by both. An encrypted file in a public
repository could not give you that: everyone cloning would start from the same
blob, and anyone holding the key could forge a session on every instance that
kept it. So each deployment generates its own.

**Then look after the key.**

| | |
| --- | --- |
| `config/master.key` | **never commit it.** `/config/*.key` is already in `.gitignore`. `.kamal/secrets` reads the file at deploy time and Kamal injects it as an environment variable; it never goes into the image. **If you lose it, nothing can decrypt your credentials again** — put a copy in a password manager. |
| `config/credentials.yml.enc` | untracked, because it is not ours to ship. In your own fork it is worth committing — that is the normal Rails arrangement, and it is useless to anyone without the key. |

Add anything else the app can use to the same file, with the same command —
`bin/rails credentials:edit` — in the shape
[Configuration](CONFIGURATION.md) describes: `smtp`, `jwt_secret`,
`cognito_pool_id`. All of them are optional and
all are off when absent.

### Or skip credentials entirely

Rails reads `ENV["SECRET_KEY_BASE"]` ahead of the credentials file, so you can
run with no credentials and no master key at all:

```yaml
# config/deploy.yml
env:
  secret:
    - SECRET_KEY_BASE
```

```sh
# .kamal/secrets — replace the RAILS_MASTER_KEY line with this
SECRET_KEY_BASE=$SECRET_KEY_BASE
```

and `export SECRET_KEY_BASE=$(openssl rand -hex 64)` in the shell you deploy
from. Keep that value somewhere: changing it signs every existing session out.

**Replace the line rather than leaving both.** `RAILS_MASTER_KEY=$(cat
config/master.key)` with no such file prints `cat: config/master.key: No such
file or directory` and passes an empty value through, which works but looks
like a failure every deploy.

With no credentials file, every credential reads as `nil` rather than raising,
so the app boots and runs. What you give up is anywhere to put the *other*
secrets. SMTP stays off, which is its default anyway. `jwt_secret`
is the one to know about: `/jwts` mints tokens for API clients and errors
without it — no part of the app's own interface calls it, so nothing an
annotator does notices, but it is a broken route rather than a disabled one.

Use `credentials:edit` if you expect to need any of those, which is why it is
the one above.

## Choosing a `config/deploy.yml`

**There is no `config/deploy.yml` in the repository.** Two ready-made versions
ship instead, one per answer to the hostname question, and the first step of any
deploy is to copy one of them into place:

```sh
cp config/deploy.yml.hostname config/deploy.yml     # a DNS name points at the machine
# or
cp config/deploy.yml.ip config/deploy.yml           # you will reach it by IP
```

Until you do, every `kamal` command stops with `Configuration file not found in
…/config/deploy.yml`. It is deliberately absent rather than shipped as
Kamal's default, because that default has no `proxy` block at all: fill in just
the server and registry and you get a working deploy that serves plain HTTP.
Starting from one of these two makes HTTPS the thing you'd have to remove.

Your copy is untracked. In your own fork it is worth committing, once the
placeholders below are real values; it is the record of where this app is
deployed.

Both are set up for a **local registry**, for an `ubuntu` login user, and for
HTTPS. They differ only in `servers.web`, in the `proxy` block, and — for the
IP version — in two certificate secrets. There are only two placeholders:

| Placeholder | Replace with |
| --- | --- |
| `your-hostname` / `your-ip` | the machine's DNS name or IP address, in **both** `servers.web` and `proxy.host`. |
| `ssh.user: ubuntu` | your login user, if it isn't `ubuntu`. It has to be in the `docker` group — Kamal runs `docker` over SSH and will not use `sudo`. |

There is deliberately no registry account to fill in — see below. The IP
version needs two secrets for its certificate, which [SSL](#ssl) covers.

### What the keys mean

Both files are Kamal's own template with this app's values filled in, so the
comments in them are the first reference. The ones that matter:

| Key | |
| --- | --- |
| `servers.web` | the host(s) to deploy to, as IP or hostname. |
| `image` | `webtrans26`, unqualified, which is right for the local registry. An external registry needs it namespaced: `your-user/webtrans26`. |
| `registry.server` | `localhost:5555` — the local registry. See [The registry](#the-registry). |
| `registry.username`, `registry.password` | **commented out**, and valid that way only because the registry is local. |
| `proxy` | configured for HTTPS — differently in the two files. See [SSL](#ssl). |
| `ssh.user` | `ubuntu`. It has to be a user in the `docker` group: Kamal runs `docker` over SSH and will not use `sudo`. |
| `volumes` | the SQLite database. See [Persistence](#persistence). |
| `env.clear` | the app's own settings, listed as comments. See [Application configuration](#application-configuration). |

One trap, if you start commenting things out: `registry:` must not end up
empty. Both files ship with `server:` active and `username`/`password`
commented, which is valid; comment out `server:` as well and the key has
nothing under it, and Kamal stops with `registry: should be a hash`, which does
not hint at the cause.

### The registry

**The deploy does not need a registry account, and the server does not need to
reach one.** Kamal builds the image on the machine you deploy *from*, and both
deploy files point it at a registry on that same machine:

```yaml
registry:
  server: localhost:5555
```

Any `server` matching `^localhost[:$]` switches Kamal into this mode
(`configuration/registry.rb`). Three things follow, and they are why the
templates look the way they do:

| | |
| --- | --- |
| **the registry is started for you** | `kamal build` runs `docker start kamal-docker-registry \|\| docker run --detach -p 127.0.0.1:5555:5000 --name kamal-docker-registry registry:3`. Nothing to install; it is Docker's own registry image. |
| **the image reaches the servers over SSH** | before pulling, Kamal forwards port 5555 to each host over the connection it already has, so the host's `docker pull localhost:5555/webtrans26` comes back through the tunnel. The image never crosses the public internet. |
| **there is no login** | `Kamal::Commands::Registry#login` returns early for a local registry, and the config validator stops requiring `username` and `password` — which is the only reason those two lines can be commented out. |

So no `KAMAL_REGISTRY_PASSWORD`, no access token, no account, and nothing
published anywhere. The line for it in `.kamal/secrets` is commented out to
match.

**What it costs.** The registry container holds the images, and it has no
volume — so its contents live in the container's own filesystem. `docker stop`
and a later `docker start` keep them, but **removing that container discards
every image in it**, and with them the versions `bin/kamal rollback` would roll
back to. Leave `kamal-docker-registry` alone on the build machine, and expect
to rebuild rather than roll back if you ever clear it.

And because the image is built locally, the build machine needs Docker and
enough disk for the build cache. That was already true — Kamal builds there
either way — but with no external registry it is also the only place the image
exists.

#### Using an external registry instead

Reasonable if you deploy from more than one machine, or want the image kept
somewhere durable. In `config/deploy.yml`:

1. Set `registry.server` to the endpoint — `ghcr.io`,
   `registry.digitalocean.com`, `your-registry.example.com:5000` — or delete
   the line for Docker Hub, which is what an unset `server` selects.
   (`hub.docker.com` is the website, not a registry endpoint.)
2. Uncomment `username` and `password`. They are required as soon as the
   registry is not local.
3. Namespace `image:` by your account: `your-user/webtrans26`. Docker Hub and
   most others reject an unqualified name.
4. Uncomment the `KAMAL_REGISTRY_PASSWORD` line in `.kamal/secrets` and export
   it in the shell you deploy from:

   ```sh
   export KAMAL_REGISTRY_PASSWORD=...
   ```

   On Docker Hub that is an access token from **Account settings → Personal
   access tokens**, not your password. Forget the export and the secret
   resolves to an empty string, so the failure arrives later as a registry
   login error rather than a configuration one.

**Check the repository is private before the first push.** The image carries
the whole application directory; `.dockerignore` is what decides what stays
out of it. A public repository on a registry publishes all of it to anyone who
looks.

### SSL

**These instructions assume you are serving HTTPS.** Annotators sign in with a
password and the audio they work on is often not public, so the app treats TLS
as the normal case: `SSL` defaults to on in production, which redirects HTTP to
HTTPS and marks session cookies secure.

How you get a certificate depends on one decision — the same one that picks
which of the two deploy files you copy, so make it first.

#### Decide: does the machine have a hostname?

| | | Deploy file |
| --- | --- | --- |
| **Yes** — a DNS name that already resolves to the server | Kamal gets a certificate from Let's Encrypt for you, and renews it. [Go here](#with-a-hostname-automatic-certificate). | `config/deploy.yml.hostname` |
| **No** — you will reach it by IP address | You generate a self-signed certificate for that IP. Browsers warn the first time and you accept it. [Go here](#without-a-hostname-self-signed-certificate). | `config/deploy.yml.ip` |

A hostname is better if you can get one: no browser warnings, and renewal is
automatic. But a self-signed certificate on an IP is a real deployment, and far
better than plain HTTP.

#### With a hostname: automatic certificate

`config/deploy.yml.hostname` already has the proxy block; replace the
placeholder with your name:

```yaml
proxy:
  ssl: true
  host: your-hostname        # -> your-host.example.edu
```

That is all there is to it. `SSL` is already on, Kamal requests the certificate
on the next deploy, and renews it from then on. (If you are editing the default
file rather than copying the template, the block is commented out — uncomment
it and write the same three lines.)

Two things must be true or the request fails: the hostname must already resolve
to the server, and port 443 must be reachable from the internet — Let's Encrypt
connects back to prove you control the name.

#### Without a hostname: self-signed certificate

`config/deploy.yml.ip` already has the proxy block and the two secret names, so
what is left is the certificate itself and one edit to `.kamal/secrets`.

Generate a certificate for the server's IP. The `subjectAltName` is the part
that matters — a certificate naming only a `CN` is rejected by modern browsers:

```sh
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout config/privkey.pem -out config/fullchain.pem \
  -subj "/CN=203.0.113.25" \
  -addext "subjectAltName=IP:203.0.113.25"
```

Use your server's address in both places. Check it took:

```sh
openssl x509 -in config/fullchain.pem -noout -text | grep -A1 "Subject Alternative Name"
```

should print `IP Address:203.0.113.25`.

**The key stays out of git.** `/config/*.pem` is already in `.gitignore`. Confirm
it, since a private key committed once is compromised even if a later commit
removes it:

```sh
git check-ignore -v config/privkey.pem
```

Now point Kamal at them. Add two lines to `.kamal/secrets`, which is where
Kamal reads the file contents at deploy time:

```
APP_CERT_PEM=$(cat config/fullchain.pem)
APP_PRIVATE_KEY_PEM=$(cat config/privkey.pem)
```

The rest is already in `config/deploy.yml.ip` — the proxy block, with your IP
to fill in:

```yaml
proxy:
  ssl:
    enable: true
    certificate_pem: APP_CERT_PEM
    private_key_pem: APP_PRIVATE_KEY_PEM
  host: your-ip              # -> 203.0.113.25
```

and the same two names under `env.secret`, so Kamal passes them into the
container as well as to the proxy:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - APP_CERT_PEM
    - APP_PRIVATE_KEY_PEM
```

Both places are needed. If you are editing the default file instead of copying
the template, add all of it by hand.

One thing not to read too much into: what turns TLS on here is the *presence*
of the `ssl:` block, not the `enable: true` inside it — Kamal treats any
`ssl:` hash as enabled and never looks at that key. Setting it to `false`
would not give you HTTP; see [below](#if-you-really-want-plain-http) for that.

The first time you open `https://203.0.113.25` the browser will warn that the
certificate is not from a recognised authority. That is expected for a
self-signed certificate: accept it and the connection is encrypted from then
on. What you lose relative to a real certificate is proof of *who* the server
is, not the encryption.

This is the same mechanism you would use for a certificate issued by an
internal CA rather than a self-signed one — nothing about it is a workaround.
If your organisation runs its own CA, a certificate from it removes the warning
on managed machines.

Remember the expiry. `-days 365` above means you regenerate and redeploy in a
year; there is nothing automatic about it.

#### If you really want plain HTTP

Copy either file, delete its `proxy:` block, and set `SSL: false` under
`env.clear`. The app
then serves HTTP on port 80 with no redirect and no secure-cookie flag.
Everything typed into it, passwords included, crosses the network in the clear
— so this is for a throwaway trial on a trusted network, not for recordings you
care about.

### Persistence

```yaml
volumes:
  - "webtrans26_storage:/rails/storage"
```

The database is SQLite under `/rails/storage`, so **that volume is the whole
database**. It is a named Docker volume, which survives redeploys but lives on
that one host — so this configuration is single-server by nature. Back it up
like a database, not like a cache: `docker run --rm -v webtrans26_storage:/v
-v "$PWD:/out" alpine tar czf /out/storage.tgz -C /v .` is enough for a
snapshot.

`bin/docker-entrypoint` runs `bin/rails db:prepare` on boot, so a first deploy
creates and migrates the database with no extra step.

### Architecture

The image is built from `ruby:3.4.3-slim` for the architecture you build on. On
an Apple Silicon Mac deploying to an x86_64 server, either build remotely or
tell Kamal to build for the target:

```yaml
builder:
  arch: amd64
```

Without that the container will fail to start, usually with an `exec format
error` that doesn't name the cause.

## Secrets

`.kamal/secrets` ships with **one** live line, reading from the machine you
deploy *from*:

```
RAILS_MASTER_KEY=$(cat config/master.key)
```

The master key is how the container gets to decrypt
`config/credentials.yml.enc`. Neither file is in the repository — **you create
both with one command**, see
[First: make your own credentials](#first-make-your-own-credentials).
`config/master.key` is gitignored; Kamal reads the file and injects it as an
environment variable, and it never goes into the image.

If that file does not exist, `cat` fails, the secret resolves to an empty
string, and the deploy carries on with `RAILS_MASTER_KEY=` — printing
`cat: config/master.key: No such file or directory` on the way. Harmless if you
meant to use `SECRET_KEY_BASE` instead, but then replace the line rather than
leaving it.

`KAMAL_REGISTRY_PASSWORD` is in the file too but **commented out**, because the
deploy files use a local registry and there is nothing to log in to. Uncomment
it only if you switch to an external registry —
[Using an external registry instead](#using-an-external-registry-instead).

Nothing here is a file of secrets. Each line is a *command* Kamal runs to fetch
one, which is why the file is safe to commit.

A commented-out secret that `deploy.yml` references stops the deploy with
`Secret 'NAME' not found in .kamal/secrets` — and it says that even if the
environment variable is set in your shell, because the file is what wires the
two together. The IP route's two certificate secrets are the case to watch:
[SSL](#ssl) has you add them.

## Application configuration

The app runs with no external dependencies by default: no SMTP, no cloud
credentials, no speech services. Each is opt-in through an environment variable
set under `env.clear` in `deploy.yml`, where they are listed as comments with
what they do. See [Configuration](CONFIGURATION.md) for the full table.

The two worth knowing about before a first deploy:

- **`APP_HOST`** — the hostname used in links in activation and password-reset
  email. Wrong or unset, those links point somewhere useless.
- **`AWS_REGION`** — required for `s3://` kit sources and the Browse tab,
  because the browser gets S3 credentials from Cognito via `POST /token` and the
  AWS SDK refuses to build a client without a region. Until it is set, those
  features report themselves unavailable rather than failing.

Cognito itself is configured in Rails credentials (`cognito_pool_id`,
`cognito_provider_name`), via `bin/rails credentials:edit` — **not** through the
`COGNITO_POOL_ID` / `COGNITO_PROVIDER_NAME` environment variables that appear in
`config/environments/*.rb`. Those assign to a config entry nothing reads; they
are vestigial and setting them has no effect.

## The first deploy

Four things have to be true before this works, and three of them are easy to
forget:

```sh
ls config/master.key                 # bin/rails credentials:edit made one — see "First: make your own credentials"
ls config/deploy.yml                 # you copied .hostname or .ip and filled in the two placeholders
docker info >/dev/null && echo ok    # Docker is running *here*; the image and the registry are both local
ssh YOUR-USER@YOUR-HOST docker ps    # key-based SSH, and that user is in the docker group
```

Then:

```sh
bin/kamal setup
```

That starts the local registry, builds and pushes the image to it, installs
Docker's prerequisites on the server if needed, boots the container, and runs
`db:prepare`. The first run is slow — it is a full image build.

Subsequent deploys are:

```sh
bin/kamal deploy
```

Useful afterwards:

```sh
bin/kamal app logs -f          # tail the app
bin/kamal app exec -i bash     # a shell in the running container
bin/kamal app exec -i "bin/rails console"
bin/kamal rollback             # previous image
```

A new instance has no users. Create the first one by signing up, then activate
it from a console — [Configuration](CONFIGURATION.md) has the activation flow
and the one-liner for it — and give it `admin`. From there,
[Getting started](GETTING_STARTED.md) walks through a first project, task and
kit.

`aws/deploying_to_aws.md` has the same steps written out against a specific
instance, with the values filled in rather than described. If you are following
that guide you do not need this section.

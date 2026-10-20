# Deploying with Kamal

The Quick start in the repository's `README.md` runs the app locally under
Docker Compose. This is about putting it on a server.

Deployment uses [Kamal](https://kamal-deploy.org), which can target **any
machine you can reach over SSH and run Docker on** — a cloud VM, a rented
server, a box under a desk. It builds the image, pushes it to a registry, and
runs it on the host over SSH. There is no Kubernetes, no agent on the server,
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
| **Outbound HTTPS** | to pull the image from your registry, and to reach Let's Encrypt if you use `proxy.ssl`. |
| **A disk that survives redeploys** | the database is SQLite in `/rails/storage`, mounted from a Docker volume. See [Persistence](#persistence). |
| **Architecture matching your build** | an image built on an Apple Silicon Mac will not run on an x86_64 server unless you build for it. See [Architecture](#architecture). |

Memory and CPU depend on your transcription load. The app itself is a single
Puma process plus Solid Queue in-process; the audio work happens in the
annotator's browser, not on the server.

`aws/deploying_to_aws.md` produces a machine that meets all of this: its
cloud-init config installs Docker and adds the login user to the `docker` group,
and its security groups open 80 and 443 while restricting SSH.

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

Both are set up for Docker Hub, for an `ubuntu` login user, and for HTTPS. They
differ only in `servers.web`, in the `proxy` block, and — for the IP version —
in two certificate secrets. What is left to do is replace the placeholders:

| Placeholder | Replace with |
| --- | --- |
| `your-user` | your registry account, in **both** `image:` and `registry.username:`. On Docker Hub, `image:` has to be `your-user/webtrans26`; a bare `webtrans26` only works on a registry that doesn't namespace by account. |
| `your-hostname` / `your-ip` | the machine's DNS name or IP address, in **both** `servers.web` and `proxy.host`. |
| `ssh.user: ubuntu` | your login user, if it isn't `ubuntu`. It has to be in the `docker` group — Kamal runs `docker` over SSH and will not use `sudo`. |

Then export your registry password in the shell you deploy from:

```sh
export KAMAL_REGISTRY_PASSWORD=...
```

`.kamal/secrets` already passes it through — the line is live, so nothing to
edit there. On Docker Hub, create an access token under **Account settings →
Personal access tokens** and use that rather than your password.

If you forget to export it, the secret resolves to an empty string and the
failure comes later, as a registry login error rather than a configuration one.

The IP version needs two more secrets, which [SSL](#ssl) covers.

### What the keys mean

Both files are Kamal's own template with this app's values filled in, so the
comments in them are the first reference. The ones that matter:

| Key | |
| --- | --- |
| `servers.web` | the host(s) to deploy to, as IP or hostname. |
| `image` | `your-user/webtrans26`. Docker Hub and most other registries namespace every repository by account, so a bare `webtrans26` only works on one that doesn't. |
| `registry.server` | **commented out**, which is how Kamal selects Docker Hub. Set it for anything else: `ghcr.io`, `registry.digitalocean.com`, your own host. (`hub.docker.com` is the website, not a registry endpoint.) |
| `registry.username`, `registry.password` | active, pointing at `KAMAL_REGISTRY_PASSWORD`, which `.kamal/secrets` reads from your shell. Use an access token, not a password. |
| `proxy` | configured for HTTPS — differently in the two files. See [SSL](#ssl). |
| `ssh.user` | `ubuntu`. It has to be a user in the `docker` group: Kamal runs `docker` over SSH and will not use `sudo`. |
| `volumes` | the SQLite database. See [Persistence](#persistence). |
| `env.clear` | the app's own settings, listed as comments. See [Application configuration](#application-configuration). |

One trap, if you start commenting things out: `registry:` must not end up empty.
Removing `server:` *and* `username`/`password` leaves the key with nothing under
it, and Kamal stops with `registry: should be a hash` — which does not hint at
the cause. Both files ship with `server:` commented and the other two active,
which is a valid combination.

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

`.kamal/secrets` ships with two live lines, both reading from the machine you
deploy *from*:

```
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
RAILS_MASTER_KEY=$(cat config/master.key)
```

The master key is how the container gets to decrypt
`config/credentials.yml.enc`. `config/master.key` is gitignored and must exist
locally — Kamal reads it and injects it as an environment variable; it never
goes into the image. The registry password comes from your shell, so
`export KAMAL_REGISTRY_PASSWORD=...` before deploying.

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

```sh
bin/kamal setup
```

That installs Docker's prerequisites if needed, pushes the image, boots the
container, and runs `db:prepare`. Subsequent deploys are:

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

# Configuration

This app deliberately avoids hard-coded infra. The defaults are chosen so a fresh clone runs without any outside dependencies (no SMTP server, no specific GitHub remote, no cloud credentials beyond what's already in Rails credentials). Most of that is controlled by a small number of env vars and `Rails.application.config.x.*` entries.

## Environment variables

| Variable | Default | What it does |
| --- | --- | --- |
| `MAIL_ENABLED` | unset (treated as `false`) | When `"true"`, signups send an activation email. Otherwise, signups land on `/awaiting_activation`. |
| `RAILS_MASTER_KEY` | from `config/master.key` | Decrypts `config/credentials.yml.enc`. The Kamal secrets file reads this from `config/master.key`. |
| `APP_HOST` | `example.com` | The hostname used in links in activation and password-reset email. Irrelevant until you turn email on, and meaningless without a hostname. |
| `SSL` | unset (treated as **`true`**) | Sets `assume_ssl` and `force_ssl` in production: HTTP redirects to HTTPS and cookies are marked secure. **On by default** — every deployment in [Deployment](DEPLOYMENT.md) serves HTTPS, either with a Let's Encrypt certificate if the machine has a hostname or a self-signed one for its IP if not. Set `SSL=false` only for a deliberate plain-HTTP deployment, and note that passwords then cross the network in the clear. |
| `AWS_REGION` | unset | The region for Cognito and S3. **Required for `s3://` kit sources and the Browse tab** — the AWS SDK refuses to build a client without it, so until it is set those features report themselves unavailable. |
| `HLT_ENDPOINT` | unset | The speech-activity-detection / ASR service. Unset, SAD and ASR are unavailable and say so. |
| `PROMISE_BUCKET` | unset | The S3 bucket that service exchanges work through. Needed together with `HLT_ENDPOINT`; one without the other is not enough. |
| `TRANSCRIPTION_REPL` | unset | Set to `1` by `bin/repl` and the scripted harnesses. Suppresses the training-guide popup so a scripted run isn't blocked by it. |

Every one of these is optional. A deployment that sets none of them runs, signs
people in, and transcribes audio from plain `http(s)` URLs; what it cannot do is
send email, read `s3://` sources, or run speech services — and in each case the
app says so rather than failing obscurely.

The two `config/deploy.yml.*` files list the deployment-relevant ones as
comments under `env.clear`, which is where to uncomment them — in the copy you
make of one of them. See [Deployment](DEPLOYMENT.md).

### Cognito is not configured by environment

`config/environments/production.rb`, `development.rb` and `repl.rb` each assign
`ENV['COGNITO_POOL_ID']` and `ENV['COGNITO_PROVIDER_NAME']` to
`config.cognito_identity_pool_id` / `config.cognito_provider_name`. **Nothing
reads those config entries.** The code uses
`Rails.application.credentials.cognito_pool_id` and `cognito_provider_name`, so
Cognito is configured with `bin/rails credentials:edit`. Those environment
variables are vestigial and setting them has no effect.

## Activation flow

Three branches in `UsersController#create`:

1. **Rails.env.development?** — auto-activate the new user and sign them in. Fast iteration; no email required.
2. **Otherwise + `MAIL_ENABLED=true`** — call `@user.send_activation_email` (uses ActionMailer) and flash "check your email".
3. **Otherwise + mail disabled (the default)** — redirect to `/awaiting_activation` with a friendly "an admin needs to activate you" page. No mailer crash.

To activate someone by hand from a Rails console:

```ruby
User.find_by(email_address: "x@y.com").activate
```

## Password reset flow

Two branches in `PasswordsController#create`:

1. **`MAIL_ENABLED=true`** — the usual self-service flow. We send a signed-token reset link to the address; the recipient clicks it and sets a new password.
2. **Mail disabled (the default)** — the user picks a new password right on the request form. On submit, we set the password on the matching account, deactivate it (`User#deactivate`, which also destroys all live sessions), and redirect with a notice telling them to ask an administrator to reactivate. After the admin verifies and flips `activated`, the user signs in with the password they just chose.

A few notes on branch 2:

- **Enumeration safety.** Password validation (min length, confirmation match) runs *before* the email lookup, so the response shape doesn't depend on whether the address matched. An unknown email gets the same "if the address matched…" notice as a successful change.
- **Lockout risk.** The endpoint can be used as a "lock this account" lever by anyone who knows an address — they'd submit a random password, the real user gets deactivated, and only the admin can reverse it. Admins should be ready to verify and reactivate quickly. Rate-limiting via `Rack::Attack` would make abuse harder; not configured here yet.
- **Reactivation.** The admin reactivates with `User.find_by(email_address: "x@y.com").activate` in a console (or via a future admin UI).

## Where the config lives

- `config/application.rb` — sets `config.x.mail_enabled`, `config.x.transcription_repl`, `config.x.hlt_endpoint` and `config.x.promise_bucket` from env vars
- `config/credentials.yml.enc` — encrypted, holds AWS / recaptcha / cognito keys (decrypt with `bin/rails credentials:edit`)
- `config/deploy.yml` — Kamal deploy targets (servers, image, registry, SSL) and the `env.clear` list above. **Not in the repository**: copy `config/deploy.yml.hostname` or `config/deploy.yml.ip` to create it. See [Deployment](DEPLOYMENT.md).
- `.kamal/secrets` — passes `RAILS_MASTER_KEY` (and certs, if you add them) to Kamal at deploy time

If you add a new configurable behaviour, put the env-var-with-default line in `config/application.rb` next to the others, and add a row to the table above so it's discoverable.

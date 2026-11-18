# Setting up Cognito identity pools

This is how the AWS side of `s3://` kit sources and the Browse tab gets built.
It creates three things: an identity pool, a role the annotator's browser ends
up holding, and a role the application itself runs as. The app reads none of it
directly — see [How this connects to the app](#how-this-connects-to-the-app) at
the end for the two values you take away from this and where they go.

All six JSON files in this directory are templates: every `$name` in them is a
placeholder you replace. Nothing here carries an account id or a bucket name.

## Create the identity pool

Edit `create-identity-pool.json`:

* `IdentityPoolName` — a name for the identity pool
* `DeveloperProviderName` — a name for the developer provider; the domain of
  the public site is a reasonable choice (e.g. `transcribe.example.edu`)

Create the identity pool:

```
aws cognito-identity create-identity-pool --cli-input-json file://create-identity-pool.json
```

The command outputs a JSON document containing, among other things, the
`IdentityPoolId` for the pool just created. We'll refer to that value as
`$identity_pool_id`.

## Create the application user role

This is the role the **browser** holds. It is what bounds what an annotator can
reach in S3.

Edit `create-app-user-role.json` to set `RoleName` to an appropriate name for
your deployment. We'll refer to that value as `$app_user_role_name`.

Edit `assume-role-policy-document.json` to set the value of
`cognito-identity.amazonaws.com:aud` to `$identity_pool_id`. This is what makes
the role assumable *only* by identities from your pool.

Create the application user role:

```
aws iam create-role --cli-input-json file://create-app-user-role.json --assume-role-policy-document file://assume-role-policy-document.json
```

Now edit `app-user-role-permissions.json` and replace `$bucket_arn` with the
ARN of the S3 bucket you'll use for this application — the whole file has three
occurrences, two with `/*` and one without, and the one without is the
`ListBucket` resource, which is bucket-level and must not carry a suffix.
Finally, grant the permissions to the role:

```
aws iam put-role-policy --role-name $app_user_role_name --policy-document file://app-user-role-permissions.json --policy-name app-user-role-permissions
```

**Every signed-in user gets this one role**, so this policy is the same for
everyone who can log in. Scoping S3 access per user or per project is a
different mechanism and this is not it.

## Create an EC2 instance role

This is the role the **application** runs as, and all it needs is permission to
mint the tokens the browser then exchanges.

Edit `create-ec2-instance-role.json`, updating `RoleName` to a valid name for
the role. We'll call that value `$instance_role_name`. Create the role:

```
aws iam create-role --cli-input-json file://create-ec2-instance-role.json
```

Then edit `instance-role-permissions.json` and replace `$identity_pool_arn`
with the identity pool ARN. You construct this string yourself, in this format:

```
arn:aws:cognito-identity:$AWS_REGION:$AWS_ACCOUNT_ID:identitypool/$identity_pool_id
```

* `$AWS_REGION` — the AWS region containing the identity pool
* `$AWS_ACCOUNT_ID` — the 12 digit id of your AWS account; `aws sts get-caller-identity` reports it
* `$identity_pool_id` — the id of the identity pool you created above

Now grant the permissions:

```
aws iam put-role-policy --role-name $instance_role_name --policy-document file://instance-role-permissions.json --policy-name instance-role-permissions
```

Attach the role to the instance the app runs on. If you built the VM from
[create_launch_template.json](create_launch_template.json), add an
`IamInstanceProfile` to it; otherwise attach the instance profile to the
running instance.

## How this connects to the app

Two values come out of the above, and they go into Rails credentials, **not**
into `deploy.yml`:

```
bin/rails credentials:edit
```

| credential key | value |
| --- | --- |
| `cognito_pool_id` | `$identity_pool_id` |
| `cognito_provider_name` | the `DeveloperProviderName` you chose |

A third value, the region, *is* an environment variable: set `AWS_REGION` under
`env.clear` in `config/deploy.yml`. All three are required together —
`docs/CONFIGURATION.md` describes what happens when they are absent (the
features report themselves unavailable rather than failing).

The app itself needs AWS credentials for the instance role, and it gets them
from the SDK's default credential chain — the instance profile on EC2, or
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` anywhere else. Nothing in this
repository sets those, which is why the role has to be attached to the
instance.

The exchange, so the two roles aren't confusable:

1. The browser asks the app for a token (`POST /token`).
2. The app calls `GetOpenIdTokenForDeveloperIdentity` with the signed-in user's
   id as the login — this is the **instance role's** one permission.
3. The browser exchanges that token for S3 credentials itself
   (`fromCognitoIdentity` → `GetCredentialsForIdentity`), and what it receives
   is the **app user role**.

So the instance role never touches S3, and the app never holds the credentials
the browser uses.

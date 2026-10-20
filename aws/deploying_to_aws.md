# Deploying to AWS

This guide describes how to set up an AWS EC2 instance to support
Kamal-based deployment of Rails applications.

## Select a VPC

VMs and other resources in EC2 are created in a "virtual private cloud" (VPC),
providing a controlled network that's isolated from from other AWS users and
the wider internet. AWS creates a default VPC for an account in each region,
which we'll use in this example. To retrieve the ID of your default VPC, run:

```
aws ec2 describe-vpcs  --query 'Vpcs[?(IsDefault==`true`)].VpcId'
```

In this example, I've used the placeholder value `$vpc_id` to represent the ID
taken from output of the command above - the actual ID will be will look
something like `vpc-a1b2c3d4`.

## Set Up Security Groups

Security groups in EC2 provide simple, rule-based control over the network
accessibility of resources in your VPC.

Security group rules come in two types - ingress and egress. Ingress rules
specify the set of IP addresses that are allowed to make connections to the VM,
egress rules specify the addresses to which the VM can make connections[^1].
We'll make two security groups, one for ingress and the other for egress[^2].

### Create the security groups

First, edit `create_ingress_sg.json`, setting the value `VpcId` to your
`$vpc_id`. Now, create the security group with the following command:

```
aws ec2 create-security-group --cli-input-json file://create_ingress_sg.json 
```

If successful, you'll see a JSON document containing the GroupId the new
security group, which I'll refer to in this example as `$ingress_sg_id` - the
actual ID will look something like `sg-0a1b2c3d4e5f67890`

Now edit `create_egress_sg.json`, update `VpcId`, and create the egress security
group:

```
aws ec2 create-security-group --cli-input-json file://create_egress_sg.json 
```

Like with the ingress group, a successful result will have the GroupId of the
newly created security group, which I'll refer to as `$egress_sg_id`.

### Authorize the security groups

Now, establish the network rules for the security groups. First, edit `authorize_ingress_sg.json`,
updating the value of the `GroupId` to `$ingress_sg_id`. The first two rules
allow traffic from any IPv4 or IPv6 address, to ports 80 and 443,
respectively. The last rule permits ssh from a limited set of IP addresses.
You **must** update these values ones that are appropriate for your scenario,
e.g., to your organization's public network range or your home office.

To apply the rules to the ingress security group, run:

```
aws ec2 authorize-security-group-ingress --cli-input-json file://authorize_ingress_sg.json
```

If successful, the cli will output a JSON response showing the group rules.

Now, update `authorize_egress_sg.json`, setting the value of `GroupId` to
`$egress_sg_id`, then run:

```
aws ec2 authorize-security-group-egress --cli-input-json file://authorize_egress_sg.json
```

Upon success, the cli will output a JSON response showing the group rules.

**TODO** _explain the purpose of the egress rules in the sample_

## Create a EC2 launch template

EC2 templates provide a standard VM configuration that can be used to deploy one
or more instances based on it.

### Add an SSH key pair

Secure SHell (ssh) will be used for managing the instance and deploying the
application. Establishing an SSH key in EC2 allows AWS to start VM instances
with the specified key installed on the instance, allowing remote login.

If you don't already have a key pair set up in EC2, you can import one
directly via the CLI. Import **your own** public key — typically
`~/.ssh/id_ed25519.pub` — under a name of your choosing:

```
aws ec2 import-key-pair --key-name my_ssh_key --public-key-material fileb://$HOME/.ssh/id_ed25519.pub
```

[id-example-key.pub](id-example-key.pub) is included only to show the expected
format. Don't import it: you don't hold the matching private key, so the VM it
produced would be one you couldn't log in to.

It's also possible to have AWS generate an ssh key for you[^3]:

```
aws --output text ec2 create-key-pair --key-name another_example_key  --query 'KeyMaterial' > another_example_key.pem
```

The resulting file contains a PEM-formatted private key that can be used to
connect to the VM.

Finally, the name given to a key pair must be unique within an AWS account.
Importing/creating a key with an existing name will produce an error. For this
example, I'll refer to the SSH key pair name as `$key_pair_name`.

### Edit the JSON template

Edit `create_launch_template.json`, setting the values of `$key_pair_name`,
`$ingress_sg_id`, `$egress_sg_id`, and `$ami_id` to their correct values.

`$ami_id` is the machine image the VM boots from. AMI IDs are specific to a
region, and new ones are published as the distribution is patched, so look up a
current one rather than reusing an ID from a guide. For the latest Ubuntu 24.04
LTS image on x86_64:

```
aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' --output text
```

The template deliberately doesn't pin a root-volume snapshot — the AMI supplies
its own. It does set the volume to 15 GB of encrypted `gp3`, which you can
change.

### What the VM does on first boot

The template's `UserData` value is not meant to be read as it stands: it is
[cloud_config.yml](cloud_config.yml), base64-encoded. The two are byte for byte
the same file. **Read and edit the YAML and re-encode it into the JSON** — don't
hand-edit the base64.

It is a [cloud-init](https://cloudinit.readthedocs.io/) config that updates the
packages, installs Docker from Docker's own apt repository, adds the login user
to the `docker` group, and reboots. That is all Kamal needs on the host.

To put an edited `cloud_config.yml` back into the template:

```
python3 -c "import base64,json,pathlib; t=json.load(open('create_launch_template.json')); t['LaunchTemplateData']['UserData']=base64.b64encode(pathlib.Path('cloud_config.yml').read_bytes()).decode(); pathlib.Path('create_launch_template.json').write_text(json.dumps(t,indent=2)+chr(10))"
```

One thing to watch if you chose a different `$ami_id`: the last `runcmd` line is
`usermod -aG docker ubuntu`, and `ubuntu` is the default login user on
Canonical's Ubuntu images. On Amazon Linux it is `ec2-user`, on Debian `admin`.
Change that line and `ssh.user` in your deploy file (step 2 below) together, or
Kamal will connect as a user that cannot reach Docker.

```
aws ec2 create-launch-template --cli-input-json file://create_launch_template.json
```

The output from this command will contain a `LaunchTemplateId` value, to which
I'll refer by the `$launch_template_id`.

### Launch template

Now, you can launch an instance with the new template:

```
aws ec2 run-instances --launch-template LaunchTemplateId=$launch_template_id,Version=1 --query 'Instances[*].InstanceId'
```

NB: don't forget to replace `$launch_template_id` in the command above with the
actual `LaunchTemplateId`. The output from this command should be the instance ID,
which I'll refer to as `$instance_id`

Once VM is launched, it takes a bit for it to come online and won't have a
publicly accessible IP address on startup. To get the IP after launching the VM,
run:

```
aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[*].Instances[*].PublicIpAddress' --output text
```

You can connect to the instance via ssh thus:

```
ssh ubuntu@IP-ADDRESS
```

If you opted to create a `.pem` file SSH key, you should change the permissions
on `$key_fil.pem` so it's only readable by you:

```
chmod 0400  $key_file.pem 
```

When connecting, you'll need to specify the path to the `.pem` file:

```
ssh -i $key_file.pem ubuntu@IP-ADDRESS
```

## Deploy the app to your new VM

At this point you have a VM with Docker installed, a public IP, and SSH access
as `ubuntu`. That is everything the app needs from a server. What follows sets
the deployment values and deploys.

Each step says what to set and why in one line. For the longer explanation of
any of it, see `docs/DEPLOYMENT.md`.

### 1. Decide how you will reach the app

**These instructions assume HTTPS.** Annotators sign in with a password and
their recordings are usually not public, so the app defaults to redirecting
HTTP to HTTPS and marking cookies secure.

One decision, and it picks which file you copy in the next step:

| | | Deploy file |
| --- | --- | --- |
| **The instance has a DNS hostname** that already points at it | Kamal gets a certificate from Let's Encrypt and renews it | `config/deploy.yml.hostname` |
| **You will reach it by IP address** | you generate a self-signed certificate for the IP, and accept a browser warning once | `config/deploy.yml.ip` |

A hostname is nicer — no warning, automatic renewal — but the IP route is a
real deployment, and the security groups you created already allow 443 either
way. If you only have the public IP from the previous section, that is the IP
route.

### 2. Copy that file to `config/deploy.yml`

There is no `config/deploy.yml` in the repository — one of these two becomes it:

```sh
cp config/deploy.yml.hostname config/deploy.yml     # or .ip
```

Until you do, `kamal` stops with `Configuration file not found`.

Both files are already set up for this walkthrough's instance: Docker Hub as
the registry, `ubuntu` as the login user, HTTPS on. Replace the placeholders:

| Placeholder | Replace with |
| --- | --- |
| `your-ip` or `your-hostname` | the instance's public IP (or its DNS name), in **both** `servers.web` and `proxy.host`. |
| `your-user` | your Docker Hub account, in **both** `image:` and `registry.username:`. `image:` has to be `your-user/webtrans26` — Docker Hub namespaces every repository by account, so a bare `webtrans26` will not push. |
| `ssh.user: ubuntu` | leave it. The Ubuntu image this template launches logs in as `ubuntu`, and the cloud-init config added that user to the `docker` group. Change it only if you changed the image. |

If your SSH key is a `.pem` file rather than one already loaded in your agent,
tell Kamal where it is:

```yaml
ssh:
  user: ubuntu
  keys: [ "/path/to/your/key_file.pem" ]
```

With a hostname, also set it for email links, under `env.clear`:

```yaml
env:
  clear:
    APP_HOST: your-host.example.edu
```

On the IP route there is no point setting `APP_HOST` — there is nothing useful
to put in a link.

### 3. Set the registry password

`.kamal/secrets` already passes it through, so there is nothing to edit — just
export it in the shell you deploy from:

```sh
export KAMAL_REGISTRY_PASSWORD=...
```

On Docker Hub, create an access token under **Account settings → Personal
access tokens** and use that rather than your password. Forget this and the
deploy fails at the registry login, not at the configuration check.

For a registry other than Docker Hub, uncomment `server:` in `config/deploy.yml`
and set it — `ghcr.io`, `registry.digitalocean.com`,
`your-registry.example.com:5000`. The template leaves it commented because an
unset `server:` is how Kamal selects Docker Hub. (`hub.docker.com` is the
website, not a registry endpoint; don't put it there.)

### 4. Without a hostname: generate the certificate

**Skip this if you used `config/deploy.yml.hostname`** — Kamal requests your
certificate on the first deploy. It will fail if the name does not yet resolve
to the instance, because Let's Encrypt connects back to port 443 to prove you
control it.

On the IP route, generate a certificate for the instance's public IP. The
`subjectAltName` line is the part that matters — browsers reject a certificate
that names the address only in `CN`:

```sh
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout config/privkey.pem -out config/fullchain.pem \
  -subj "/CN=YOUR-IP" \
  -addext "subjectAltName=IP:YOUR-IP"
```

Substitute the IP in both places, then check it took:

```sh
openssl x509 -in config/fullchain.pem -noout -text | grep -A1 "Subject Alternative Name"
```

It should print `IP Address:YOUR-IP`.

The private key stays out of git: `/config/*.pem` is already in `.gitignore`.
Confirm it, because a key committed once is compromised even if a later commit
removes it:

```sh
git check-ignore -v config/privkey.pem
```

Then add two lines to `.kamal/secrets`, which is where Kamal reads the file
contents at deploy time:

```
APP_CERT_PEM=$(cat config/fullchain.pem)
APP_PRIVATE_KEY_PEM=$(cat config/privkey.pem)
```

`config/deploy.yml.ip` already names those two secrets in both places they are
needed — the `proxy.ssl` block and `env.secret` — so there is nothing else to
edit.

The first time you open the app the browser will warn that the certificate is
not from a recognised authority. Accept it. That warning is about proving *who*
the server is, which a self-signed certificate cannot do; the connection is
encrypted regardless. And `-days 365` means you regenerate and redeploy in a
year — nothing reminds you.

### 5. Deploy

`.kamal/secrets` already reads `RAILS_MASTER_KEY` from `config/master.key`, so
there is nothing to do for that as long as the file exists on the machine you
are deploying *from*.

```
bin/kamal setup
```

This pushes the image, boots the container, and creates the database. Later
deployments are `bin/kamal deploy`.

If it fails on the image architecture — `exec format error` — you are building
on an Apple Silicon Mac for an x86_64 instance. Add:

```yaml
builder:
  arch: amd64
```

### 6. First sign-in

Open `https://your-host` or `https://YOUR-IP`, whichever you configured —
accepting the certificate warning the first time, on the IP route. A new
instance has no users: sign up, then activate that first account from a console
and make it an admin.

```
bin/kamal app exec -i "bin/rails console"
```

```ruby
u = User.find_by(email_address: "you@example.edu")
u.activate            # sets activated, activated_at and confirmed_at
u.update!(admin: true)
```

Useful afterwards:

```
bin/kamal app logs -f          # tail the app
bin/kamal app exec -i bash     # a shell in the container
bin/kamal rollback             # previous image
```

### What this leaves unconfigured

The app runs and transcribes audio from plain `http(s)` URLs with nothing
further set. Three features are off until you configure them, and each says so
in the interface rather than failing:

| | |
| --- | --- |
| Email | set `MAIL_ENABLED: true` under `env.clear` and configure a mail server. Until then new signups wait for an admin to activate them. |
| `s3://` kit sources, and the Browse tab | need Cognito in Rails credentials (`bin/rails credentials:edit`, keys `cognito_pool_id` and `cognito_provider_name`) **and** `AWS_REGION` under `env.clear`. |
| Speech activity detection and ASR | need `HLT_ENDPOINT` and `PROMISE_BUCKET` under `env.clear`. Both, not one. |

`docs/CONFIGURATION.md` has the full list.

### A note on the database

The database is SQLite on a Docker volume (`webtrans26_storage`), so it lives on
this one instance and survives redeploys but not the instance. Back it up:

```
ssh ubuntu@IP-ADDRESS 'docker run --rm -v webtrans26_storage:/v -v /tmp:/out alpine tar czf /out/storage.tgz -C /v .'
scp ubuntu@IP-ADDRESS:/tmp/storage.tgz .
```

## Notes

### Adding a server entry to your SSH configuration

If you'd like to not have to remember to specify the key file path and username when
connecting to your VM, you can add an entry in your SSH configuration file like this:

```
Host myvm.example.edu
  User ubuntu
  IdentityFile /path/to/your/ssh/key_file.pem
```

Your SSH configuration file can be found under your home directory, in
`$HOME/.ssh/config`. Note that you might need to create the `.ssh` directory and
`config` files if they don't exist; if so, make sure their permissions are set
properly:

```
chmod 0700 $HOME/.ssh
chmod 0600 $HOME/.ssh/config
```

[^1]: It's worth pointing out that these rules only need to be given "in one direction," i.e., if you've created an ingress rule from `0.0.0.0/0` to port 443 on the VM, that's all that's needed to allow the VM to respond to HTTPS connections from any IP address; you do **not** need to add a corresponding egress rule.
[^2]: The division into ingress/egress security groups is purely organizational; for example, one could also make a single group with for rules or separate groups by traffic type (e.g., one for HTTP/S, another for SSH).
[^3]: Avoid this option if possible. For information on how to generate your own SSH keys, please see [GitHub's documentation](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent).

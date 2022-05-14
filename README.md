# linkding on fly

> 🔖 Run the self-hosted bookmark service [linkding](https://github.com/sissbruecker/linkding) on [fly.io](https://fly.io/). Automatically backup the bookmark database to [B2](https://www.backblaze.com/b2/cloud-storage.html) with [litestream](https://litestream.io/).

### Pricing

Assuming one 256MB VM and a free 3GB fly volume, this setup fits within Fly's free tier. [^0] Backups with B2 are free as well. [^1]

[^0]: otherwise the VM is ~$2 per month. $0.15/GB per month for the persistent volume.  
[^1]: the first 10GB are free, then $0.005 per GB.

### Install fly

Follow [the instructions](https://fly.io/docs/getting-started/installing-flyctl/) to install fly's command-line `flyctl`.

Then, [log into flyctl](https://fly.io/docs/getting-started/log-in-to-fly/).

```sh
flyctl auth login
```

### Launch fly application

Launch the fly application. Choose a region close to you. When asked, **do not** setup Postgres and **do not** deploy yet.

```sh
flyctl launch
```

This command creates a `fly.toml` file. Open it and add an `env` section.

```toml
[env]
  # linkding's internal port, should be 8080 on fly.
  LD_SERVER_PORT="8080"
  # Path to linkding's sqlite database.
  DB_PATH="/etc/linkding/data/DB.sqlite3"
  # B2 replica path.
  LITESTREAM_REPLICA_PATH="linkding_replica.sqlite3"
  # B2 endpoint.
  LITESTREAM_REPLICA_ENDPOINT="<filled_later>"
  # B2 bucket name.
  LITESTREAM_REPLICA_BUCKET="<filled_later>"
```

### Add a persistent volume

Create a [persistent volume](https://fly.io/docs/reference/volumes/). The first `3GB` volume is free on fly. 3GB should be sufficient for most installs.

```sh
fly volumes create linkding_data --region <your_region> --size <size_in_gb>
```

Attach the persistent volume to the container by adding a `mounts` section to `fly.toml`.

```toml
[mounts]
source="linkding_data"
destination="/etc/linkding/data"
```

### Configure litestream backups

Log into B2 and [create a bucket](https://litestream.io/guides/backblaze/#create-a-bucket). Instead of adjusting the litestream config directly, we will add configuration to `fly.toml`. In the `env` section, set `LITESTREAM_REPLICA_ENDPOINT` and `LITESTREAM_REPLICA_BUCKET` to your newly created bucket's endpoint and name.

Then, create [an access key](https://litestream.io/guides/backblaze/#create-a-user) for this bucket. Add the key to fly's secret store.

```sh
flyctl secrets set LITESTREAM_ACCESS_KEY_ID="<keyId>" LITESTREAM_SECRET_ACCESS_KEY="<applicationKey>"
```

> Note: If you want to use another storage provider, check litestream's ["Replica Guides"](https://litestream.io/guides/) and adjust the config as needed.

### Deploy to fly

Deploy the application to fly.

```sh
flyctl deploy
```

If all is well, you can now access linkding by running `flyctl open`. You should see its login page.

### Create a linkding root user

If you have never used fly's SSH console before, begin by setting up fly's ssh-agent.

```sh
fly ssh establish

# use agent if possible, otherwise follow on-screen instructions.
fly ssh issue --agent
```

Then, run `fly ssh console` to get an interactive shell in your running container. You can now create a root user by running the `createsuperuser` command and entering a password.

```sh
cd /etc/linkding
python manage.py createsuperuser --username=<your_username> --email=<your_email>
exit
```

That's it! If you wish, you can now [configure a custom domain for your install](https://fly.io/docs/app-guides/custom-domains-with-fly/).

### Verify the installation

 - you should now be able to log into your linkding instance.
 - in your B2 bucket, there should be an initial replica of your database.
 - your user data should survive a restart.

### Verify backups / scale persistent volume

Litestream continuously backs up your database by persisting its WAL to B2 (once per second).

There are two ways to verify these backups:
 1. run the docker image locally or on a second VM. Verify the DB restores correctly.
 2. swap the fly volume for a new one and verify the DB restores correctly.

We will focus on (2) as it simulates an actual data loss scenario. This procedure can also be used to scale your volume to a different size.

Start by making a manual backup of your data.
 1. ssh into the VM and copy the DB to a remote. If only you are using your instance, you can also export bookmarks as HTML.
 2. make a snapshot of the B2 bucket.

Now list all fly volumes and note the id of the `linkding_data` volume. Then, delete the volume.

```sh
flyctl volumes list
flyctl volumes delete <id>
```

This will result in a **dead** VM after a few seconds. Now create the volume `linkding_data` again. (see above) Your application should automatically attempt to restart. If not, restart it manually.

When the application starts, you should see the successful restore in the logs.

```
[info] No database found, attempt to restore from a replica.
[info] Finished restoring the database.
[info] Starting litestream & linkding service.
```

### Troubleshooting

#### litestream is logging 403 errors

Check that your B2 secrets and environment variables are correct.

#### fly ssh does not connect

Check the output of `flyctl doctor`, every line should be marked as **PASSED**. If `Pinging WireGuard` fails, try `flyctl wireguard reset` and `flyctl agent restart`.

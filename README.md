# linkding on fly

> 🔖 Run the self-hosted bookmark service [linkding](https://github.com/sissbruecker/linkding) on [fly.io](https://fly.io/). Automatically backup the bookmark database to [B2](https://www.backblaze.com/b2/cloud-storage.html) with [litestream](https://litestream.io/).

### Install Fly

Follow [the instructions](https://fly.io/docs/getting-started/installing-flyctl/) to install fly's command-line `flyctl`.

Then, [log into flyctl](https://fly.io/docs/getting-started/log-in-to-fly/).

```sh
flyctl auth login
```

### Launch fly application

Launch the fly application. Choose a region close to you. When asked, **do not** setup postgres and **do not** deploy yet.

```sh
flyctl launch
```

This command creates a `fly.toml` file. Open it and add an `env` section.

```toml
[env]
  # linkding's internal port, should be 8080 on fly.
  LD_SERVER_PORT="8080"
  # Path to linkding's sqlite database.
  DB_PATH="/etc/linkding/data/db.sqlite3"
  # B2 replica path.
  LITESTREAM_REPLICA_PATH="linkding_replica.sqlite3"
  # B2 endpoint.
  LITESTREAM_REPLICA_ENDPOINT="<filled_later>"
  # B2 bucket name.
  LITESTREAM_REPLICA_BUCKET="<filled_later>"
```

### Add a persistent volume

Create a [persistent volume](https://fly.io/docs/reference/volumes/). The first `3GB` volume is free on fly. 3GB should be sufficient for most installs, but use your own judgement.

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

> Note: If you want to use another storage provider, check litestream's ["Replica Guides"](https://litestream.io/guides/) and adjust config as needed.

### Deploy to fly

Run `flyctl deploy`. Once successfully deployed, set the application's memory to `512MB` in the fly control panel and wait for the change to be applied.

If all is well, you can now access linkding by running `flyctl open`. You should see its login page.

### Create a linkding root user

If you have never used fly's SSH console before, begin by setting up fly's ssh agent.

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

### Verifying the install

 - you should now be able to log into your linkding instance.
 - in your B2 bucket, there should be an initial replica of your database.
 - your user data should survive a restart.

### Troubleshooting

#### litestream is logging 403 errors

Check that your B2 secrets and envs are correct.

#### fly ssh does not connect

Check the output of `flyctl doctor`, every line should be marked as **PASSED**. If `Pinging WireGuard` fails, try `flyctl wireguard reset` and `flyctl agent restart`.

#### linkding is slow or hangs frequently

Scale your application's memory to at least 512MB.

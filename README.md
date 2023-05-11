# linkding on fly

> 🔖 Run the self-hosted bookmark service [linkding](https://github.com/sissbruecker/linkding) on [fly.io](https://fly.io/). Automatically backup the bookmark database to [Backblaze B2](https://www.backblaze.com/b2/cloud-storage.html) with [litestream](https://litestream.io/).

### Pricing

Assuming one 256MB VM and a 3GB volume, this setup fits within Fly's free tier. [^0] Backups with Backblaze B2 are free as well. [^1]

[^0]: Otherwise the VM is ~$2 per month. $0.15/GB per month for the persistent volume.
[^1]: The first 10GB are free, then $0.005 per GB.

### Prerequisites

- A [fly.io](https://fly.io/) account
- A [Backblaze](https://www.backblaze.com/) account
- `flyctl` CLI installed. [^2]

[^2]: https://fly.io/docs/getting-started/installing-flyctl/

#### Litestream - Create Backblaze B2 Bucket and Application Key

> ℹ️ If you want to use another storage provider, check litestream's ["Replica Guides"](https://litestream.io/guides/#replica-guides) section and adjust the config as needed.

Log into [Backblaze B2](https://secure.backblaze.com/user_signin.htm) and [create a bucket](https://litestream.io/guides/backblaze/#create-a-bucket). Once created, you will see the bucket's name and endpoint. You will use these later to populate `LITESTREAM_REPLICA_BUCKET` and `LITESTREAM_REPLICA_ENDPOINT` in the `.env` file.

Next, create [an application key](https://litestream.io/guides/backblaze/#create-a-user) for the bucket. Once created, you will see the `keyID` and `applicationKey` to add to Fly's secret store:

```sh
flyctl secrets set LITESTREAM_ACCESS_KEY_ID="<keyId>" LITESTREAM_SECRET_ACCESS_KEY="<applicationKey>"
```

### Usage

1. Clone the repository:

    ```sh
    git clone https://github.com/fspoettel/linkding-on-fly.git && cd linkding-on-fly
    ```

2. Login to [`flyctl`](https://fly.io/docs/getting-started/log-in-to-fly/):

    ```sh
    flyctl auth login
    ```

3. Create a [persistent volume](https://fly.io/docs/reference/volumes/) to store the `linkding` application data:

    > ℹ️ Fly's free tier includes `3GB` of storage across your VMs. Since `linkding` is very light on storage, a `1GB` volume will be more than enough for most use cases. It's possible to change volume size later. A how-to can be found in the _"Verify Backups / Scale Persistent Volume"_ section below.

    ```sh
    # List available regions via: flyctl platform regions
    flyctl volumes create linkding_data --region <region code> --size 1
    ```

4. Add the `linkding` superuser credentials to fly's secret store:

    ```sh
    flyctl secrets set LD_SUPERUSER_NAME="<username>" LD_SUPERUSER_PASSWORD="<password>"
    ```

5. Copy the [.env.sample](.env.sample) file to `.env`, fill in the values and source them:

    ```sh
    cp .env.sample .env
    # vim .env
    source .env
    ```

6. Create the [`fly.toml`](https://fly.io/docs/reference/configuration/) from the [template](templates/fly.toml):

    ```sh
    envsubst < templates/fly.toml > fly.toml
    ```

7. Deploy `linkding` to fly:

    > ℹ️ When asked, **do not** setup Postgres or Redis.

    ```sh
    flyctl deploy
    ```

That's it! 🚀 - If all goes well, you can now access `linkding` by running `flyctl open`. You should see the `linkding` login page and be able to log in with the superuser credentials you set in step 4.

If you wish, you can [configure a custom domain for your install](https://fly.io/docs/app-guides/custom-domains-with-fly/).

### Verify the Installation

- You should be able to log into your linkding instance.
- There should be an initial replica of your database in your B2 bucket.
- Your user data should survive a restart of the VM.

### Verify Backups / Scale Persistent Volume

Litestream continuously backs up your database by persisting its [WAL](https://en.wikipedia.org/wiki/Write-ahead_logging) to the Backblaze B2 bucket, once per second.

There are two ways to verify these backups:

1. Run the docker image locally or on a second VM. Verify the DB restores correctly.
2. Swap the fly volume for a new one and verify the DB restores correctly.

We will focus on _2_ as it simulates an actual data loss scenario. This procedure can also be used to scale your volume to a different size.

Start by making a manual backup of your data:

1. Ssh into the VM and copy the DB to a remote. If only you are using your instance, you can also export bookmarks as HTML.
2. Make a snapshot of the B2 bucket in the B2 admin panel.

Now list all fly volumes and note the id of the `linkding_data` volume. Then, delete the volume:

```sh
flyctl volumes list
flyctl volumes delete <id>
```

This will result in a **dead** VM after a few seconds. Create a new `linkding_data` volume. Your application should automatically attempt to restart. If not, restart it manually.

When the application starts, you should see the successful restore in the logs:

```
[info] No database found, attempt to restore from a replica.
[info] Finished restoring the database.
[info] Starting litestream & linkding service.
```

### Troubleshooting

#### Litestream is logging 403 errors

Check that your B2 secrets and environment variables are correct.

#### Fly ssh does not connect

Check the output of `flyctl doctor`, every line should be marked as **PASSED**. If `Pinging WireGuard` fails, try `flyctl wireguard reset` and `flyctl agent restart`.

#### Fly does not pull in the latest version of linkding

Either:

- Specify a version number in the [Dockerfile](https://github.com/fspoettel/linkding-on-fly/blob/master/Dockerfile#L9).
- Run `flyctl deploy` with the `--no-cache` option.

#### Create a linkding superuser manually

If you have never used fly's SSH console before, begin by setting up fly's ssh-agent:

```sh
flyctl ssh establish

# use agent if possible, otherwise follow on-screen instructions.
flyctl ssh issue --agent
```

Then, run `flyctl ssh console` to get an interactive shell in your running container. You can now create a superuser by running the `createsuperuser` command and entering a password.

```sh
cd /etc/linkding
python manage.py createsuperuser --username=<your_username> --email=<your_email>
exit
```

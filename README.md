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

Instructions below assume that you have cloned this repository to your local computer:

```sh
git clone https://github.com/fspoettel/linkding-on-fly.git && cd linkding-on-fly
```

#### Litestream - Create Backblaze B2 Bucket and Application Key

Log into [Backblaze B2](https://secure.backblaze.com/user_signin.htm) and [create a bucket](https://litestream.io/guides/backblaze/#create-a-bucket). Once created, you will see the bucket's name and endpoint. You will use these later to populate `LITESTREAM_REPLICA_BUCKET` and `LITESTREAM_REPLICA_ENDPOINT` in the `fly.toml` configuration.

Next, create [an application key](https://litestream.io/guides/backblaze/#create-a-user) for the bucket. Once created, you will see the `keyID` and `applicationKey`. You will add these later to Fly's secret store, save them for step 3 below.



> **Note**  
> If you want to use another storage provider, check litestream's ["Replica Guides"](https://litestream.io/guides/#replica-guides) section and adjust the config as needed.

### Usage

1. Login to [`flyctl`](https://fly.io/docs/getting-started/log-in-to-fly/):

    ```sh
    flyctl auth login
    ```

2. Generate fly app and create the [`fly.toml`](https://fly.io/docs/reference/configuration/):
    <details>
    <summary>Alternative: Generating from template</summary>

    You can generate the `fly.toml` from the [template](templates/fly.toml) provided in this repository.

    1. Install [`envsubst`](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) if you don't have it already:

        ```sh
        # macOS
        brew install gettext
        ```

    2. Copy the [.env.sample](.env.sample) file to `.env`, fill in the values and source them:

        ```sh
        cp .env.sample .env
        # vim .env
        source .env
        ```

    3. Generate the `fly.toml` from the template:

        ```sh
        envsubst < templates/fly.toml > fly.toml
        ```

    4. Proceed to step 3.
    </details>

    ```sh
    # Generate the initial fly.toml
    # When asked, don't setup Postgres or Redis.
    flyctl launch
    ```

    Next, open the `fly.toml` and add the following `env` and `mounts` sections (populating `LITESTREAM_REPLICA_ENDPOINT` and `LITESTREAM_REPLICA_BUCKET`):

    ```toml
    [env]
      # linkding's internal port, should be 8080 on fly.
      LD_SERVER_PORT="8080"
      # Path to linkding's sqlite database.
      DB_PATH="/etc/linkding/data/db.sqlite3"
      # B2 replica path.
      LITESTREAM_REPLICA_PATH="linkding_replica.sqlite3"
      # B2 endpoint.
      LITESTREAM_REPLICA_ENDPOINT="<Backblaze B2 endpoint>"
      # B2 bucket name.
      LITESTREAM_REPLICA_BUCKET="<Backblaze B2 bucket name>"

    [mounts]
      source="linkding_data"
      destination="/etc/linkding/data"
    ```

3. Add the Backblaze application key to fly's secret store

    ```sh
    flyctl secrets set LITESTREAM_ACCESS_KEY_ID="<keyId>" LITESTREAM_SECRET_ACCESS_KEY="<applicationKey>"
    ```

4. Create a [persistent volume](https://fly.io/docs/reference/volumes/) to store the `linkding` application data:

    ```sh
    # List available regions via: flyctl platform regions
    flyctl volumes create linkding_data --region <region code> --size 1
    ```

    > **Note**  
    > Fly's free tier includes `3GB` of storage across your VMs. Since `linkding` is very light on storage, a `1GB` volume will be more than enough for most use cases. It's possible to change volume size later. A how-to can be found in the _"Verify Backups / Scale Persistent Volume"_ section below.

5. Add the `linkding` superuser credentials to fly's secret store:

    ```sh
    flyctl secrets set LD_SUPERUSER_NAME="<username>" LD_SUPERUSER_PASSWORD="<password>"
    ```

6. Deploy `linkding` to fly:

    ```sh
    flyctl deploy
    ```

    > **Note**  
    > The [Dockerfile](Dockerfile) contains overridable build arguments: `ALPINE_IMAGE_TAG`, `LINKDING_IMAGE_TAG` and `LITESTREAM_VERSION` which can overridden by passing them to `flyctl deploy` like `--build-arg LITESTREAM_VERSION=v0.3.11` etc.

    
That's it! 🚀 - If all goes well, you can now access `linkding` by running `flyctl open`. You should see the `linkding` login page and be able to log in with the superuser credentials you set in step 5.

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

1. SSH into the VM and copy the DB to a remote. If only you are using your instance, you can also export bookmarks as HTML.
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

- Override the [Dockerfile](Dockerfile#L2) build argument `LINKDING_IMAGE_TAG`: `flyctl deploy --build-arg LINKDING_IMAGE_TAG=<tag>`
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

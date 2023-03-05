FROM alpine:3.17 as builder

EXPOSE 8080

# Download the static build of Litestream directly into the path & make it executable.
# This is done in the builder and copied as the chmod doubles the size.
ADD https://github.com/benbjohnson/litestream/releases/download/v0.3.9/litestream-v0.3.9-linux-amd64-static.tar.gz /tmp/litestream.tar.gz
RUN tar -C /usr/local/bin -xzf /tmp/litestream.tar.gz

# Pull in latest linkding docker image.
FROM sissbruecker/linkding:latest

# Copy Litestream from builder.
COPY --from=builder /usr/local/bin/litestream /usr/local/bin/litestream

# Copy Litestream configuration file.
COPY etc/litestream.yml /etc/litestream.yml

# Copy custom uwsgi. This allows to run with 256MB RAM.
COPY uwsgi.ini /etc/linkding/uwsgi.ini

# Copy startup script and make it executable.
COPY scripts/run.sh /scripts/run.sh
RUN chmod +x /scripts/run.sh

# Litestream spawns linkding's webserver as subprocess.
CMD ["/scripts/run.sh"]

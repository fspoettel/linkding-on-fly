#!/bin/bash
set -e

# Restore the database if it does not already exist.
if [ -f $DB_PATH ]; then
  echo "Database exists, skipping restore."
else
  echo "No database found, restoring from replica if exists."
  litestream restore -if-replica-exists $DB_PATH
  echo "Successfully restored from replica."
fi

echo "Starting litestream & linkding service."

# Run litestream with your app as the subprocess.
exec litestream replicate -exec "/etc/linkding/bootstrap.sh"

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -f .env ]; then
  echo ".env already exists; keeping its values."
  exit 0
fi
umask 077
secret=$(openssl rand -hex 32)
sed "s/replace-with-a-random-secret-at-least-32-characters/$secret/" .env.example > .env
echo "Created .env with a unique local authentication secret."

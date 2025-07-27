#!/bin/sh

sleep 3

mkdir -p /tmp
filedate=$(date +%Y%m%dT%H%M%S)
logname="/tmp/healthcheck_${filedate}.txt"
echo "Waiting for PostgreSQL at miniapp_db:5432 as miniapp_user" > "$logname"

for i in $(seq 1 10); do
  if pg_isready -h "miniapp_db" -p "5432" -U "miniapp_user" >> "$logname" 2>&1; then
    echo "PostgreSQL is ready!" >> "$logname"
    break
  fi
  echo "Attempt $i failed..." >> "$logname"
  sleep 2
done

cat "$logname"

exec "$@"
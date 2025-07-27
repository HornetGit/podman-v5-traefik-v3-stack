#!/bin/bash
# CREATED: 28MAY2025
# UPDATED: 13JUN2025
# OWNER  : XCS HornetGit
# NOTE:Remove '-d'etachment to see the output of podman-compose up (DEBUG)
# --log-level debug -> check containers.conf


# make sure podman is using the podman user socket (and not the the docker socket owned by the root user)
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock

echo "Building and Starting up all 'miniapp' containers..."
podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build > /dev/null
# check
if [ $? -ne 0 ]; then
    echo "❌ Failed to start 1 or more miniapp container(s)."
    exit 1
fi
echo "✅ Miniapp: all containers restarted successfully."

echo 'Checking running state of miniapp containers: miniapp'
podman ps --all --filter "status=running" --filter "name=miniapp"
echo "✅  Done"

echo 'Checking networks of miniapp containers'
podman network ls --filter "name=miniapp"
echo "✅  Done"
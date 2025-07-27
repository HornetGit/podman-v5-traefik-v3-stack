#!/bin/sh
# OWNER : XCS HornetGit
# CREATED: MAY2025
# UPDATED: 21JUN2025

set -e

# Array of container names to manage
containers="miniapp_frontend miniapp_backend miniapp_db miniapp_pgadmin miniapp_traefik"

# Array of network names to manage
networks="miniapp_private miniapp_public"

# Get list of running miniapp containers
running_containers=$(podman ps -a --format "{{.Names}}" | grep "^miniapp_" || true)

if [ -n "$running_containers" ]; then
    echo "🛑 Stopping miniapp containers..."
    echo "$running_containers" | xargs podman stop 2>/dev/null || echo "Some containers were not running."
    
    echo "🛑 Deleting miniapp containers..."
    echo "$running_containers" | xargs podman rm -f 2>/dev/null || echo "Some containers could not be deleted."
else
    echo "❌ No running miniapp containers found."
fi

echo "🌐 Removing miniapp networks..."
sleep 1
for network in $networks; do
    podman network rm -f "$network" 2>/dev/null || true
    echo "✅ Removing network: $network"
done

echo "🛑 Pruning unused containers, images, volumes and pods..."
podman container prune -f
podman image prune -a -f
podman volume prune -f
podman pod prune -f

echo "✅ Full cleanup done."
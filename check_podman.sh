#!/bin/bash
# test podman version 5.x install with healthcheck functionality
# OWNER: XCS  
# CREATED: 04JUL2025

set -e


# cd $HOME/Project/InstallationScripts/

# Test healthcheck functionality (e.g. the main reason for my podman upgrade)
echo "Testing healthcheck functionality..."
podman run -d --name test-health \
  --health-cmd="echo 'healthy'" \
  --health-interval=30s \
  --health-retries=3 \
  --health-start-period=5s \
  alpine:latest sleep 300

echo "Waiting for healthcheck..."
sleep 10

# Check healthcheck status
echo "Healthcheck status:"
podman inspect test-health --format='{{.State.Health.Status}}'
podman ps

# Clean up test
podman stop test-health
podman rm test-health
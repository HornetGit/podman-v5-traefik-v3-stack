#!/bin/bash
podman build --format docker -t "custom-postgres:alpine" -f "./db/Dockerfile" "./db"
sleep 3
podman tag "custom-postgres:alpine" "version10_postgres:latest"
sleep 3
podman build --format docker -t "miniapp-backend:alpine" -f "./backend/Dockerfile" "."
sleep 3
podman tag "miniapp-backend:alpine" "version10_backend:latest"
sleep 3
podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d "postgres"
sleep 3
podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d "backend"
sleep 3
podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build frontend
sleep 3
podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build traefik
sleep 3
podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build pgadmin
sleep 3

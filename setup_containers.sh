#!/bin/bash
# CREATED: 28MAY2025
# UPDATED: 27JUL2025
# OWNER: XCS HornetGit
# SETUP SCRIPT: Run from inside mini-app/versionxx directory
# AUTO: launched from restart_application.sh
# PREREQUISITE: create a "dockeruser", as a podman rootless user and owner of the miniapp project dir
# VERSIONS: podman v5.3.1, podman-compose v1.4.1, GO 1.23, crun 1.19.2, traefik v3.4.3
# CHANGES: added reset_socket in the functions.sh and use of it in this script

set -e

echo "SETTING UP containers and networks..."

# Signs
OK="\e[32m✅\e[0m" # or : \e[92m → bright green
NOK="\e[31m❌\e[0m" # or : \e[91m → bright red
WARN="\e[33m⚠️\e[0m"  # or : \e[93m → bright orange/yellow

# source functions
source functions.sh

# Read env vars
source .env.dev

# podman setup variables
export PODMAN_COMPOSE_WARNING_LOGS=false
export PODMAN_PASST="$HOME/.local/bin/passt"
export PODMAN_COMPOSE_PROVIDER="/home/dockeruser/bin/podman-compose"

# set and load podman socket ($MINIAPP_TRAEFIK_PODMAN_SOCK used in the compose file)
reset_socket
[ $? -eq 1 ] && { echo -e "$NOK Socket not reset" ; exit 1; } || echo -e "$OK Socket successfully reset"

# create miniapp directory structure if not existing
mkdir -p config backend backend/templates backend/app frontend frontend/templates pgadmin \
          traefik traefik/acme traefik/certs traefik/templates \
          logs db db/pgadmin db/templates instructions
echo -e "$OK Directories added"

# this code directory is the root of the miniapp
current_dir=$(pwd)
yaml_file="podman-compose-dev.yaml"
env_dev=".env.dev"

# check that this script directory is below any directory named version*** potentially on 2 digits and any chars after
# e.g. version01, version02, version03_arch etc.
if [[ ! "$current_dir" =~ /version[0-9]{1,2}.* ]]; then
    echo "$NOK This script must be run from a directory below 'versionXX' (e.g. version01, version02, etc.)"
    exit 1
fi

# clean up files to be auto-generated from their templates
filename_list=(Dockerfile main.py db.py wait-for-db.sh nginx.conf index.html init.sql pg_service.conf traefik.yml dynamic.yml)
# for filename in "${filename_list[@]}"; do
#     find $current_dir -type f -name "$filename" -exec rm -f {} +
# done
# echo "check that this files were deleted: Dockerfile main.py db.py wait-for-db.sh nginx.conf index.html init.sql"
# exit 1

# check podman installation
if ! command -v podman &> /dev/null; then
    echo "$NOK Podman is not installed. Please install Podman first."
    exit 1
fi
podman_version=$(podman --version | awk '/podman version/ {print $3}')

# check podman status
if ! podman info &> /dev/null; then
    echo "$NOK Podman is not running. Please start Podman first."
    exit 1
fi

# check postgres repository
if ! podman search postgres &> /dev/null; then
    echo -e "$NOK Postgres image not found in the available repositorie(s). Please check your Podman setup."
    echo "Hint: see .config/containers/registries.conf for the default registries to seek images"
    exit 1
fi

# check podman-compose installation and version
if ! command -v podman-compose &> /dev/null; then
    echo -e "$NOK podman-compose is NOT installed. Please install podman-compose first (prefer LTS from github)."
    exit 1
fi
compose_version=$(podman compose version | awk '/podman-compose/ {print $3}')

# check/set that podman v5.x uses podman-compose (defined in containers.conf)
CONFIG_DIR="$HOME/.config/containers"
CONFIG_FILE="$CONFIG_DIR/containers.conf"
TEMPLATE=config/templates/containers.conf.template
# check that the template file exists and not empty
if [ ! -f "$TEMPLATE" ]; then
  echo -e "$NOK missing containers.conf template file"
  exit 1
fi

# Copy template if containers.conf missing
if [ ! -f "$CONFIG_FILE" ]; then
    # echo "📄 Creating containers.conf from template"
    echo -e "$NOK containers.conf: missing"
    cp "$TEMPLATE" "$CONFIG_FILE"
    echo -e "$OK containers.conf: created from template"
fi

# Double-check compose_provider is set
if ! grep -q "compose_provider" "$CONFIG_FILE"; then
    echo -e "$NOK compose_provider not set in containers.conf"
    echo "👉 Please add: compose_provider=\"/home/dockeruser/bin/podman-compose\""
    exit 1
fi
echo -e "$OK compose_provider: correctly set in containers.conf"

# final msg
echo -e "$OK podman ($podman_version) and podman-compose ($compose_version) are installed, up and running."


# ####################
# ----- backend -----
# ####################
# See : https://fastapi.tiangolo.com/bn/deployment/docker/#use-cmd-exec-form

# create an empty __init__.py file to make backend a package
touch backend/app/__init__.py

# create requirements.txt if missing
[ ! -f backend/requirements.txt ] && cp backend/templates/requirements.txt.template backend/requirements.txt

# set db Dockerfile
sed \
  -e "s|%%POSTGRES_VERSION%%|${MINIAPP_SW_VERSION_TAG}|" \
  db/templates/Dockerfile.template > db/Dockerfile

# set db entrypoint.sh
cp db/templates/entrypoint.sh.template db/entrypoint.sh
chmod +x db/entrypoint.sh

# backend Dockerfile
sed \
  -e "s|%%BACKEND_PORT%%|${MINIAPP_BACKEND_PORT_CONT}|" \
  backend/templates/Dockerfile.template > backend/Dockerfile

# backend main.py
sed \
  -e "s|%%BASE_DOMAIN%%|${MINIAPP_TRAEFIK_BASE_DOMAIN}|g" \
  -e "s|%%FRONTEND_DOMAIN%%|${MINIAPP_FRONTEND_DOMAIN}|" \
  -e "s|%%API_DOMAIN%%|${MINIAPP_BACKEND_DOMAIN}|" \
  -e "s|%%TRAEFIK_DOMAIN%%|${MINIAPP_TRAEFIK_DOMAIN}|" \
  -e "s|%%FRONTEND_HTTPS%%|https://${MINIAPP_FRONTEND_DOMAIN}:${MINIAPP_TRAEFIK_HTTPS_PORT_HOST}|" \
  -e "s|%%API_HTTPS%%|https://${MINIAPP_BACKEND_DOMAIN}:${MINIAPP_TRAEFIK_HTTPS_PORT_HOST}|" \
  -e "s|%%TRAEFIK_HTTPS%%|https://${MINIAPP_TRAEFIK_DOMAIN}:${MINIAPP_TRAEFIK_HTTPS_PORT_HOST}|" \
  -e "s|%%BACKENDPORT_ORIGIN%%|${MINIAPP_BACKEND_PORT_CONT}|" \
  backend/templates/main.py.template > backend/app/main.py

# db.py
# NOTE: MINIAPP_DB_HOST in .env.dev should better take the SAME name as its yml service 
sed \
  -e "s|%%DB_HOST%%|${MINIAPP_DB_HOST}|" \
  -e "s|%%DB_NAME%%|${MINIAPP_DB_NAME}|" \
  -e "s|%%DB_USER%%|${MINIAPP_DB_USER}|" \
  -e "s|%%DB_PASSWORD%%|${MINIAPP_DB_PASSWORD}|" \
  backend/templates/db.py.template > backend/app/db.py

# wait-for-db.sh (healthcheck workaround for podman v4.x)
sed \
  -e "s|%%DB_HOST%%|${MINIAPP_DB_HOST}|" \
  -e "s|%%DB_PORT%%|${MINIAPP_DB_PORT}|" \
  -e "s|%%DB_USER%%|${MINIAPP_DB_USER}|" \
  backend/templates/wait-for-db.sh.template > backend/wait-for-db.sh
chmod +x backend/wait-for-db.sh


# ####################
# ----- frontend -----
# ####################
# set index.html
sed \
  -e "s|%%BACKEND_API_URL_HTTPS%%|https://${MINIAPP_BACKEND_DOMAIN}:${MINIAPP_TRAEFIK_HTTPS_PORT_HOST}|" \
  frontend/templates/index.html.template > frontend/index.html

# frontend/nginx.conf
sed \
  -e "s|%%SERVER_NAME%%|${MINIAPP_FRONTEND_DOMAIN}|" \
  frontend/templates/nginx.conf.template > frontend/nginx.conf

# ###############
# ----- db -----
# ###############
# db/init.sql 
cp db/templates/init.sql.template db/init.sql

# ######################
# ----- Traefik v3 -----
# ######################

# self-signed cert, create new empty acme.json file (for TLS)
echo "GENERATING acme.json file ..."
[ -f traefik/acme/acme.json ] && rm traefik/acme/acme.json
touch traefik/acme/acme.json
chmod 600 traefik/acme/acme.json

# static config
echo "GENERATING Traefik v3 static config file from template..."
sed \
    -e "s|%%FRONTEND_PORT%%|${MINIAPP_TRAEFIK_HTTP_PORT_CONT}|g" \
    -e "s|%%DASHBOARD_PORT%%|${MINIAPP_TRAEFIK_DASHBOARD_PORT_CONT}|g" \
    -e "s|%%HTTPS_PORT%%|${MINIAPP_TRAEFIK_HTTPS_PORT_CONT}|g" \
    -e "s|%%PUBLIC_NETWORK_NAME%%|${NETWORK_PUBLIC_NAME}|g" \
    traefik/templates/traefik.yml.template > traefik/traefik.yml

# dynamic config
echo "GENERATING Traefik v3 dynamic config file from template..."
[ -f traefik/templates/dynamic.yml.template ] && cp traefik/templates/dynamic.yml.template traefik/dynamic.yml

# enable traefik to use the podman user socket (rootless)
if [ ! -S "$MINIAPP_TRAEFIK_PODMAN_SOCK" ]; then
    echo -e "$WARN  Podman user socket not found: $MINIAPP_TRAEFIK_PODMAN_SOCK"
    reset_socket
    [ $? -eq 1 ] && \
      { echo -e "$NOK Socket reset FAILED" ; exit 1; } || \
      echo -e "$OK Socket successfully reset (MINIAPP_TRAEFIK_PODMAN_SOCK=$MINIAPP_TRAEFIK_PODMAN_SOCK)"
else
    echo -e "$OK Podman user socket found: $MINIAPP_TRAEFIK_PODMAN_SOCK"
fi


# set access and traefik error logs
touch logs/access.log
touch logs/traefik.log


# ######################################
# ----- pgAdmin service management -----
# ######################################

# dB service access automation for PGadmin GUI
# thus only setting the new server connection in 1 shot
sed \
    -e "s|%%DB_HOST%%|${MINIAPP_DB_HOST}|" \
    -e "s|%%DB_PORT%%|${MINIAPP_DB_PORT}|" \
    -e "s|%%DB_USER%%|${MINIAPP_DB_USER}|" \
    -e "s|%%DB_PASSWORD%%|${MINIAPP_DB_PASSWORD}|" \
    -e "s|%%DB_NAME%%|${MINIAPP_DB_NAME}|" \
    pgadmin/templates/pg_service.conf.template > pgadmin/pg_service.conf

# TODO
# manage the pgadmin service as a traefik web service,
# so that enabling/disabling it easily from the compose file


# ^^^^^^^ CHECKED       ^^^^^
# vvvvvvv TO BE CHECKED vvvvv


# ######################################
# ----- compose file setup -------------
# ######################################
if [ -f "$yaml_file" ]; then
    echo -e "$OK yaml_file found: $yaml_file"
else
    echo -e "$NOK docker-compose file not found"
    exit 1
fi

chmod 644 "$yaml_file"
if [ "$(id -u)" -eq 0 ]; then
    chown dockeruser:dockeruser "$yaml_file"
else
    echo -e "$WARN  Skipping chown: not running as root. If needed, run 'sudo chown dockeruser:dockeruser $yaml_file'"
fi


# #######################
# CERTS, check and set
# #######################
# echo -e "$WARN  NOTES about TLS self-certificates:"
# echo -e "\tset local certs: see 'setup_certificates.sh'" 
# echo -e "\tFirefox: if getting an https cert warning,"
# echo -e "\tadjust: 'about:preferences#privacy', 'Certificates', 'View Certificates', 'Authorities', 'Import'"
./setup_certificates.sh


# ##########
# Clean exit
# ##########
final_msg1="$OK All files successfully generated."
final_msg2="$OK Ready to run: \e[32mpodman-compose --env-file $env_dev -f $yaml_file up -d --build\e[0m"
final_msg3="$OK Reset only 1 specific container: \e[32mpodman-compose --env-file $env_dev -f $yaml_file up -d --build the_specific_yaml_SERVICE_NAME\e[0m"
final_msg4="$OK Reset all: \e[32mpodman-compose --env-file $env_dev -f $yaml_file down && sleep 2 && podman-compose --env-file $env_dev -f $yaml_file  up -d\e[0m"

printf "##"'%*s\n' "${#final_msg4}" '' | tr ' ' '#'
echo -e "# $final_msg1"
echo -e "# $final_msg2"
echo -e "# $final_msg3"
echo -e "# $final_msg4"
printf "##"'%*s\n' "${#final_msg4}" '' | tr ' ' '#'
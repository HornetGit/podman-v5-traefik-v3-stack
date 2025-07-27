#!/bin/bash
# CREATED: 07JUL2025
# UPDATED: 09JUL2025
# OWNER: XCS HornetGit
# PURPOSE: test all backends networks (pasta, netavark, slirp4netns) and DNS

set -e

clear
script_name="$(basename "$0") by XCS  "
script_name2="$(basename "$0") by XCS"
printf "##"'%*s\n' "${#script_name}" '' | tr ' ' '#'
echo "# $script_name2 #"
printf "##"'%*s\n' "${#script_name}" '' | tr ' ' '#'

FAILED="\e[31mFAILED\e[0m" # or : \e[91m → bright red
OK="\e[32mOK\e[0m" # or : \e[92m → bright green

compose_version=$(podman compose version | awk '/podman-compose/ {print $2 $3}')

echo "🔎 Test 0: Checking Podman network backend"
PODNET=$(podman info | grep "networkBackend:" | awk '{print $2}' 2>/dev/null)
[ ! -z "${PODNET}" ] && echo -e "\t✅ Podman net: $OK ($PODNET)" || echo -e "\t❌ Podman net: $FAILED"

echo "🔎 Test 1: Podman basic info"
podman info >/dev/null && echo -e "\t✅ Podman info: $OK" || echo -e "\t❌ Podman info: $FAILED"

echo "🔎 Test 2: Rootless mode check"
podman info | grep -q 'rootless: true' && echo -e "\t✅ Rootless: $OK" || echo -e "\t❌ Rootless: $FAILED"

echo "🔎 Test 3: Default network (ping google, pls wait)"
podman run --rm alpine ping -c1 8.8.8.8 >/dev/null 2>&1 \
  && echo -e "\t✅ Default network: $OK" || echo -e "\t❌ Default network: $FAILED (positive fail if rootless)"

echo "🌐 Test 4: pasta network (curl https://example.com)"
podman run --rm --network pasta alpine sh -c "apk add --no-cache curl && curl -Is https://example.com" >/dev/null 2>&1 \
  && echo -e "\t✅ Pasta network: $OK (incl. DNS+ICMP)" || echo -e "\t❌ Pasta network: $FAILED"

echo "🌐 Test 5: slirp4netns network (curl https://example.com)"
podman run --rm --network slirp4netns alpine sh -c "apk add --no-cache curl && curl -Is https://example.com" >/dev/null 2>&1 \
  && echo -e "\t✅ Slirp4netns network: $OK (incl. DNS+ICMP)" || echo -e "\t❌ Slirp4netns network: $FAILED"

echo "🌐 Test 6: custom bridge network (curl http://myserver)"
podman network exists testnet || podman network create testnet >/dev/null
podman run -dit --replace --name myserver --network testnet httpd >/dev/null
podman run --rm --network testnet alpine sh -c "apk add --no-cache curl && curl -Is http://myserver" >/dev/null 2>&1 \
  && echo -e "\t✅ Custom bridge network: $OK" || echo -e "\t❌ Custom bridge network: $FAILED"
podman rm -f myserver >/dev/null
podman network rm testnet >/dev/null

echo "🌐 Test 7: DNS resolution (curl https://google)"
podman run --rm alpine sh -c "apk add --no-cache curl && curl -Is https://google.com" >/dev/null 2>&1 \
  && echo -e "\t✅ DNS resolution: $OK" || echo -e "\t❌ DNS resolution: $FAILED"

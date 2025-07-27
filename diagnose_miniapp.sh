#!/bin/bash
# CREATED: 10JUL2025
# UPDATED: 10JUL2025
# OWNER: XCS HornetGit
# PURPOSE: diagnose and debug miniapp podman: networks and containers

set -e

continue_or_abort() {
    local condition="$1"

    if [ "$condition" = false ]; then
        read -n1 -p "Press y/Y to continue, any other key to abort: " key
        echo    # move to a new line
        if [[ "$key" =~ [yY] ]]; then
            echo -e "✅ Continuing..."
        else
            echo -e "❌ Aborted by user."
            exit 1
        fi
    fi
}

# #### COSMETIC TITLE
clear
script_name="$(basename "$0") by XCS  "
script_name2="$(basename "$0") by XCS"
printf "##"'%*s\n' "${#script_name}" '' | tr ' ' '#'
echo "# $script_name2 #"
printf "##"'%*s\n' "${#script_name}" '' | tr ' ' '#'
NOK="\e[31mNOK\e[0m"    # bright red
OK="\e[32mOK\e[0m"      # bright green
WARN="\e[33mWARN\e[0m"  # yellow

# Source and use the defined env variables
source .env.dev

# Array of container names to manage
containers=("miniapp_frontend" "miniapp_backend" "miniapp_db" "miniapp_pgadmin" "miniapp_traefik")
count_containers=${#containers[@]}

# Array of network names to manage
networks=("miniapp_private" "miniapp_public")
count_networks=${#networks[@]}

# Get list of running miniapp containers
running_containers=($(podman ps -a --format "{{.Names}}" | grep "^miniapp_" || true))
count_running=${#running_containers[@]}


# #### PREREQUISITES, CHECK CORE ELEMENTS
echo -e "\n1) CHECK CORE ELEMENTS"
echo "###########################"

# Check if Podman is installed and containers up and running
echo "🔎 Check 1.1: podman version and containers"
R=false
R1=false
R2=false
R3=false
R4=false
R5=false
binary1=$(which podman) && R1=true
binary2=$(command -v podman) && R2=true
R3=$([ "$R1" = true ] && [ "$R2" = true ] && [ "$binary1" = "$binary2" ] && [ -f "$binary1" ] && echo true || echo false)
podman_version=$(podman --version | awk '{print $3}') && R4=true
# echo "bin1: $binary1"
# echo "bin2: $binary2"
# echo "ver: $podman_version"
# Check if containers are up
# echo "🔎 Check 1.3: Containers state"
for aContainer in "${containers[@]}"; do
    # up and running: podman ps --format "{{.Names}}" | grep -qx "miniapp_frontend" && echo "running"
    # exists and running: podman inspect -f '{{.State.Running}}' miniapp_frontend 2>/dev/null
    up_and_running=$(podman ps --format "{{.Names}}" | grep -qx "$aContainer" && echo $?)
    # BUG: This only checks miniapp_frontend for all containers, should be $aContainer
    if [ "$up_and_running" -eq 0 ]; then
        R5=true
        echo -e "\t✅ $aContainer :\t'up and running'"
    else
        R5=false
        echo -e "\t❌ $aContainer :\tnot 'up and running'"
        break
    fi
done
R=$([ "$R3" = true ] && [ "$R4" = true ] && [ "$R5" = true ] && echo true || echo false)
echo -e "\t$([ "$R" ] && echo "$OK" || echo "$NOK"): podman $podman_version with $count_running/$count_containers containers up & running"
continue_or_abort $R5

# Check Podman rootless mode
echo "🔎 Check 1.2: podman rootless mode"
R=$(podman info | grep -q 'rootless: true' && echo $?)
echo -e "\t$([ $R -eq 0 ] && echo "$OK" || echo "$NOK"): Rootless mode"

# Check if networks exist
echo "🔎 Check 1.3: Networks"
for n in "${networks[@]}"; do
    # echo "checking $n:"
    if podman network exists "$n"; then
        echo -e "\t✅ '$n' exists"
    else
        echo -e "\t❌ '$n' missing"
    fi
done

# networks up and engine
PODNET=$(podman info | grep "networkBackend:" | awk '{print $2}' 2>/dev/null)
[ ! -z "${PODNET}" ] && echo -e "\t✅ Podman net engine: $OK ($PODNET)" || echo -e "\t❌ Podman net engine: $NOK"

# check container(s) / network binds
for oneNet in "${networks[@]}"; do
    network_containers=($(podman network inspect $oneNet | grep '"name":' | tail -n +2 | awk -F'"' '{print $4}'))
    echo -e "\t${#network_containers[@]} container(s) for: $oneNet"
    for container in "${network_containers[@]}"; do
        container_iface=$(podman network inspect $oneNet | grep -A 20 "\"name\": \"$container\"" | grep -o '"eth[0-9]*"' | head -1 | tr -d '"')
        container_ipnet=$(podman network inspect $oneNet | grep -A 20 "\"name\": \"$container\"" | grep '"ipnet":' | head -1 | awk -F'"' '{print $4}')
        container_gw=$(podman network inspect $oneNet | grep -A 20 "\"name\": \"$container\"" | grep '"gateway":' | head -1 | awk -F'"' '{print $4}')
        container_ip=$(echo "$container_ipnet" | cut -d'/' -f1)
        echo -e "\t\t- $container, iface: $container_iface, inet: $container_ipnet, gw: $container_gw"
    done
done

# #### RUN NETWORK TESTS
echo -e "\n2) NETWORK TESTS"
echo "##################"

# Check DNS resolution from frontend → backend
echo "🔎 Test 2.1: Internal DNS resolution"
if podman exec -it miniapp_frontend sh -c "ping -c1 miniapp_backend" >/dev/null 2>&1; then
    echo -e "\t✅ DNS: frontend → backend resolves: $OK"
else
    echo -e "\t❌ DNS: frontend → backend fails: $NOK"
fi

# Check network connectivity ping from host to containers and to gw
echo "🔎 Test 2.2: ping from host to containers"
for oneNet in "${networks[@]}"; do
    network_containers=($(podman network inspect $oneNet | grep '"name":' | tail -n +2 | awk -F'"' '{print $4}'))
    network_gateway=$(podman network inspect $oneNet | grep '"gateway":' | head -1 | awk -F'"' '{print $4}')
    echo -e "\t${#network_containers[@]} container(s) for: $oneNet (pls wait...)"
    ping -c1 "$network_gateway" >/dev/null 2>&1 && \
        echo -e "\t✅ Ping from host to $oneNet gw $network_gateway: $OK" || \
        echo -e "\t❌ Ping from host to $oneNet gw $network_gateway: $NOK"
    for container in "${network_containers[@]}"; do
        container_ipnet=$(podman network inspect $oneNet | grep -A 20 "\"name\": \"$container\"" | grep '"ipnet":' | head -1 | awk -F'"' '{print $4}')
        container_ip=$(echo "$container_ipnet" | cut -d'/' -f1)
        container_gw=$(podman network inspect $oneNet | grep -A 20 "\"name\": \"$container\"" | grep '"gateway":' | head -1 | awk -F'"' '{print $4}')
        ping -c1 "$container_ip" >/dev/null 2>&1 && \
            echo -e "\t✅ Ping from host to $container (ip:$container_ip, gw chk: $container_gw): $OK" || \
            echo -e "\t❌ Ping from host to $container (ip:$container_ip, gw chk: $container_gw): $NOK"
    done
done


# Check network connectivity container to containers within a same network
echo "🔎 Test 2.3: ping from container to container inside one network"
for oneNet in "${networks[@]}"; do
    network_containers=($(podman network inspect $oneNet | grep '"name":' | tail -n +2 | awk -F'"' '{print $4}'))
    echo -e "\t${#network_containers[@]} container(s) for: $oneNet (pls wait...)"
    for container_from in "${network_containers[@]}"; do
        for container_to in "${network_containers[@]}"; do
            if [ "$container_from" != "$container_to" ]; then
                container_to_ipnet=$(podman network inspect $oneNet | grep -A 20 "\"name\": \"$container_to\"" | grep '"ipnet":' | head -1 | awk -F'"' '{print $4}')
                container_to_ip=$(echo "$container_to_ipnet" | cut -d'/' -f1)
                podman exec "$container_from" ping -c1 "$container_to_ip" >/dev/null 2>&1 && \
                    echo -e "\t✅ Ping $container_from → $container_to ($container_to_ip): $OK" || \
                    echo -e "\t❌ Ping $container_from → $container_to ($container_to_ip): $NOK"
            fi
        done
    done
done

# Check network connectivity container to containers within a same network
echo "🔎 Test 2.4: ping from a container of one network to a container of the other network"
# all cases to be tested even if I know that some MUST fail of course
network1_containers=($(podman network inspect miniapp_private | grep '"name":' | tail -n +2 | awk -F'"' '{print $4}'))
network2_containers=($(podman network inspect miniapp_public | grep '"name":' | tail -n +2 | awk -F'"' '{print $4}'))
echo -e "\tTesting miniapp_private → miniapp_public (pls wait...)"
for container_from in "${network1_containers[@]}"; do
    for container_to in "${network2_containers[@]}"; do
        container_to_ipnet=$(podman network inspect miniapp_public | grep -A 20 "\"name\": \"$container_to\"" | grep '"ipnet":' | head -1 | awk -F'"' '{print $4}')
        container_to_ip=$(echo "$container_to_ipnet" | cut -d'/' -f1)
        podman exec "$container_from" ping -c1 "$container_to_ip" >/dev/null 2>&1 && \
            echo -e "\t✅ Ping $container_from → $container_to ($container_to_ip): $OK" || \
            echo -e "\t❌ Ping $container_from → $container_to ($container_to_ip): $NOK"
    done
done
echo -e "\tTesting miniapp_public → miniapp_private (pls wait...)"
for container_from in "${network2_containers[@]}"; do
    for container_to in "${network1_containers[@]}"; do
        container_to_ipnet=$(podman network inspect miniapp_private | grep -A 20 "\"name\": \"$container_to\"" | grep '"ipnet":' | head -1 | awk -F'"' '{print $4}')
        container_to_ip=$(echo "$container_to_ipnet" | cut -d'/' -f1)
        podman exec "$container_from" ping -c1 "$container_to_ip" >/dev/null 2>&1 && \
            echo -e "\t✅ Ping $container_from → $container_to ($container_to_ip): $OK" || \
            echo -e "\t❌ Ping $container_from → $container_to ($container_to_ip): $NOK"
    done
done


# #### CONTAINER-SPECIFIC TESTS
echo -e "\n3) CONTAINER TESTS"
echo "####################"

# Traefik
echo "🔎 Test 3.1: Traefik health"
if curl -s -k https://traefik.localtest.me:8443/dashboard/ >/dev/null 2>&1; then
    echo -e "\t✅ Traefik dashboard reachable: $OK"
else
    echo -e "\t❌ Traefik dashboard unreachable: $NOK"
fi

# Frontend → Backend POST test
echo "🔎 Test 3.2: Frontend → Backend API call"
if podman exec -it miniapp_frontend sh -c "curl -s http://miniapp_backend:8001/ >/dev/null"; then
    echo -e "\t✅ Frontend → Backend API OK: $OK"
else
    echo -e "\t❌ Frontend → Backend API FAIL: $NOK"
fi

# DB health
echo "🔎 Test 3.3: Database connection"
if podman exec -it miniapp_backend sh -c "pg_isready -h miniapp_db -p 5432 -U $MINIAPP_DB_USER" >/dev/null 2>&1; then
    echo -e "\t✅ Postgres reachable: $OK"
else
    echo -e "\t❌ Postgres not responding: $NOK"
fi

# PgAdmin
echo "🔎 Test 3.4: PgAdmin web UI"
if curl -s -k http://localhost:$MINIAPP_PGLADMIN_PORT >/dev/null 2>&1; then
    echo -e "\t✅ PgAdmin reachable: $OK"
else
    echo -e "\t❌ PgAdmin unreachable: $NOK"
fi

echo -e "\n✅ All checks complete.\n"
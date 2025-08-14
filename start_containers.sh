#!/bin/bash
# CREATED: 28MAY2025
# UPDATED: 29JUL2025
# OWNER  : XCS HornetGit
# NOTES:
# --log-level debug -> check containers.conf
# 3 cases and ways for building and starting the containers:
# 1) services with a dockerfile AND healthcheck: specific commands for building and running these,
# 2) services with dockerfile but no heathcheck: podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build
# 3) services w/o dockerfile: podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build
# and ONLY 2 commands stacks for these 3 cases above: 
# a) split the 2 commands "build" and "run" , to build them with the docker format, and then run them ; this applies to above case 1)
# b) build and run in 1-liner podman-compose as shown for cases 2) and 3) 
# drawback: this way implies that the HELTHHCHECK are set in the  Dockerfile, and not in the  compose file.


set -e 

# init
clear
source functions.sh

# Load environment variables for envsubst
# for expanding the env variables, when parsing the tags from teh compose file
# in the get_service_image_tag function
set -a  # automatically export all variables
source .env.dev
set +a  # stop auto-exporting

# make sure podman is using the podman user socket (and not the docker socket owned by the root user)
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock

# Base array: ALL services with their basic information
# ⚠️  CRITICAL: Order matters for dependencies! Services are processed in this exact order.
# ORDERED by dependencies: postgres -> backend -> frontend (pgadmin, traefik independent)
# This order applies to BOTH oneliner builds AND healthcheck separate builds
# Format: ["service_name"]="context:dockerfile_path:container_name"
declare -A base_services=(
    ["postgres"]="./db:./db/Dockerfile:miniapp_db"
    ["backend"]=".:./backend/Dockerfile:miniapp_backend"
    ["frontend"]="./frontend::miniapp_frontend"
    ["pgadmin"]="./pgadmin::miniapp_pgadmin"
    ["traefik"]="./traefik::miniapp_traefik"
)

# Dependency order array
declare -a service_order=(postgres backend frontend traefik pgadmin)

# Array of service cases with clear text descriptions
declare -A service_cases=(
    [1]="dockerfile_with_healthcheck"
    [2]="dockerfile_without_healthcheck" 
    [3]="no_dockerfile_prebuilt_image"
)

# Array of command cases
declare -A command_cases=(
    ["a"]="podman_build_and_run_separately"
    ["b"]="podman_compose_build_and_run_oneliner"
)

# Result array: Base services amended with case analysis
# Format: ["service_name"]="context:dockerfile_path:service_case:command_case"
declare -A result_services=()

# Array to store all commands that will be executed
declare -A service_commands=()

# Function to extract image tag from compose file
get_compose_image_tag() {
    local service="$1"
    local compose_file="podman-compose-dev.yaml"
    
    # Use yq to extract the image tag, handling both build.image and direct image
    local image_tag
    image_tag=$(yq eval ".services.${service}.build.image // .services.${service}.image" "$compose_file" 2>/dev/null)
    
    # If yq not available, fall back to grep/sed
    if [ $? -ne 0 ] || [ -z "$image_tag" ]; then
        # Fallback method using grep
        image_tag=$(grep -A 10 "^  $service:" "$compose_file" | grep -E "^\s+image:" | sed 's/.*image: *"*\([^"]*\)"*.*/\1/' | head -1)
    fi
    
    # Expand environment variables
    image_tag=$(envsubst <<< "$image_tag")
    echo "$image_tag"
}

# Logic function to parse cases generically and populate result array
analyze_and_populate_services() {
    log_info "Analyzing services and determining cases..."
    
    #for service in "${!base_services[@]}"; do
    for service in "${service_order[@]}"; do
        #IFS=":" read -r context dockerfile <<< "${base_services[$service]}"
        IFS=":" read -r context dockerfile container_name <<< "${base_services[$service]}"
        local service_case=""
        local command_case=""
        
        # Determine service case
        if [ -z "$dockerfile" ]; then
            # Case 3: No dockerfile (prebuilt image)
            service_case=3
            command_case="b"
        elif [ -f "$dockerfile" ]; then
            # Has dockerfile - check for healthcheck
            if detect_healthcheck "$dockerfile"; then
                # Case 1: Dockerfile with healthcheck
                service_case=1
                command_case="a"
            else
                # Case 2: Dockerfile without healthcheck
                service_case=2
                command_case="b"
            fi
        else
            # Dockerfile specified but doesn't exist - error
            log_error "Dockerfile not found: $dockerfile for service $service"
            exit 1
        fi
        
        # Populate result array
        #result_services["$service"]="${context}:${dockerfile}:${service_case}:${command_case}"
        result_services["$service"]="${context}:${dockerfile}:${service_case}:${command_case}:${container_name}"

        # Log the analysis
        log_info "$service -> Case ${service_case}: ${service_cases[$service_case]}, Command ${command_case}: ${command_cases[$command_case]}, Container name: ${container_name}"
    done
    
    log_success "Service analysis complete"
}

# Function to build command array for all services
build_command_array() {
    log_info "Building command array for all services..."
    
    #for service in "${!result_services[@]}"; do
    for service in "${service_order[@]}"; do
        #IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
        IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"

        if [ "$command_case" = "a" ]; then
            # Case a: Split build and run (2 commands)
            local image_tag=$(get_compose_image_tag "$service")
            # local image_tag="localhost/$(basename $(pwd))_${service}:latest"
            local build_cmd="podman build --format docker -t \"$image_tag\" -f \"$dockerfile\" \"$context\""
            local run_cmd="podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d $service"
            service_commands["$service"]="$build_cmd|$run_cmd"
            #set_command "$build_cmd"
            #set_command "$run_cmd"
        elif [ "$command_case" = "b" ]; then
            # Case b: Oneliner (1 command) - FIXED: Added specific service name
            local oneliner_cmd="podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build $service"
            service_commands["$service"]="$oneliner_cmd"
            #set_command "$oneliner_cmd"
        fi
    done
}


# Display results
display_service_analysis() {
    echo ""
    echo "=== SERVICE CASE ANALYSIS ==="
    
    # Sort cases 1, 2, 3
    for case_num in 1 2 3; do
        if [[ -n "${service_cases[$case_num]}" ]]; then
            echo "Case $case_num: ${service_cases[$case_num]}"
        fi
    done
    
    echo ""
    echo "=== COMMAND CASES ==="
    
    # Sort commands a, b
    for cmd_case in a b; do
        if [[ -n "${command_cases[$cmd_case]}" ]]; then
            log_command "$cmd_case: ${command_cases[$cmd_case]}"
        fi
    done
    
    echo ""
    echo "=== RESULT SERVICES ==="
    
    # Display in dependency order (same order as base_services)
    #for service in postgres backend frontend pgadmin traefik; do
    for service in "${service_order[@]}"; do
        if [[ -n "${result_services[$service]}" ]]; then
            #IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
            IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"
            echo "$service: ${service_cases[$service_case]} -> ${command_cases[$command_case]}"
        fi
    done
}

# Function to display all commands for all services
display_all_commands() {
    echo ""
    echo "=== ALL COMMANDS FOR EACH SERVICE ==="
    
    # Display in dependency order (same order as base_services)
    # for service in postgres backend frontend pgadmin traefik; do
    for service in "${service_order[@]}"; do
        if [[ -n "${service_commands[$service]}" ]]; then
            #IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
            IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"
            echo ""
            echo "Service: $service (Case $service_case, Command $command_case)"
            
            # Split commands by | delimiter
            IFS="|" read -ra commands <<< "${service_commands[$service]}"
            
            for i in "${!commands[@]}"; do
                log_command " $((i+1)): ${commands[i]}"
            done
        fi
    done
    
    echo ""
    echo "=== EXECUTION SUMMARY ==="
    
    # Count services by command type
    local separate_count=0
    local oneliner_count=0
    local counting=0

    for service in "${service_order[@]}"; do
    # for service in "${!result_services[@]}"; do
    # for service in postgres backend frontend pgadmin traefik; do
        log_info "... processing service: $service"
        #IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
        IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"
        if [ "$command_case" = "a" ]; then
            separate_count=$((separate_count + 1))
        elif [ "$command_case" = "b" ]; then
            oneliner_count=$((oneliner_count + 1))
        fi
        counting=$((counting + 1))
        #echo "DEBUG: Read values - context='$context' dockerfile='$dockerfile' service_case='$service_case' command_case='$command_case'"
    done
    
    echo "Services needing separate build/run: $separate_count"
    echo "Services using oneliner compose: $oneliner_count"
    echo ""
    
    # DEBUG: Add this to see if function completes
    log_info "display_all_commands function completed successfully"
}

# Function 1: Build and run with oneliner compose (command case b)
# OBSOLETE
build_and_run_oneliner() {
    local services_list=("$@")
    
    log_info "Building and running services with oneliner compose: ${services_list[*]}"
    
    # Using explicit dependency predefined order
    for service in "${service_order[@]}"; do

        log_debug "Running 1-liner for service: $service"

        # Only process if service exists in result_services AND is in services_list
        if [[ -n "${result_services[$service]}" ]] && [[ " ${services_list[*]} " =~ " ${service} " ]]; then
            IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"
            
            # Remove only this specific container
            log_info "Removing existing container: $container_name"
            podman rm -f "$container_name" 2>/dev/null || true
            
            # Build and run this specific service
            log_command "podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build $service"
            # podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build "$service"
            set_command "podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build $service"

            # if [ $? -ne 0 ]; then
            #     log_error "Failed to build and run $service with oneliner"
            #     exit 1
            # fi
            # log_success "Started $service successfully"

        fi
    done
    
    log_success "Oneliner build and run completed successfully for: ${services_list[*]}"
}


# Function 2: Build and run separately (command case a)
# OBSOLETE
build_and_run_separately() {
    local services_list=("$@")
    
    log_info "Building and running services separately: ${services_list[*]}"
    log_warning "Services with healthchecks will be processed in dependency order!"
    log_info "If you have dependency issues, check the base_services array order"
    
    # Build each service with --format docker (in dependency order)
    for service in "${service_order[@]}"; do
    
        # Only process services that are in the services_list
        if [[ " ${services_list[*]} " =~ " ${service} " ]]; then
            #IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
            IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"
            log_info "Building $service with --format docker (healthcheck detected)"
            
            # Build with docker format, managing teh tag as latest 
            # local image_tag="localhost/$(basename $(pwd))_${service}:latest"
            local image_tag=$(get_compose_image_tag "$service")
            log_command "podman build --format docker -t \"$image_tag\" -f \"$dockerfile\" \"$context\""
            #podman build --format docker -t "$image_tag" -f "$dockerfile" "$context"
            set_command "podman build --format docker -t \"$image_tag\" -f \"$dockerfile\" \"$context\""
            # if [ $? -ne 0 ]; then
            #     log_error "Failed to build $service"
            #     exit 1
            # fi

            # tag the image with the name that podman-compose command expects
            local compose_expected_tag="version10_${service}:latest"
            log_info "TAGGING: podman tag \"$image_tag\" \"$compose_expected_tag\""
            # podman tag "$image_tag" "$compose_expected_tag"
            set_command "podman tag \"$image_tag\" \"$compose_expected_tag\""

            # if [ $? -ne 0 ]; then
            #     log_error "Failed to tag $service"
            #     exit 1
            # fi

            log_success "Built $service successfully"
        fi
    done
    
    # Run each service individually in dependency order
    log_info "Starting separately built services individually: ${services_list[*]}"
    for service in "${service_order[@]}"; do
        log_info "|_ trying to start: $service"
        if [[ " ${services_list[*]} " =~ " ${service} " ]]; then
            log_command "podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d $service"
            set_command "podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d \"$service\""
            # podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d "$service"
            # podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml --podman-run-args=--replace up -d "$service"
            # timeout 30 podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml --podman-run-args=--replace up -d "$service"
            # podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --no-build "$service"

            log_debug "Finished starting service: $service"
        #     if [ $? -ne 0 ]; then
        #         log_error "Failed to start $service"
        #         exit 1
        #     fi
        #     log_success "Started $service successfully"
        # else
        #     log_info "$service: NOT in the service list"
        fi
    done

}

# Function 3: Parse result array and call appropriate functions
# OBSOLETE
execute_build_and_run() {
    log_info "Executing build and run based on service analysis..."
    
    # Arrays to collect services by command type
    local oneliner_services=()
    local separate_services=()
    
    # Parse result array and categorize services
    #for service in "${!result_services[@]}"; do
    for service in "${service_order[@]}"; do
        #IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
        IFS=":" read -r context dockerfile service_case command_case container_name <<< "${result_services[$service]}"
        if [ "$command_case" = "a" ]; then
            separate_services+=("$service")
        elif [ "$command_case" = "b" ]; then
            oneliner_services+=("$service")
        fi
    done
    
    log_info "Found ${#separate_services[@]} services for separate build/run: ${separate_services[*]}"
    log_info "Found ${#oneliner_services[@]} services for oneliner: ${oneliner_services[*]}"
    
    # Execute based on what we found
    if [ ${#separate_services[@]} -gt 0 ] && [ ${#oneliner_services[@]} -gt 0 ]; then
        # Both types exist - run separate build first, then oneliner
        log_info "Mixed service types detected - running separate build first"
        log_info "|_separate build and run: ${separate_services[*]}"
        build_and_run_separately "${separate_services[@]}"

        log_info "|_one-liner run: "${oneliner_services[*]}""
        build_and_run_oneliner "${oneliner_services[@]}"

    elif [ ${#separate_services[@]} -gt 0 ]; then
        # Only separate services
        log_info "Only separate build services detected"
        build_and_run_separately "${separate_services[@]}"

    elif [ ${#oneliner_services[@]} -gt 0 ]; then
        # Only oneliner services
        log_info "Only oneliner services detected"
        build_and_run_oneliner "${oneliner_services[@]}"

    else
        log_error "No services to build and run"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting miniapp container build and deployment process..."
    
    # Analyze services and populate result array
    log_debug "Running : analyze_and_populate_services"
    analyze_and_populate_services
    
    # Build command array for all services
    log_debug "Running : build_command_array"
    build_command_array
    
    # Display the analysis
    log_debug "Running : display_service_analysis"
    display_service_analysis
    
    # Display all commands that would be executed
    log_debug "Running : display_all_commands"
    display_all_commands

    # Execute build and run based on analysis
    log_debug "Running : run_command"
    execute_build_and_run #: kept functions but all are obsoletes
    #run_command

    log_success "Miniapp deployment complete!"
}

# Run main function  
main "$@"
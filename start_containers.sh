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
source functions.sh

# make sure podman is using the podman user socket (and not the docker socket owned by the root user)
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock

# Base array: ALL services with their basic information
# Format: ["service_name"]="context:dockerfile_path"
# ⚠️  CRITICAL: Order matters for dependencies! Services are processed in this exact order.
# ORDERED by dependencies: postgres -> backend -> frontend (pgadmin, traefik independent)
# This order applies to BOTH oneliner builds AND healthcheck separate builds
declare -A base_services=(
    ["postgres"]="./db:db/Dockerfile"
    ["backend"]=".:backend/Dockerfile"
    ["frontend"]="./frontend:"
    ["pgadmin"]="./pgadmin:"
    ["traefik"]="./traefik:"
)

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

# Logic function to parse cases generically and populate result array
analyze_and_populate_services() {
    log_info "Analyzing services and determining cases..."
    
    for service in "${!base_services[@]}"; do
        IFS=":" read -r context dockerfile <<< "${base_services[$service]}"
        
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
        result_services["$service"]="${context}:${dockerfile}:${service_case}:${command_case}"
        
        # Log the analysis
        log_info "$service -> Case ${service_case}: ${service_cases[$service_case]}, Command ${command_case}: ${command_cases[$command_case]}"
    done
    
    log_success "Service analysis complete"
}

# Function to build command array for all services
build_command_array() {
    log_info "Building command array for all services..."
    
    for service in "${!result_services[@]}"; do
        IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
        
        if [ "$command_case" = "a" ]; then
            # Case a: Split build and run (2 commands)
            local image_tag="localhost/$(basename $(pwd))_${service}:latest"
            local build_cmd="podman build --format docker -t \"$image_tag\" -f \"$dockerfile\" \"$context\""
            local run_cmd="podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d $service"
            service_commands["$service"]="$build_cmd|$run_cmd"
            
        elif [ "$command_case" = "b" ]; then
            # Case b: Oneliner (1 command) - FIXED: Added specific service name
            local oneliner_cmd="podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build $service"
            service_commands["$service"]="$oneliner_cmd"
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
            echo "Command $cmd_case: ${command_cases[$cmd_case]}"
        fi
    done
    
    echo ""
    echo "=== RESULT SERVICES ==="
    
    # Display in dependency order (same order as base_services)
    for service in postgres backend frontend pgadmin traefik; do
        if [[ -n "${result_services[$service]}" ]]; then
            IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
            echo "$service: ${service_cases[$service_case]} -> ${command_cases[$command_case]}"
        fi
    done
}

# Function to display all commands for all services
display_all_commands() {
    echo ""
    echo "=== ALL COMMANDS FOR EACH SERVICE ==="
    
    # Display in dependency order (same order as base_services)
    for service in postgres backend frontend pgadmin traefik; do
        if [[ -n "${service_commands[$service]}" ]]; then
            IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
            
            echo ""
            echo "Service: $service (Case $service_case, Command $command_case)"
            
            # Split commands by | delimiter
            IFS="|" read -ra commands <<< "${service_commands[$service]}"
            
            for i in "${!commands[@]}"; do
                echo "  Command $((i+1)): ${commands[i]}"
            done
        fi
    done
    
    echo ""
    echo "=== EXECUTION SUMMARY ==="
    
    # Count services by command type
#     local separate_count=0
#     local oneliner_count=0
#     local counting=0

#     echo "before loop"

#     for service in "${!result_services[@]}"; do
#     # for service in postgres backend frontend pgadmin traefik; do
#         echo "DEBUG: Processing service: $service"
#         IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
#         echo "DEBUG: Read values - context='$context' dockerfile='$dockerfile' service_case='$service_case' command_case='$command_case'"

# #        IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
#         if [ "$command_case" = "a" ]; then
#             ((separate_count++))
#         elif [ "$command_case" = "b" ]; then
#             ((oneliner_count++))
#         fi
#         ((counting++))
#         echo "loop counting: $counting"
#     done
    
#     echo "Services needing separate build/run: $separate_count"
#     echo "Services using oneliner compose: $oneliner_count"
#     echo ""
    
    # DEBUG: Add this to see if function completes
    log_info "display_all_commands function completed successfully"
}

# Function 1: Build and run with oneliner compose (command case b)
build_and_run_oneliner() {
    local services_list=("$@")
    
    log_info "Building and running services with oneliner compose: ${services_list[*]}"
    
    # Run each service individually with oneliner (in dependency order)
    for service in postgres backend frontend pgadmin traefik; do
        # Only process services that are in the services_list
        if [[ " ${services_list[*]} " =~ " ${service} " ]]; then
            echo "COMMAND: podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build $service"
            podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d --build "$service"
        fi
    done
    
    if [ $? -eq 0 ]; then
        log_success "Oneliner build and run completed successfully for: ${services_list[*]}"
    else
        log_error "Failed to build and run with oneliner compose"
        exit 1
    fi
}

# Function 2: Build and run separately (command case a)
build_and_run_separately() {
    local services_list=("$@")
    
    log_info "Building and running services separately: ${services_list[*]}"
    log_warning "Services with healthchecks will be processed in dependency order!"
    log_info "If you have dependency issues, check the base_services array order"
    
    # Build each service with --format docker (in dependency order)
    for service in postgres backend frontend pgadmin traefik; do
        # Only process services that are in the services_list
        if [[ " ${services_list[*]} " =~ " ${service} " ]]; then
            IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
            
            log_info "Building $service with --format docker (healthcheck detected)"
            
            # Build with docker format
            local image_tag="localhost/$(basename $(pwd))_${service}:latest"
            echo "COMMAND: podman build --format docker -t \"$image_tag\" -f \"$dockerfile\" \"$context\""
            podman build --format docker -t "$image_tag" -f "$dockerfile" "$context"
            
            if [ $? -ne 0 ]; then
                log_error "Failed to build $service"
                exit 1
            fi
            
            log_success "Built $service successfully"
        fi
    done
    
    # Run ONLY the specific services we built (in dependency order)
    log_info "Starting only the separately built services: ${services_list[*]}"
    echo "COMMAND: podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d ${services_list[*]}"
    podman-compose --verbose --env-file .env.dev -f podman-compose-dev.yaml up -d "${services_list[@]}"
    
    if [ $? -eq 0 ]; then
        log_success "Separate build and run completed successfully for: ${services_list[*]}"
    else
        log_error "Failed to start services after separate build"
        exit 1
    fi
}

# Function 3: Parse result array and call appropriate functions
execute_build_and_run() {
    log_info "Executing build and run based on service analysis..."
    
    # Arrays to collect services by command type
    local oneliner_services=()
    local separate_services=()
    
    # Parse result array and categorize services
    for service in "${!result_services[@]}"; do
        IFS=":" read -r context dockerfile service_case command_case <<< "${result_services[$service]}"
        
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
        build_and_run_separately "${separate_services[@]}"
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
    analyze_and_populate_services
    
    # Build command array for all services
    build_command_array
    
    # Display the analysis
    display_service_analysis
    
    # Display all commands that would be executed
    display_all_commands

    # Execute build and run based on analysis
    execute_build_and_run
    
    log_success "Miniapp deployment complete!"
}

# Run main function  
main "$@"
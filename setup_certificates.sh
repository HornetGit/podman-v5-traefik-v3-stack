#!/bin/bash
# OWNER: XCS HornetGit
# CREATED: 20JUN2025
# TLS CERTIFICATE AND KEYRING SETUP (DEV)
# This script generates mkcert certificates for LOCAL DEV only

set -e  # Exit on any error

# Configuration
NEED_REGENERATE=false
CERT_DIR="traefik/certs"
BASE_DOMAIN="localhost"
CERT_FILE="${CERT_DIR}/${BASE_DOMAIN}-cert.pem"
KEY_FILE="${CERT_DIR}/${BASE_DOMAIN}-key.pem"

# Array of domains and subdomains
domains=(
    "$BASE_DOMAIN" 
    "traefik.$BASE_DOMAIN" 
    "backend.$BASE_DOMAIN" 
    "frontend.$BASE_DOMAIN"
    # Add more subdomains as needed
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if mkcert is installed
check_mkcert() {
    if ! command -v mkcert &> /dev/null; then
        print_error "mkcert is not installed!"
        print_status "Install mkcert first:"
        print_status "  - Debian/Ubuntu: Download from https://github.com/FiloSottile/mkcert/releases"
        print_status "  - Or use: wget -O mkcert https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-amd64"
        print_status "  - Then: chmod +x mkcert && sudo mv mkcert /usr/local/bin/"
        exit 1
    fi
    print_success "mkcert is installed"
}

# Function to check if mkcert CA is installed
check_mkcert_ca() {
    if [ ! -f "$(mkcert -CAROOT)/rootCA.pem" ]; then
        print_warning "mkcert CA not found, installing..."
        mkcert -install
        print_success "mkcert CA installed"
    else
        print_success "mkcert CA is already installed"
    fi
}

# Function to create certificate directory
create_cert_dir() {
    if [ ! -d "$CERT_DIR" ]; then
        print_status "Creating certificate directory: $CERT_DIR"
        mkdir -p "$CERT_DIR"
    else
        print_status "Certificate directory $CERT_DIR: exists"
    fi
}

# Function to check if certificates exist and are valid
check_existing_certs() {
    local need_regenerate=false
    
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        print_status "Certificate or key file missing"
        need_regenerate=true
    else
        print_status "Checking existing certificate validity..."
        
        # Check if certificate is expired or expires soon (within 30 days)
        if openssl x509 -checkend 2592000 -noout -in "$CERT_FILE" >/dev/null 2>&1; then
            print_success "Existing certificate is valid and not expiring soon"
            
            # Check if all domains are covered by existing certificate
            local missing_domains=()
            for domain in "${domains[@]}"; do
                # Skip wildcard check for now, just check if cert exists
                if ! openssl x509 -noout -text -in "$CERT_FILE" | grep -q "DNS:$domain" 2>/dev/null; then
                    if [[ "$domain" != *"*"* ]]; then  # Skip wildcard domains in this check
                        missing_domains+=("$domain")
                    fi
                fi
            done
            
            if [ ${#missing_domains[@]} -gt 0 ]; then
                print_warning "Certificate missing domains: ${missing_domains[*]}"
                need_regenerate=true
            fi
        else
            print_warning "Certificate is expired or expires within 30 days"
            need_regenerate=true
        fi
    fi

    print_status "Certs needs to be renewed: $need_regenerate"    

    # pass the result to the  caller
    # echo "$need_regenerate"
    NEED_REGENERATE="$need_regenerate"

}

# Function to generate certificates
generate_certificates() {
    print_status "Generating certificates for domains: ${domains[*]}"
    
    # Build mkcert command with all domains
    local mkcert_cmd="mkcert -key-file \"$KEY_FILE\" -cert-file \"$CERT_FILE\""
    for domain in "${domains[@]}"; do
        mkcert_cmd+=" \"$domain\""
    done
    
    # Execute the command
    print_status "Running: $mkcert_cmd"
    eval "$mkcert_cmd"
    
    if [ $? -eq 0 ]; then
        print_success "Certificates generated successfully!"
        print_status "Certificate: $CERT_FILE"
        print_status "Key: $KEY_FILE"
        
        # Show certificate details
        print_status "Certificate details:"
        openssl x509 -noout -text -in "$CERT_FILE" | grep -A 1 "Subject Alternative Name" || true
    else
        print_error "Failed to generate certificates!"
        exit 1
    fi
}

# Function to set proper permissions
set_permissions() {
    print_status "Setting proper permissions on certificate files..."
    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"
    print_success "Permissions set correctly"
}

# Function to verify certificates
verify_certificates() {
    print_status "Verifying generated certificates..."
    
    if openssl x509 -noout -text -in "$CERT_FILE" >/dev/null 2>&1; then
        print_success "Certificate file is valid"
        
        # Show expiration date
        local expiry_date=$(openssl x509 -noout -enddate -in "$CERT_FILE" | cut -d= -f2)
        print_status "Certificate expires: $expiry_date"
        
        # Show covered domains
        # print_status "Certificate covers the following domains:"
        # openssl x509 -noout -text -in "$CERT_FILE" | grep -A 10 "Subject Alternative Name" | grep "DNS:" | sed 's/.*DNS://g' | sed 's/,.*//g' | sort | uniq || true
        print_status "Certificate covers the following domains:"
        openssl x509 -noout -text -in "$CERT_FILE" | \
            grep -A 10 "Subject Alternative Name" | \
            grep -o "DNS:[^,]*" | \
            sed 's/DNS://g' | \
            sort | uniq || true
    else
        print_error "Generated certificate is invalid!"
        exit 1
    fi
    
    if [ -f "$KEY_FILE" ]; then
        print_success "Key file exists and is readable"
    else
        print_error "Key file is missing or unreadable!"
        exit 1
    fi
}

# Main execution
main() {
    #clear
    print_status "RUNNING: ${0##*/}"
    print_status "Starting TLS certificate setup for local development..."
    print_status "Base domain: $BASE_DOMAIN"
    print_status "Domains to cover: ${domains[*]}"
    echo
    
    # Check prerequisites
    check_mkcert
    check_mkcert_ca
    
    # Create certificate directory
    create_cert_dir
    
    # Check if we need to generate certificates
    #NEED_REGENERATE=$(check_existing_certs)
    check_existing_certs
    
    if [ "$NEED_REGENERATE" == "true" ]; then
        generate_certificates
        set_permissions
        verify_certificates
        echo
        print_success "Certificate(s) setup completed successfully!"
    else
        print_success "Existing certificates are valid and up to date!"
    fi
    
    echo
    print_status "Next steps:"
    print_status "1. Ensure Traefik is configured to use these certificates"
    print_status "2. Make sure dynamic.yml points to: $CERT_FILE and $KEY_FILE"
    print_status "3. Restart the Traefik container: podman-compose restart traefik_cont_name_or_ID"
    echo
}

# Run main function
main "$@"
#!/bin/bash

# Automated Static IP Configuration Script
echo "=== Automated Static IP Configuration ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo"
    exit 1
fi

# Function to detect network settings
detect_network_settings() {
    echo "Detecting network settings..."
    
    # Detect primary network interface (excluding lo)
    INTERFACE=$(ip route show default | awk '{print $5}' | head -1)
    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip addr show | grep -E "^\s*[0-9]+:" | grep -v "lo:" | awk '{print $2}' | cut -d: -f1 | head -1)
    fi
    
    # Detect current IP and subnet
    CURRENT_IP=$(ip addr show $INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    CURRENT_SUBNET=$(ip addr show $INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f2 | head -1)
    
    # Detect gateway
    GATEWAY=$(ip route show default | awk '{print $3}' | head -1)
    
    # If detection failed, use common defaults
    if [ -z "$INTERFACE" ]; then
        INTERFACE="eth0"
    fi
    
    if [ -z "$CURRENT_IP" ]; then
        CURRENT_IP="192.168.1.100"
    fi
    
    if [ -z "$CURRENT_SUBNET" ]; then
        CURRENT_SUBNET="24"
    fi
    
    if [ -z "$GATEWAY" ]; then
        GATEWAY="192.168.1.1"
    fi
    
    # Generate static IP (increment last octet of current IP)
    IP_BASE=$(echo $CURRENT_IP | cut -d. -f1-3)
    IP_LAST=$(echo $CURRENT_IP | cut -d. -f4)
    STATIC_IP="$IP_BASE.$((IP_LAST + 10))"
    
    # Use reliable DNS servers
    DNS_SERVERS="8.8.8.8 1.1.1.1"
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Function to configure static IP
configure_static_ip() {
    echo "Configuring static IP..."
    
    # Backup existing netplan files
    for file in /etc/netplan/*.yaml; do
        if [ -f "$file" ]; then
            cp "$file" "$file.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    done
    
    # Create new netplan configuration
    cat > /etc/netplan/01-static-ip.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [$STATIC_IP/$CURRENT_SUBNET]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS_SERVERS]
EOF

    # Apply configuration
    echo "Applying network configuration..."
    netplan generate
    netplan apply
    
    # Wait for network to stabilize
    echo "Waiting for network to stabilize..."
    sleep 8
}

# Function to configure firewall
configure_firewall() {
    echo "Configuring firewall..."
    
    # Enable UFW if available
    if command -v ufw &> /dev/null; then
        ufw --force enable
        
        # Allow common services
        ufw allow 22/tcp comment "SSH"
        ufw allow 80/tcp comment "HTTP"
        ufw allow 443/tcp comment "HTTPS"
        
        echo "Firewall configured with basic rules"
    else
        echo "UFW not available, skipping firewall configuration"
    fi
}

# Function to test connectivity
test_connectivity() {
    echo "Testing network connectivity..."
    
    # Test gateway connectivity
    if ping -c 2 -W 3 $GATEWAY &> /dev/null; then
        echo "✓ Gateway connectivity: SUCCESS"
    else
        echo "✗ Gateway connectivity: FAILED"
    fi
    
    # Test internet connectivity
    if ping -c 2 -W 3 8.8.8.8 &> /dev/null; then
        echo "✓ Internet connectivity: SUCCESS"
    else
        echo "✗ Internet connectivity: FAILED"
    fi
    
    # Get public IP
    echo "Fetching public IP..."
    PUBLIC_IP=$(curl -s -m 5 ifconfig.me || echo "Unable to determine")
    echo "Public IP: $PUBLIC_IP"
}

# Function to display summary
display_summary() {
    echo -e "\n=== Configuration Summary ==="
    echo "Network Interface: $INTERFACE"
    echo "Static IP: $STATIC_IP/$CURRENT_SUBNET"
    echo "Gateway: $GATEWAY"
    echo "DNS Servers: $DNS_SERVERS"
    echo "Public IP: $PUBLIC_IP"
    
    echo -e "\n=== Next Steps ==="
    echo "1. You can now access your VM at: $STATIC_IP"
    echo "2. Configure port forwarding on your router for: $STATIC_IP"
    echo "3. Backup created: /etc/netplan/*.backup.*"
    
    echo -e "\n=== Router Port Forwarding ==="
    echo "Access your router at: http://$GATEWAY"
    echo "Forward ports to: $STATIC_IP"
}

# Main execution
main() {
    echo "Starting automated network configuration..."
    
    # Detect current settings
    detect_network_settings
    
    # Display detected settings
    echo -e "\n=== Detected Settings ==="
    echo "Interface: $INTERFACE"
    echo "Current IP: $CURRENT_IP"
    echo "Static IP: $STATIC_IP"
    echo "Subnet: /$CURRENT_SUBNET"
    echo "Gateway: $GATEWAY"
    
    # Confirm with user (optional - can be removed for full automation)
    echo -e "\nProceeding with automatic configuration..."
    echo "Press Ctrl+C within 5 seconds to cancel..."
    sleep 5
    
    # Execute configuration steps
    configure_static_ip
    configure_firewall
    test_connectivity
    display_summary
    
    echo -e "\n=== Configuration Complete ==="
    echo "You may need to restart for all changes to take full effect."
}

# Run main function
main

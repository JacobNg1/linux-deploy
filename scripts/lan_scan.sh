#!/bin/bash

# Configuration
NETWORK_PREFIX="192.168.8"
USER="jacob"
TIMEOUT=0.2
# SSH options for a smoother experience
SSH_OPTS="-o StrictHostKeyChecking=no"

echo "--- LAN SSH Discovery ($(date +'%H:%M:%S')) ---"
printf "%-15s | %-28s | %s\n" "IP Address" "Hostname" "Quick Connect Command"
echo "--------------------------------------------------------------------------------------------"

scan_node() {
    local ip="$NETWORK_PREFIX.$1"
    
    # Fast TCP probe on port 22
    if timeout $TIMEOUT bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null; then
        # Try to resolve hostname
        local name=$(getent hosts "$ip" | awk '{print $2}')
        if [ -z "$name" ]; then
            name=$(avahi-resolve -a "$ip" 2>/dev/null | awk '{print $2}')
        fi
        
        local target
        if [ -n "$name" ]; then
            # If name exists, use name for SSH command
            target="$name"
        else
            # Fallback to IP and set display name to unknown
            target="$ip"
            name="unknown"
        fi
        
        # Print formatted row
        printf "%-15s | %-28s | ssh %s@%s\n" "$ip" "$name" "$USER" "$target"
    fi
}

# Run scan in parallel
for i in {1..254}; do
    scan_node $i &
done

wait
echo "--------------------------------------------------------------------------------------------"

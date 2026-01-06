#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

# --- VARIABLES ---
NODE1_IP="10.7.2.10"
NODE2_IP="10.7.2.11"
NODE3_IP="10.7.2.12"
INTERFACE="enp0s31f6" # The network interface name from your previous logs

# VIP: A "Floating IP" that points to whichever control plane node is leader.
# Best Practice: Set this to a FREE IP in your subnet (e.g. 10.7.2.100).
# If you leave this empty, the script will default to using NODE1_IP (Simple/SPOF).
VIP="10.7.2.100"

CLUSTER_NAME="talos-home-lab"

# --- LOGIC SETUP ---
if [ -n "$VIP" ]; then
    log "High Availability Mode: Using VIP $VIP"
    ENDPOINT="https://$VIP:6443"
else
    log "Simple Mode: Using Node 1 IP $NODE1_IP"
    ENDPOINT="https://$NODE1_IP:6443"
fi

# --- HELPER FUNCTIONS ---
log() {
    echo -e "\n\033[1;32m[INFO]\033[0m $1"
}

warn() {
    echo -e "\n\033[1;33m[WARN]\033[0m $1"
}

pause() {
    read -p "Press [Enter] to continue..."
}

# --- MAIN EXECUTION ---

clear
log "Starting Talos Cluster Bootstrap for $CLUSTER_NAME"
log "Nodes: $NODE1_IP, $NODE2_IP, $NODE3_IP"
log "Cluster Endpoint: $ENDPOINT"
warn "This is a DESTRUCTIVE operation. It will wipe the nodes."
pause

# 1. RESET NODES
log "Resetting nodes to maintenance mode..."
# We try/catch these in case the nodes are already reset or unreachable
talosctl -n $NODE1_IP -e $NODE1_IP reset --graceful=false --reboot || true
talosctl -n $NODE2_IP -e $NODE2_IP reset --graceful=false --reboot || true
talosctl -n $NODE3_IP -e $NODE3_IP reset --graceful=false --reboot || true

log "Waiting 60 seconds for nodes to reboot..."
sleep 60

# 2. GENERATE CONFIG
log "Generating new configuration files..."
rm -f controlplane.yaml worker.yaml talosconfig vip-patch.yaml
talosctl gen config "$CLUSTER_NAME" "$ENDPOINT"

# 3. PREPARE VIP PATCH (If VIP is used)
PATCH_FLAG=""
if [ -n "$VIP" ]; then
    log "Creating VIP configuration patch..."
    cat > vip-patch.yaml <<EOF
machine:
  network:
    interfaces:
      - interface: $INTERFACE
        vip:
          ip: $VIP
EOF
    PATCH_FLAG="--config-patch @vip-patch.yaml"
fi

# 4. APPLY CONFIG
log "Applying configuration to nodes..."
# Apply to Node 1
talosctl apply-config --insecure -n $NODE1_IP -e $NODE1_IP --file controlplane.yaml $PATCH_FLAG
# Apply to Node 2
talosctl apply-config --insecure -n $NODE2_IP -e $NODE2_IP --file controlplane.yaml $PATCH_FLAG
# Apply to Node 3
talosctl apply-config --insecure -n $NODE3_IP -e $NODE3_IP --file controlplane.yaml $PATCH_FLAG

log "Configuration applied. Waiting 30 seconds for services to start..."
sleep 30

# 5. BOOTSTRAP
log "Bootstrapping etcd on Node 1..."
# Note: We bootstrap via the Node IP
talosctl bootstrap -n $NODE1_IP -e $NODE1_IP

log "Waiting 60 seconds for etcd to stabilize..."
sleep 60

# 6. CONFIGURE LOCAL CLIENT
log "Merging local configuration..."
talosctl config merge ./talosconfig
# We set the endpoint to the VIP (if used) or the nodes
if [ -n "$VIP" ]; then
    talosctl config endpoint $VIP
    talosctl config node $VIP
else
    talosctl config endpoint $NODE1_IP $NODE2_IP $NODE3_IP
    talosctl config node $NODE1_IP
fi

# 7. DOWNLOAD KUBECONFIG
log "Downloading kubeconfig..."
talosctl kubeconfig .

# 8. VERIFY
log "Checking member status..."
# Use the new endpoint to check status
talosctl get members

# 9. UNTAINT CONTROL PLANE
log "Untainting control plane nodes to allow workloads..."
# We use || true because if the taint doesn't exist or fails slightly, we don't want to crash the script at the finish line
kubectl --kubeconfig=./kubeconfig taint nodes --all node-role.kubernetes.io/control-plane- || true

log "Done! You can now use: kubectl --kubeconfig=./kubeconfig get nodes"

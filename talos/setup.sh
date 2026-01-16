#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

# --- VARIABLES ---
# VIP: A "Floating IP" that points to whichever control plane node is leader.
VIP="10.7.2.100"
NODE1_IP="10.7.2.10"
NODE2_IP="10.7.2.11"
NODE3_IP="10.7.2.12"
INTERFACE="enp0s31f6"


CLUSTER_NAME="talos-home-lab"
ENDPOINT="https://$VIP:6443"

log() {
    echo -e "\n\033[1;32m[INFO]\033[0m $1"
}

pause() {
    read -p "Press [Enter] to continue..."
}

# --- MAIN EXECUTION ---
reset() {
    clear
    log "Starting Talos Cluster Bootstrap for $CLUSTER_NAME"
    log "Nodes: $NODE1_IP, $NODE2_IP, $NODE3_IP"
    log "Cluster Endpoint: $ENDPOINT"
    log "This is a DESTRUCTIVE operation. It will wipe the nodes."
    pause

    # 1. RESET NODES
    log "Resetting nodes to maintenance mode..."
    # We try/catch these in case the nodes are already reset or unreachable
    talosctl -n $NODE1_IP -e $NODE1_IP reset --graceful=false --reboot || true
    talosctl -n $NODE2_IP -e $NODE2_IP reset --graceful=false --reboot || true
    talosctl -n $NODE3_IP -e $NODE3_IP reset --graceful=false --reboot || true

    log "Waiting 60 seconds for nodes to reboot..."
}

config() {
    log "Generating new configuration files..."
    rm -f controlplane.yaml worker.yaml talosconfig vip-patch.yaml
    talosctl gen config "$CLUSTER_NAME" "$ENDPOINT" --config-path @patches/patch.yaml
}

apply() {
    log "Applying configuration to nodes..."
    # Apply to Node 1
    talosctl apply-config --insecure -n $NODE1_IP -e $NODE1_IP --file controlplane.yaml
    # Apply to Node 2
    talosctl apply-config --insecure -n $NODE2_IP -e $NODE2_IP --file controlplane.yaml
    # Apply to Node 3
    talosctl apply-config --insecure -n $NODE3_IP -e $NODE3_IP --file controlplane.yaml

    log "Configuration applied. Waiting 30 seconds for services to start..."
    sleep 30

    # apply edge patch
    talosctl patch machineconfig --nodes 10.7.2.10 --patch @talos/patches/edge.yaml
}

bootstrap() {
    log "Bootstrapping etcd on Node 1..."
    # Note: We bootstrap via the Node IP
    talosctl bootstrap -n $NODE1_IP -e $NODE1_IP

    log "Waiting 60 seconds for etcd to stabilize..."
    sleep 60

    # CONFIGURE LOCAL CLIENT
    log "Merging local configuration..."
    talosctl config merge ./talosconfig

    talosctl config endpoint $VIP
    talosctl config node $VIP
}

k8s() {

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
}

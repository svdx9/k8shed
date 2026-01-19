#!/bin/bash
# Kubernetes Home Lab Scaffolding Script
# This script creates the directory structure agreed upon in our design standards.
# It adds .gitkeep files to ensure empty directories are tracked by Git.

set -eu # Exit immediately if a command exits with a non-zero status

# --- Configuration ---
GITHUB_USER="svdx9"
REPO_NAME="k8shed"
CLUSTER_PATH="./cluster/production"

echo "🚀 Initializing Kubernetes Home Lab Structure..."

# Function to create dir and add gitkeep
create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        touch "$dir/.gitkeep"
        echo "✅ Created $dir"
    else
        echo "⏭️  Skipped $dir (already exists)"
    fi
}


setup_dirs() {
    # --- Cluster Layer ---
    create_dir "cluster/base"
    create_dir "cluster/production"

    # --- Infrastructure Layer ---
    create_dir "infrastructure/controllers"
    create_dir "infrastructure/networking"
    create_dir "infrastructure/storage"
    create_dir "infrastructure/security" # Added for SOPS/Secret Management components

    # --- Application Layer ---
    # create_dir "apps/media"
    # create_dir "apps/observability"
    # create_dir "apps/home-automation"

    # --- Talos / OS Layer ---
    create_dir "talos/patches"

    echo "🎉 Scaffolding complete! Your directory structure is ready."
}

init_flux() {
   # --- Pre-flight Checks ---
    echo "🚀 Preparing to Bootstrap Flux..."

    if ! command -v flux &> /dev/null; then
        echo "❌ Flux CLI not found. Please install it first: brew install fluxcd/tap/flux"
        exit 1
    fi

    required_envs=(
        "GITHUB_TOKEN:<your-token>"
        "GITHUB_USER:<your-username>"
        "REPO_NAME:<your-repo-name>"
        "CLUSTER_PATH:<your-cluster-path>"
        "SOPS_AGE_KEY_PATH:</path/to/age.key>"
    )

    for entry in "${required_envs[@]}"; do
        IFS=: read -r var hint <<< "$entry"
        if [ -z "${!var:-}" ]; then
            echo "⚠️  ${var} is not set. Flux needs this to write to your repo."
            echo "   export ${var}=${hint}"
            exit 1
        fi
    done

    # need to import sops key
    if [ ! -f "$SOPS_AGE_KEY_PATH" ]; then
        echo "❌ SOPS_AGE_KEY_PATH file not found: $SOPS_AGE_KEY_PATH"
        exit 1
    fi

    # --- Bootstrap Execution ---
    echo "⚙️  Running Flux Bootstrap for $CLUSTER_PATH..."
    # This installs the Flux controllers on the cluster and pushes the manifests to this repo.
    flux bootstrap github \
    --owner=$GITHUB_USER \
    --repository=$REPO_NAME \
    --branch=main \
    --path=$CLUSTER_PATH \
    --components-extra=image-reflector-controller,image-automation-controller \
    --personal


    kubectl -n flux-system create secret generic sops-age \
        --from-file=age.agekey="$SOPS_AGE_KEY_PATH" \
        --dry-run=client -o yaml | kubectl apply -f -

    # --- Post-Bootstrap Sync ---
    echo "📥 Syncing local repository..."
    git pull --rebase

    echo "------------------------------------------------"
    echo "🎉 Cluster Bootstrapped Successfully!"
    echo "👉 Next Step: Commit your scaffolded directories:"
    echo "   git add ."
    echo "   git commit -m 'chore: initialize directory structure'"
    echo "   git push"

}

init_flux

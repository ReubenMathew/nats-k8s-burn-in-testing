# This file contains helper functions and it is sourced by the main script.

function start_k3d_cluster()
{
    echo "🚀 Starting K3D cluster"
    # If cluster is already running, fail
    if k3d cluster get "${K3D_CLUSTER_NAME}" >/dev/null 2>&1; then
        echo "⚠️  Cluster ${K3D_CLUSTER_NAME} already running"
    else
        # Create the cluster
        k3d cluster create --config "${K3D_CLUSTER_CONFIG}"
    fi

    # Wait for the cluster to be ready
    kubectl wait --for=condition=ready node --all --timeout=60s || fail "Timeout waiting for k3d cluster"
}

function stop_k3d_cluster()
{
    echo "🛑 Stopping K3D cluster"
    # If cluster is not running, print warning message
    if ! k3d cluster get "${K3D_CLUSTER_NAME}" >/dev/null 2>&1; then
        echo "⚠️  Cluster ${K3D_CLUSTER_NAME} not running"
    else
        # Delete the cluster
        k3d cluster delete "${K3D_CLUSTER_NAME}"
    fi
}
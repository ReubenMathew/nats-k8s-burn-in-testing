#!/bin/bash -e

set -e

K3D_CLUSTER_CONFIG="./k3d/k3-cluster.yaml"
K3D_CLUSTER_NAME="k3-cluster"
HELM_CHART_CONFIG="./nats"
HELM_CHART_NAME="nats"
TESTS_DIR="./tests"

RR_TIMEOUT="2m"
RR_PAUSE=10 # Time between rolling restarts in seconds
RR_INITIAL_DELAY=10 # Time before first restart in seconds

function fail() {
  echo "❌ $*"
  exit 1
}

# These also make sure we're running the script from the expected location

test -f "${K3D_CLUSTER_CONFIG}" || fail "not found: ${K3D_CLUSTER_CONFIG}"
test -d "${HELM_CHART_CONFIG}" || fail "not found: ${HELM_CHART_CONFIG}"
test -d "bench" || fail "bench directory not found"

# Test Docker running
k3d node list || fail "Failed to list nodes (Docker not running?)"

# Set up cleanup
trap cleanup EXIT
function cleanup()
{
  # Kill any background jobs
  kill $(jobs -p) &>/dev/null
  # Uninstall Helm release
  if [[ -n "${LEAVE_CHART_UP}" ]]; then
    echo "Leaving helm chart alone (not launched by this script)"
  else
    helm uninstall "${HELM_CHART_NAME}"
  fi

  # Delete K3 cluster
  if [[ -n "${LEAVE_CLUSTER_UP}" ]]; then
    echo "Leaving cluster alone (not launched by this script)"
  else
    k3d cluster delete "${K3D_CLUSTER_NAME}"
  fi
}

if k3d cluster get "${K3D_CLUSTER_NAME}"; then
  echo "Cluster ${K3D_CLUSTER_NAME} is already running"
  export LEAVE_CLUSTER_UP="true"
else
  k3d cluster create --config ${K3D_CLUSTER_CONFIG}
fi

if helm status "${HELM_CHART_NAME}"; then
  echo "Helm ${HELM_CHART_NAME} already deployed"
  export LEAVE_CHART_UP="true"
else
  # Build and install Helm dependencies
  helm repo add nats https://nats-io.github.io/k8s/helm/charts/
  # N.B. could use --skip-refresh
  helm dependency build ${HELM_CHART_CONFIG}

  # Helm deploy
  helm upgrade \
    --debug \
    --install \
    --wait \
    --reset-values \
    ${HELM_CHART_NAME} \
    ${HELM_CHART_CONFIG}
fi

function rolling_bounce() {
  sleep "${RR_INITIAL_DELAY}"
  while true; do
    echo "Begin rolling restart"
    kubectl rollout restart statefulset/nats 1>/dev/null || fail "Failed to initiate rolling restart"
    kubectl rollout status statefulset/nats --timeout="${RR_TIMEOUT}" 1>/dev/null || fail "Failed to complete rolling restart"
    echo "Completed rolling restart"
    sleep "${RR_PAUSE}"
  done
}

# Start background process
rolling_bounce &

cd bench && go run main.go || fail "Test failed"

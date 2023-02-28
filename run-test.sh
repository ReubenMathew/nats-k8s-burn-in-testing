#!/bin/bash -e

# Usage: ./run-test.sh
# Depends on: Docker (running), k3d, kubectl, helm, go
#
# Which test and which 'mayhem' mode are currently hardcoded in this script.
#
# Overview:
#  1. Script checks it is running from the expected location (relative to configuration files and tests code)
#  2. Build tests code
#  3. Start a K3D virtual cluster (unless it's already running)
#  4. Deploy helm charts (unless it's already deployed)
#  5. Fork a background tasks causing some mayhem
#  6. Run the test client
#  7. Stop the background task injecting faults
#  8. Take down the helm chart (unless it was already running)
#  9. Take down the k3d cluster (unless it was already running)
# 10. Exit with code 0 unless something failed (usually, the test)
#
# To iterate faster on tests, it is possible to skip steps 2 & 3 (cluster creation and helm deployment).
# Either manually start one or the other before running the script (so that steps 7, 8 are skipped),
# OR run with `LEAVE_CHART_UP=yes LEAVE_CLUSTER_UP=yes ./rolling-bounce-test.sh` this will provision the cluster,
# deploy helm, but then exit without taking them down. If started this way, they need to be shut down manually.

set -e

# Constants
K3D_CLUSTER_CONFIG="./k3d/k3-cluster.yaml"
K3D_CLUSTER_NAME="k3-cluster"
HELM_CHART_CONFIG="./nats"
HELM_CHART_NAME="nats"
TESTS_DIR="./tests"
TESTS_EXE_NAME="test.exe"

# Test options:
# TEST_NAME="kv-cas"
TEST_NAME="durable-pull-consumer"
# TEST_NAME="queue-group-consumer"
# TEST_NAME="add-remove-streams"
TEST_DURATION="3m"

# Mayhem options:
MAYHEM_START_DELAY=5 # Time before rolling restart begins (in seconds)
MAYHEM_FUNCTION='rolling_restart'
# MAYHEM_FUNCTION='random_reload'

function fail()
{
  echo "❌ $*"
  exit 1
}

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

function mayhem()
{
  sleep "${MAYHEM_START_DELAY}"
  echo "🐵 Starting mayhem: ${MAYHEM_FUNCTION}"
  "${MAYHEM_FUNCTION}"
}

# Mayhem function rolling_restart restarts all pods (in order) via 'rollout' command
RR_TIMEOUT="3m" # Max amount of time a rolling restart should take
RR_PAUSE=5 # Time between rolling restarts (in seconds)
function rolling_restart() {
  while true; do
    echo "🐵 Begin rolling restart"
    kubectl rollout restart statefulset/nats 1>/dev/null || fail "Failed to initiate rolling restart"
    kubectl rollout status statefulset/nats --timeout="${RR_TIMEOUT}" || fail "Failed to complete rolling restart"
    echo "🐵 Completed rolling restart"
    sleep "${RR_PAUSE}"
  done
}

# Mayhem function random_reload randomly triggers a config reload on one of the servers
CLUSTER_SIZE=5
MIN_RELOAD_DELAY=0 # Minimum time between reloads
MAX_RELOAD_DELAY=10 # Maximum time between reloads
function random_reload() {
  while true; do
    RANDOM_POD="nats-$(( ${RANDOM} % ${CLUSTER_SIZE} ))"
    RANDOM_DELAY="$(( (${RANDOM} % (${MAX_RELOAD_DELAY} - ${MIN_RELOAD_DELAY})) + ${MIN_RELOAD_DELAY} ))"
    echo "🐵 Trigger config reload of ${RANDOM_POD}"
    kubectl exec "pod/${RANDOM_POD}" -c nats quiet -- sh -c 'kill -SIGHUP $(cat /var/run/nats/nats.pid)'
    sleep "${RANDOM_DELAY}"
  done
}

# Make sure we're running the script from the expected location
test -f "${K3D_CLUSTER_CONFIG}" || fail "not found: ${K3D_CLUSTER_CONFIG}"
test -d "${HELM_CHART_CONFIG}" || fail "not found: ${HELM_CHART_CONFIG}"
test -d "${TESTS_DIR}" || fail "not found: ${TESTS_DIR}"

# Build the tests binary
pushd "${TESTS_DIR}" >/dev/null
go build -o "${TESTS_EXE_NAME}" || fail "Build failed"
popd >/dev/null
test -f "${TESTS_DIR}/${TESTS_EXE_NAME}" || fail "not found: ${TESTS_DIR}/${TESTS_EXE_NAME}"

# Test Docker running
k3d node list || fail "Failed to list nodes (Docker not running?)"

# Set up cleanup
trap cleanup EXIT

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

# Wait for a potential previous rollouts still running
kubectl rollout status statefulset/nats --timeout="${RR_TIMEOUT}"

# Start background mayhem process
mayhem &

"${TESTS_DIR}/${TESTS_EXE_NAME}" --test "${TEST_NAME}" --duration "${TEST_DURATION}" || fail "Test failed"

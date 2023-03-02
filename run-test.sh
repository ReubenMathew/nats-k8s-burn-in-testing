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
CLUSTER_SIZE=5
POD_PREFIX="nats-"
TRAFFIC_SHAPING_CONTAINER="netshoot"

# Test options:
# TEST_NAME="kv-cas"
TEST_NAME="durable-pull-consumer"
# TEST_NAME="queue-group-consumer"
#TEST_NAME="add-remove-streams"
TEST_DURATION="3m"

# Mayhem options:
MAYHEM_START_DELAY=5 # Time before rolling restart begins (in seconds)
# MAYHEM_FUNCTION='none'
# MAYHEM_FUNCTION='rolling_restart'
# MAYHEM_FUNCTION='random_reload'
MAYHEM_FUNCTION='network_chaos'

# Docker image options:
USE_LOCAL_IMAGE=false

function fail()
{
  echo "❌ $*"
  exit 1
}

function reset_traffic_shaping
{
  echo "🧹 Resetting traffic shaping rules"
  # Delete any traffic shaping rules installed
  for pod_name in ${POD_NAMES};
  do
    kubectl exec ${pod_name} -c ${TRAFFIC_SHAPING_CONTAINER} -- tc qdisc delete dev eth0 root 2>/dev/null || echo
  done
}

function cleanup()
{
  # Kill any background jobs
  kill $(jobs -p) &>/dev/null

  # Reset any installed traffic shaping rule
  reset_traffic_shaping

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

function load_latest_nats_image() {
  docker pull nats:latest
  docker tag nats:latest localhost:5001/nats:local
  docker push localhost:5001/nats:local
}


function mayhem()
{
  sleep "${MAYHEM_START_DELAY}"
  echo "🐵 Starting mayhem: ${MAYHEM_FUNCTION}"
  "${MAYHEM_FUNCTION}"
}

function none()
{
  # NOOP mayhem function
  echo
}

# Mayhem function rolling_restart restarts all pods (in order) via 'rollout' command
RR_TIMEOUT="3m" # Max amount of time a rolling restart should take
RR_PAUSE=5 # Time between rolling restarts (in seconds)
function rolling_restart()
{
  while true; do
    echo "🐵 Begin rolling restart"
    kubectl rollout restart statefulset/nats 1>/dev/null || fail "Failed to initiate rolling restart"
    kubectl rollout status statefulset/nats --timeout="${RR_TIMEOUT}" || fail "Failed to complete rolling restart"
    echo "🐵 Completed rolling restart"
    sleep "${RR_PAUSE}"
  done
}

# Mayhem function random_reload randomly triggers a config reload on one of the servers
MIN_RELOAD_DELAY=0 # Minimum time between reloads
MAX_RELOAD_DELAY=10 # Maximum time between reloads
function random_reload()
{
  while true; do
    RANDOM_POD="${POD_PREFIX}$(( ${RANDOM} % ${CLUSTER_SIZE} ))"
    RANDOM_DELAY="$(( (${RANDOM} % (${MAX_RELOAD_DELAY} - ${MIN_RELOAD_DELAY})) + ${MIN_RELOAD_DELAY} ))"
    echo "🐵 Trigger config reload of ${RANDOM_POD}"
    kubectl exec "pod/${RANDOM_POD}" -c nats quiet -- sh -c 'kill -SIGHUP $(cat /var/run/nats/nats.pid)'
    sleep "${RANDOM_DELAY}"
  done
}

# Mayhem function network_chaos will apply netem traffic control manipulations to the network interface of each pod for a specific duration
SIDECAR_CONTAINER_NAME="netshoot"
# Used for reseting network interface in between tc manipulations
TC_RESET_COMMAND="tc qdisc delete dev eth0 root"
# Current example below will cause:
# 1. 3% of packets to be randomly dropped for 15 seconds
# 2. adds 50ms delay (100ms RTT) with a 5ms jitter with a normal distribution for 45 seconds
# 3. adds 100ms delay (200ms RTT) with a 10ms jitter with a normal distribution for 60 seconds
TC_MANIPULATION_LIST=(
  "tc qdisc add dev eth0 root netem loss 3%"
  "tc qdisc add dev eth0 root netem delay 50ms 5ms distribution normal"
  "tc qdisc add dev eth0 root netem delay 100ms 10ms distribution normal"
  )
TC_MANIPULATION_DURATION_LIST=(
  15
  45
  60
  )
function network_chaos() {
  # helper function to run kubectl exec on netshoot containers within every pod
  function exec_all_pods() {
    exec_command=$1
    pod_names=$(kubectl get pods --no-headers -o custom-columns=:metadata.name)
    for pod_name in $pod_names
    do
      echo "${pod_name}: ${exec_command}"
      kubectl exec $pod_name -c $SIDECAR_CONTAINER_NAME -- $exec_command
    done
  }

  for i in ${!TC_MANIPULATION_LIST[@]}; do
    tc_manipulation="${TC_MANIPULATION_LIST[$i]}"
    tc_manipulation_duration=${TC_MANIPULATION_DURATION_LIST[$i]}

    echo "Applying [${tc_manipulation}] to all pods for ${tc_manipulation_duration} seconds"
    exec_all_pods "${tc_manipulation}"
    sleep $tc_manipulation_duration
    echo "Resetting network interface for all pods"
    exec_all_pods "${TC_RESET_COMMAND}"
  done

}

function exec_all_pods() {
  exec_command=$1
  pod_names=$(kubectl get pods --no-headers -o custom-columns=:metadata.name)
  for pod_name in $pod_names
  do
    kubectl exec $pod_name -c $SIDECAR_CONTAINER_NAME -- sh -ec $exec_command
  done
}

# Mayhem function random_hard_kill randomly kills (SIGKILL) one of the servers
MIN_TIME_BETWEEN_HARD_KILL=1 # Minimum time between kills
MAX_TIME_BETWEEN_HARD_KILL=10 # Maximum time between kills
function random_hard_kill()
{
  while true; do
    RANDOM_POD="${POD_PREFIX}$(( ${RANDOM} % ${CLUSTER_SIZE} ))"
    RANDOM_DELAY="$(( (${RANDOM} % (${MAX_TIME_BETWEEN_HARD_KILL} - ${MIN_TIME_BETWEEN_HARD_KILL})) + ${MIN_TIME_BETWEEN_HARD_KILL} ))"
    echo "🐵 Killing ${RANDOM_POD} (sigkill)"
    kubectl exec "pod/${RANDOM_POD}" -c nats quiet -- sh -c 'kill -9 $(cat /var/run/nats/nats.pid)' || echo "Failed to kill ${RANDOM_POD}"
    # TODO: wait for all pods to be running again using
    #       `kubectl get pods  --field-selector status.phase!="Running"`
    sleep "${RANDOM_DELAY}"
  done
}

# Mayhem function slow_network sets an random network delay distribution for each server
MAX_NET_DELAY=100
MIN_NET_DELAY=0
function slow_network
{
  for pod_name in ${POD_NAMES};
  do
    DELAY="$(( (${RANDOM} % (${MAX_NET_DELAY} - ${MIN_NET_DELAY})) + ${MIN_NET_DELAY} ))"
    JITTER="$(( ${RANDOM} %(${MAX_NET_DELAY} - ${MIN_NET_DELAY})))"
    # TODO: numbers are not exactly delay +/- jitter, but close enough...
    echo "🐵 Degrading ${pod_name} network: ${DELAY}ms, ± ${JITTER}ms"
    kubectl exec "${pod_name}" -c "${TRAFFIC_SHAPING_CONTAINER}" -- tc qdisc add dev eth0 root netem delay "${DELAY}ms" "${JITTER}ms" distribution normal
  done
}

# Mayhem function lossy_network sets an random amount of network packet loss for each server
MAX_NET_LOSS=10
MIN_NET_LOSS=1
function lossy_network
{
  for pod_name in ${POD_NAMES};
  do
    LOSS="$(( (${RANDOM} % (${MAX_NET_LOSS} - ${MIN_NET_LOSS})) + ${MIN_NET_LOSS} ))"
    echo "🐵 Degrading ${pod_name} network: ${LOSS}% packet loss"
    kubectl exec "${pod_name}" -c "${TRAFFIC_SHAPING_CONTAINER}" -- tc qdisc add dev eth0 root netem loss "${LOSS}%"
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

echo "Use Local Docker Image? ${USE_LOCAL_IMAGE}"
# Load NATS docker image
if [ "$USE_LOCAL_IMAGE" = true]; then
  # TODO: pass the nats-server path and build a local docker image
  echo "Building local NATS image"
else
  echo "Pulling nats:latest from dockerhub"
  load_latest_nats_image
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

# Delete any network traffic shaping rules previously installed
reset_traffic_shaping

# Start background mayhem process
mayhem &

"${TESTS_DIR}/${TESTS_EXE_NAME}" --wipe --test "${TEST_NAME}" --duration "${TEST_DURATION}" || fail "Test failed"

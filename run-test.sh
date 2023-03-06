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
# OR run with `LEAVE_CHART_UP=yes LEAVE_CLUSTER_UP=yes ./run-test.sh` this will provision the cluster,
# deploy helm, but then exit without taking them down. If started this way, they need to be shut down manually.

set -e

for filename in mayhem helpers;
do
  . "./run-helpers/${filename}.sh"
done

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
# TEST_NAME="durable-pull-consumer"
# TEST_NAME="queue-group-consumer"
TEST_NAME="add-remove-streams"
TEST_DURATION="5s"

# Mayhem options:
MAYHEM_START_DELAY=5 # Time before rolling restart begins (in seconds)
MAYHEM_FUNCTION='none'
# MAYHEM_FUNCTION='rolling_restart'
# MAYHEM_FUNCTION='random_reload'
# MAYHEM_FUNCTION='network_chaos'
# MAYHEM_FUNCTION='slow_network'
# MAYHEM_FUNCTION='lossy_network'


# Docker image options:
# NATS_SERVER_LOCAL_SOURCE="../nats-server.git"
UPSTREAM_IMAGE_TAG="nats:alpine"
LOCAL_IMAGE_REPO='localhost:5001'
LOCAL_IMAGE_TAG='nats:local'

# Check environment before taking any actions
check

# Create list of pod names
#  TODO: could query for this (after rollout) using: `kubectl get pods --no-headers -o custom-columns=:metadata.name | xargs`
for (( i = 0; i < ${CLUSTER_SIZE}; i++ )); do
  POD_NAMES="${POD_NAMES} ${POD_PREFIX}${i}"
done

# Build test executable
build_test

# May build local nats-server image, or pull latest release from upstream
prepare_server_image

# Set up cleanup trap
trap cleanup EXIT

# Start K3D virtual cluster if not already running
k3d_start

# Publish server image into K3D registry
publish_server_image

# Deploy with helm if not already deployed
helm_deploy

# Delete any network traffic shaping rules previously installed
reset_traffic_shaping

# Start background mayhem process
mayhem &

run_test

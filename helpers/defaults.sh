# This file contains default environment variables and it is sourced by the main script

# Tools required to be installed on the host
BIN_DEPENDENCIES=(
    "docker"
    "k3d"
    "kubectl"
    "helm"
    "go"
)

# Docker image names and tags
DOCKERFILE="./config/docker/Dockerfile"
REGISTRY="localhost:5001"
IMAGE_NAME="nats"
LOCAL_IMAGE_TAG="local"
UPSTREAM_IMAGE_TAG="alpine"

# K3D
K3D_CLUSTER_NAME="k3-cluster"
K3D_CLUSTER_CONFIG="./config/k3d/k3-cluster.yaml"

# Helm
HELM_CHART_CONFIG="./config/helm/nats"
UPSTREAM_HELM_CHART="https://nats-io.github.io/k8s/helm/charts/"
HELM_CHART_NAMESPACE="nats"
HELM_CHART_VALUES="${HELM_CHART_CONFIG}/values.yaml"
NATS_SERVER_CONTAINER="nats"
TRAFFIC_SHAPING_CONTAINER="netshoot"


# Mayhem
MAYHEM_DIR="./mayhem"
MAYHEM_PIDS_DIR="./.mayhem-pids"
MAYHEM_LOG_FILE="./mayhem.log"
DEFAULT_MAYHEM_DELAY="3" #Seconds

# Tests
TESTS_DIR="./tests"
TEST_BIN="test.exe"
DEFAULT_TEST_DURATION="5s"

# Cluster details exposed to scripts
CLUSTER_SIZE=5
POD_PREFIX="nats-"
declare -a POD_NAMES=(${POD_NAMES})
for (( i = 0; i < ${CLUSTER_SIZE}; i++ ));
do
  POD_NAMES[${i}]="${POD_PREFIX}${i}"
done

# NATS server details exposed to script
NATS_SERVER_CONFIG_PATH="/etc/nats-config/nats.conf"
DIAGNOSTIC_BASE_URL="http://localhost:8222"
DIAGNOSTIC_ENDPOINTS="varz jsz connz accountz accstatz subsz routez leafz gatewayz healthz"

# Dump
DUMP_DIR="./dump"

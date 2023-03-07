# This file contains default environment variables and it is sourced by the main script

# Local files and directories
TESTS_DIR="./tests"

# Tools required to be installed on the host
BIN_DEPENDENCIES=(
    "docker"
    "k3d"
    "kubectl"
    "helm"
    "go"
)

# Docker image names and tags
DOCKERFILE="./Dockerfile"
REGISTRY="localhost:5001"
IMAGE_NAME="nats"
LOCAL_IMAGE_TAG="local"
UPSTREAM_IMAGE_TAG="alpine"

# K3D
K3D_CLUSTER_NAME="k3-cluster"
K3D_CLUSTER_CONFIG="./k3d/k3-cluster.yaml"

# Helm
HELM_CHART_CONFIG="./nats"
UPSTREAM_HELM_CHART="https://nats-io.github.io/k8s/helm/charts/"
HELM_CHART_NAMESPACE="nats"
HELM_CHART_VALUES="${HELM_CHART_CONFIG}/values.yaml"

# Mayhem
MAYHEM_DIR="./mayhem"
MAYHEM_PIDS_DIR="./.mayhem-state"
#!/usr/bin/env bash

function fail()
{
  echo "❌ $*"
  exit 1
}

# Check before doing anything
function check
{
  # Make sure we're running the script from the expected location
  test -f "${K3D_CLUSTER_CONFIG}" || fail "not found: ${K3D_CLUSTER_CONFIG}"
  test -d "${HELM_CHART_CONFIG}" || fail "not found: ${HELM_CHART_CONFIG}"
  test -d "${TESTS_DIR}" || fail "not found: ${TESTS_DIR}"

  # If pointed to nats-server source checkout, validate it exists
  if [[ -n "${NATS_SERVER_LOCAL_SOURCE}" ]] ; then
    test -d "${NATS_SERVER_LOCAL_SOURCE}" || fail "not found: ${NATS_SERVER_LOCAL_SOURCE}"
  fi

  # Test Docker is running
  k3d node list || fail "Failed to list nodes (Docker not running?)"
}

function cleanup()
{
  echo "🧹 Cleaning up"
  # Kill any background jobs
  kill $(jobs -p) &>/dev/null || echo "Mayhem not running"

  # Reset any installed traffic shaping rule
  reset_traffic_shaping

  # Uninstall Helm release
  if [[ -n "${LEAVE_CHART_UP}" ]]; then
    echo "Leaving helm chart alone (not launched by this script)"
  else
    helm uninstall "${HELM_CHART_NAME}" || echo "Failed to uninstall Helm"
  fi

  # Delete K3 cluster
  if [[ -n "${LEAVE_CLUSTER_UP}" ]]; then
    echo "Leaving cluster alone (not launched by this script)"
  else
    k3d cluster delete "${K3D_CLUSTER_NAME}" || echo "Failed to delete K3D cluster"
  fi
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


# Build the tests executable
function build_test
{
  pushd "${TESTS_DIR}" >/dev/null
  go build -o "${TESTS_EXE_NAME}" || fail "Build failed"
  popd >/dev/null
  test -f "${TESTS_DIR}/${TESTS_EXE_NAME}" || fail "not found: ${TESTS_DIR}/${TESTS_EXE_NAME}"
}

function prepare_server_image
{
  # Use upstream release image of nats, or build one from local source?
  if [[ -n "${NATS_SERVER_LOCAL_SOURCE}" ]] ; then
    echo "Building server image from source: ${NATS_SERVER_LOCAL_SOURCE}"
    # Build image and push it to K3D repository
    docker build "${NATS_SERVER_LOCAL_SOURCE}" -f ./Dockerfile -t "${LOCAL_IMAGE_REPO}/${LOCAL_IMAGE_TAG}"
  else
    echo "Pulling ${UPSTREAM_IMAGE_TAG} from Dockerhub"
    # Pull upstream image and push it to K3D repository
    docker pull "${UPSTREAM_IMAGE_TAG}"
  fi
}

function publish_server_image
{
  echo "Publishing image ${LOCAL_IMAGE_TAG} to repository ${LOCAL_IMAGE_REPO}"
  if [[ -n "${NATS_SERVER_LOCAL_SOURCE}" ]] ; then
    docker push "${LOCAL_IMAGE_REPO}/${LOCAL_IMAGE_TAG}"
  else
    docker tag "${UPSTREAM_IMAGE_TAG}" "${LOCAL_IMAGE_REPO}/${LOCAL_IMAGE_TAG}"
    docker push "${LOCAL_IMAGE_REPO}/${LOCAL_IMAGE_TAG}"
  fi
}

# Start K3D virtual cluster if not already running
function k3d_start
{
  if k3d cluster get "${K3D_CLUSTER_NAME}"; then
    echo "Cluster ${K3D_CLUSTER_NAME} is already running"
    export LEAVE_CLUSTER_UP="true"
  else
    k3d cluster create --config ${K3D_CLUSTER_CONFIG}
  fi
}

# Deploy (or upgrade) helm deployment
function helm_deploy
{
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
}

function run_test
{
  "${TESTS_DIR}/${TESTS_EXE_NAME}" --wipe --test "${TEST_NAME}" --duration "${TEST_DURATION}" || fail "Test failed"
}

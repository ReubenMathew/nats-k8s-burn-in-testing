#!/usr/bin/env bash

# Captures info into the dump directory

DUMP_DIR="./dump"
NATS_CONTAINER_NAME='nats'

POD_PREFIX='nats-'
NUM_PODS=5
CONFIG_PATH="/etc/nats-config/nats.conf"

DIAGNOSTIC_BASE_URL="http://localhost:8222"
DIAGNOSTIC_ENDPOINTS="varz jsz connz accountz accstatz subsz routez leafz gatewayz healthz"

# Uncomment (or set in environment) to skip the corresponding section
# SKIP_STATUS="yes"
# SKIP_EVENTS="yes"
# SKIP_DESCRIBE_POD="yes"
# SKIP_DIAGNOSTIC_ENDPOINTS="yes"
# SKIP_SERVER_LOGS="yes"
# SKIP_SERVER_CONFIG="yes"

function fail
{
  echo $*
  exit 1
}

function dumped
{
  echo "📥  `basename $1` ($2)"
}

test -d ${DUMP_DIR} || fail "Directory not found ${DUMP_DIR}"

TIMESTAMP=`date "+%Y-%m-%d_%H-%M-%S"`
OUT_DIR="${DUMP_DIR}/${TIMESTAMP}"

echo "Dumping in ${OUT_DIR}..."
mkdir "${OUT_DIR}"

POD_NAMES=""
for (( i = 0; i < ${NUM_PODS}; i++ )); do
  POD_NAMES="${POD_NAMES} ${POD_PREFIX}${i}"
done

# Dump controller events
if [[ -n "${SKIP_EVENTS}" ]]; then
  echo "Skip events"
else
  OUT_FILE="${OUT_DIR}/events.txt"
  kubectl get events > "${OUT_FILE}"
  dumped ${OUT_FILE} "events"
fi

# Dump pods status
if [[ -n "${SKIP_STATUS}" ]]; then
  echo "Skip status"
else
  OUT_FILE="${OUT_DIR}/status.txt"
  kubectl get pods > "${OUT_FILE}"
  dumped ${OUT_FILE} "pods status"
fi

# Dump pods info
if [[ -n "${SKIP_DESCRIBE_POD}" ]]; then
  echo "Skip pod description"
else
  for pod in ${POD_NAMES};
  do
    OUT_FILE="${OUT_DIR}/pod-${pod}.txt"
    kubectl describe pod ${pod} > "${OUT_FILE}"
    dumped ${OUT_FILE} "pod description"
  done
fi

# Dump JSON from diagnostic endpoints for each server
if [[ -n "${SKIP_DIAGNOSTIC_ENDPOINTS}" ]]; then
  echo "Skip diagnostics (${DIAGNOSTIC_ENDPOINTS})"
else
  for ep in ${DIAGNOSTIC_ENDPOINTS};
  do
    for pod in ${POD_NAMES};
    do
      OUT_FILE="${OUT_DIR}/${ep}-${pod}.json"
      kubectl exec "${pod}" -c "${NATS_CONTAINER_NAME}" -- wget -q "${DIAGNOSTIC_BASE_URL}/${ep}" -O - > "${OUT_FILE}"
      dumped ${OUT_FILE} "${ep} for ${pod}"
    done
  done
fi

# Dump servers log (since restart)
# TODO could configure server to log to file, so that entire log is retained
if [[ -n "${SKIP_SERVER_LOGS}" ]]; then
  echo "Skip server logs"
else
  for pod in ${POD_NAMES};
  do
    OUT_FILE="${OUT_DIR}/server-log-${pod}.txt"
    kubectl logs ${pod} -c "${NATS_CONTAINER_NAME}" > "${OUT_FILE}"
    dumped ${OUT_FILE} "nats-server log"
  done
fi

# Dump servers config
if [[ -n "${SKIP_SERVER_CONFIG}" ]]; then
  echo "Skip server config"
else
  for pod in ${POD_NAMES};
  do
    OUT_FILE="${OUT_DIR}/server-config-${pod}.conf"
    kubectl exec ${pod} -c "${NATS_CONTAINER_NAME}" -- cat "${CONFIG_PATH}" > "${OUT_FILE}"
    dumped ${OUT_FILE} "nats-server config"
  done
fi

# TODO could add traffic shaping status using:
#    kubectl exec ${pod} -c netshoot quiet -- tc qdisc list dev eth0 root
# but since rules are cleaned up on test completion this could be confusing.
# Skip for now.

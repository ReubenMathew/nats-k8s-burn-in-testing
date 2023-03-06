#!/usr/bin/env bash

# Mayhem is a function that injects some ...mayhem into the test.

function mayhem()
{
  echo "🐵 Holding off mayhem for ${MAYHEM_START_DELAY}s"
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

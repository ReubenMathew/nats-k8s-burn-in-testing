# Randomly chose a server and kill it with SIGKILL
function run()
{
    local min_delay="3"
    local max_delay="10"
    local cluster_size=5
    local pod_prefix="nats-"

    while true;
    do
        local random_pod="${pod_prefix}$(( ${RANDOM} % ${cluster_size} ))"
        local random_delay="$(( (${RANDOM} % (${max_delay} - ${min_delay})) + ${min_delay} ))"
        echo "🐵 Killing ${random_pod}"
        kubectl exec "pod/${random_pod}" -c nats quiet -- sh -c 'kill -9 $(cat /var/run/nats/nats.pid)'
        echo "🐵 Next kill in ${random_delay} seconds"
        sleep "${random_delay}"
    done
}

function cleanup ()
{
    echo "🐵 Goodbye World!"
}

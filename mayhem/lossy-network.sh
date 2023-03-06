# Introduce random packet loss at each cluster server

function run()
{
    local min_loss="3"
    local max_loss="10"

    for pod in "${POD_NAMES[@]}";
    do
        local loss=$(random_number_between ${min_loss} ${max_loss})
        echo "🐵 Introducing ${loss}% packet loss on ${pod} network"
        kubectl exec "pod/${pod}" -c "${TRAFFIC_SHAPING_CONTAINER}" quiet -- tc qdisc add dev eth0 root netem loss "${loss}%"
    done

    # Wait forever for kill signal
    while true;
    do
        sleep 1
    done
}

function cleanup ()
{
    local cluster_size=5

    for pod in "${POD_NAMES[@]}";
    do
        echo "🐵 Resetting traffic shaping for ${pod} network"
        kubectl exec "pod/${pod}" -c "${TRAFFIC_SHAPING_CONTAINER}" quiet -- tc qdisc delete dev eth0 root 2>/dev/null
    done
}

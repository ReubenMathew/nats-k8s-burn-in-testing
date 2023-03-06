# Randomly chose a server and trigger a config reload

function run()
{
    local min_delay="0"
    local max_delay="10"

    while true;
    do
        local random_pod=$(choose_random_pod)
        local random_delay="$(( (${RANDOM} % (${max_delay} - ${min_delay})) + ${min_delay} ))"
        echo "🐵 Reload config ${random_pod}"
        kubectl exec "pod/${random_pod}" -c nats quiet -- sh -c 'kill -SIGHUP $(cat /var/run/nats/nats.pid)'
        echo "🐵 Next reload in ${random_delay} seconds"
        sleep "${random_delay}"
    done
}

function cleanup ()
{
    echo "🐵 Goodbye World!"
}

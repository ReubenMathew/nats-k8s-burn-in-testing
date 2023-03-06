# This file contains helper functions and it is sourced by the main script.


function dumped
{
  echo "📥  `basename $1` ($2)"
}

function dump()
{
    local timestamp=`date "+%Y-%m-%d_%H-%M-%S"`
    local out_dir="${DUMP_DIR}/${timestamp}"

    mkdir -p "${out_dir}" || fail "Failed to create dump directory ${out_dir}"

    local out_file=""

    # Dump controller events
    if [[ -n "${SKIP_EVENTS}" ]]; then
        echo "Skip events"
    else
        out_file="${out_dir}/events.txt"
        kubectl get events > "${out_file}"
        dumped ${out_file} "events"
    fi

    # Dump pods status
    if [[ -n "${SKIP_STATUS}" ]]; then
        echo "Skip status"
    else
        out_file="${out_dir}/status.txt"
        kubectl get pods > "${out_file}"
        dumped ${out_file} "pods status"
    fi

    # Dump pods info
    if [[ -n "${SKIP_DESCRIBE_POD}" ]]; then
        echo "Skip pod description"
    else
        for pod in ${POD_NAMES[@]};
        do
            out_file="${out_dir}/pod-${pod}.txt"
            kubectl describe pod ${pod} > "${out_file}"
            dumped ${out_file} "pod description"
        done
    fi

    # Dump JSON from diagnostic endpoints for each server
    if [[ -n "${SKIP_DIAGNOSTIC_ENDPOINTS}" ]]; then
        echo "Skip diagnostics (${DIAGNOSTIC_ENDPOINTS})"
    else
        for ep in ${DIAGNOSTIC_ENDPOINTS};
        do
            for pod in ${POD_NAMES[@]};
            do
                out_file="${out_dir}/${ep}-${pod}.json"
                kubectl exec "${pod}" -c "${NATS_SERVER_CONTAINER}" -- wget -q "${DIAGNOSTIC_BASE_URL}/${ep}" -O - > "${out_file}"
                dumped ${out_file} "${ep} for ${pod}"
            done
        done
    fi

    # Dump servers log (since restart)
    # TODO could configure server to log to file, so that entire log is retained
    if [[ -n "${SKIP_SERVER_LOGS}" ]]; then
        echo "Skip server logs"
    else
    for pod in ${POD_NAMES[@]};
    do
        out_file="${out_dir}/server-log-${pod}.txt"
        kubectl logs ${pod} -c "${NATS_SERVER_CONTAINER}" > "${out_file}"
        dumped ${out_file} "nats-server log"
    done
    fi

    # Dump servers config
    if [[ -n "${SKIP_SERVER_CONFIG}" ]]; then
        echo "Skip server config"
    else
        for pod in ${POD_NAMES[@]};
        do
            out_file="${out_dir}/server-config-${pod}.conf"
            kubectl exec ${pod} -c "${NATS_SERVER_CONTAINER}" -- cat "${NATS_SERVER_CONFIG_PATH}" > "${out_file}"
            dumped ${out_file} "nats-server config"
        done
    fi

    # TODO could add traffic shaping status using:
    #    kubectl exec ${pod} -c netshoot quiet -- tc qdisc list dev eth0 root
    # but since rules are cleaned up on test completion this could be confusing.
    # Skip for now.

    echo "🚚  Dumped to ${out_dir}"
}

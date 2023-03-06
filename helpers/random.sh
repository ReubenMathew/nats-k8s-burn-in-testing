# This file contains helper functions and it is sourced by the main script.

function random_number_between()
{
    local min="$1"
    local max="$2"
    echo "$(( (${RANDOM} % (${max} - ${min})) + ${min} ))"
}

function choose_random_pod()
{
    local num_pods="${#POD_NAMES[@]}"
    local index=$(random_number_between 0 ${num_pods})
    echo "${POD_NAMES[${index}]}"
}

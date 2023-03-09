#!/usr/bin/env bash

# Main switch statement that parses arguments.
# sub-commands are: check, start, stop, mayhem, stop-mayhem, test, run, dump, help

# Print an error message to stderr and exits with a non-zero status.
function fail()
{
    echo "❌ $@" >&2
    exit 1
}

# Source helper files
source_files=(
    "./helpers/defaults.sh"
    "./helpers/check.sh"
    "./helpers/image.sh"
    "./helpers/k3d.sh"
    "./helpers/helm.sh"
    "./helpers/mayhem.sh"
    "./helpers/test.sh"
    "./helpers/random.sh"
    "./helpers/dump.sh"
)
for source_file in "${source_files[@]}"; do
    source "${source_file}" || fail "Failed to source ${source_file}"
done

function main()
{
    case "$1" in
        check)
            set -e
            # Check if the environment is ready to run the tests
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running
            echo "✅ Environment is ready to run the tests"
            ;;
        start)
            set -e
            # Check if the environment is ready to run the tests
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running
            # Start K3D virtual cluster
            start_k3d_cluster

            # Optional argument: a path the local NATS server source.
            # If provided, it will be used to build a local Docker image
            # If not provided, the latest release image will be pulled from Docker Hub
            if [[ -n "$2" ]]; then
                publish_local_source_image "$2"
            else
                publish_latest_release_image
            fi

            # Deploy NATS using Helm
            deploy_nats_cluster

            ;;
        stop)
            # Check if the environment is sane
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running
            # Stop any running mayhem agents
            stop_mayhem
            # Stop K3D virtual cluster
            stop_k3d_cluster
            ;;
        mayhem)
            # Required argument: name of mayhem agent to start
            if [[ -z "$2" ]]; then
                fail "Missing argument: name of mayhem agent to start"
            fi
            # Optional argument: delay before starting the mayhem agent
            delay="${3:-${DEFAULT_MAYHEM_DELAY}}"


            # Check if the environment is sane
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running

            # Start a 'mayhem agent', which injects random failures into the environment
            mayhem "$2" "${delay}"
            ;;
        stop-mayhem)
            # Check if the environment is sane
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running

            # Stop all running mayhem agents
            stop_mayhem
            ;;
        test)
            # Required argument: name of test to run
            if [[ -z "$2" ]]; then
                fail "Missing argument: name of test run"
            fi
            # Optional argument: duration of test
            duration="${3:-${DEFAULT_TEST_DURATION}}"

            # Check if the environment is sane
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running
            # Build the test binary
            build_test
            run_test "$2" "${duration}"
            ;;
        run)
            echo "Not implemented"
            exit 1
            # TODO this mode is meant for CI
            # It starts the test environment, runs a test, stops the environment
            # It also starts a mayhem agent with a configurable delay
            ;;
        dump)
            # Check if the environment is sane
            check_files_and_dirs
            check_bin_dependencies
            check_docker_running
            dump
            ;;
        help)
            echo "Usage: $0 {check|start|stop|mayhem|reset|test|run|help}"
            # Print a summary for each sub-command and its arguments
            echo "check: Check if the environment is ready to run the tests"
            echo "start [nats-server_source_dir]: Start the test environment"
            echo "stop: Stop the test environment"
            echo "mayhem <name> [delay_seconds]: Start a 'mayhem agent', which injects random failures into the environment"
            echo "stop-mayhem <name>: Stop all running mayhem agents"
            echo "test <name> [duration]: Run the specified test client"
            echo "run <test_name> <mayhem_name> [duration]: Start the test environment, run a test, stop the environment"
            echo "dump: Capture logs and other information from the test environment"
            exit 0
            ;;
        *)
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main $*

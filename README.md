# Failground

## A failure testing playground

Failground is a utility to test NATS server and client in the presence of failures.

Failground can be employed in different scenarios.

 * Developers: testing local changes to NATS client and server in the presence of failures
 * CI: run a test matrix with combinations of tests and failure modes, this is suitable for:
   * Release qualification
   * Long-running stress tests

Failground runs in a virtualized environment, therefore it is not suitable for performance measurements

### Notable features

 * Easy to add new tests
 * Easy to add new mayhem modes
 * Easy to run against local development version of NATS server or client

---

## Overview

Failground is made to be run on a developer's laptop or in a CI pipeline.

1. K3D creates a virtual Kubernetes cluster using Docker
2. Helm deploys a NATS cluster
3. (optional) one or more mayhem agent start injecting failures
4. A test workload is run from the host against the NATS cluster

### Requirements
- `k3d`
- `kubectl`
- `docker`
- `go`
- `helm`

---

## Example usage

The following is an example session with a developer interacting with failground.

### Check dependencies

```
./failground.sh check
```

Verifies that all required dependencies are installed (does not attempt to install them or make any other modification to your system)

### Bring up the virtual cluster

```
./failground.sh start ../nats-server.git
```

Build the nats-server binary locally from the given location, then start a NATS cluster.

If the source path is omitted, the latest release image `nats:alpine` is used.

### Add mayhem

```
./failground mayhem slow-network
./failground mayhem random-reload
```

Start two "mayhem" agents:
 * The first sets a small random delay on the network interface of all (virtual) hosts running NATS server, thus simulating a network with some latency
 * The second causes the servers to reload (using SIGHUP) at random intervals

Mayhem agents log to `mayhem.log`

It is possible to delay the start of a mayhem agent (for example to ensure the test has time to initialize cleanly before anything goes wrong). The `mayhem` command takes an optional argument for this reason, e.g.:

```
./failground mayhem random-hard-kill 30
```

Which means: in 30 seconds, start killing (SIGKILL) servers at random intervals.

### Run a test

```
./failground test kv-cas 120s
```

Start the test workload named `kv-cas` and declare success if it could run successfully for 120 seconds.

In this case, `kv-cas` does operations using the KeyValue's Update API (Compare and Swap).
And it checks that successfully committed values are not lost.

### Stop mayhem
```
./failground stop-mayhem
```

Stop any mayhem agent which may be running in background.

### Dump cluster state

```
./failground dump
```

Dumps cluster diagnostic information into a timestamped folder inside `dump/`

### Bring down the environment

```
./failground stop
```

Stops the virtual cluster

---

## Mayhem agents

Mayhem agents are simple, take a look in the `mayhem/` directory.

### `lossy-network`

Introduces a random amount of packet loss in the virtual servers network interfaces

Cannot be combined with other `*-network` agents

### `slow-network`

Introduces a random amount of latency and jitter in the virtual servers network interfaces

Cannot be combined with other `*-network` agents

### `random-hard-kill`

At random intervals, choose a random NATS server and kill it via SIGKILL

### `random-reload`

At random intervals, choose a random NATS server and trigger a configuration reload with SIGHUP

### `rolling-restart`

At random intervals, trigger a Kubernetes rolling restart for the entire cluster

### `noop`

This agent only prints messages to the log, it's used for testing

---

## Test workloads

Tests are self-contained *go* programs in the `tests/` directory.

Tests must be written to run arbitrarily long, and they need to be fault-tolerant:
 - Retry operations that might fail
 - Handle disconnections and reconnections
 - Handle timeouts
 - ...


### `add-remove-streams`

A single client creates and deletes streams.
It verifies that successfully created streams still exist, and deleted streams don't reappear later.

### `durable-pull-consumer`

A single client publishing one message to a stream, than consuming and verifying the same message using a durable consumer.

### `queue-group-consumer`

A single client publishing one message to a queue, than verifying that it gets consumed by at most one of the clients subscribed to the queue.

### `kv-cas`

A single client performing CAS updates on a small set of keys and verifying committed values are not lost.

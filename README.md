# K8s NATS Burn-in Testing
A testing set of `nats-server` workloads running against a variety of failure modes in a Kubernetes environment. 

## File Structure Explanation
<!--TODO: File structure explanation, point out important fconfig files that can be changed -->

## Requirements
<!--TODO: Add links or install instructions for some tools-->
- `k3d`
- `kubectl`
- `docker`
- `go`
- `helm`

## Using a locally built `nats-server` image
The included helm chart pulls a `nats-server` image from a locally created registry. By default, this image is `nats:latest` found on [Dockerhub](https://hub.docker.com/_/nats). The `nats:latest` image is pulled, re-tagged and pushed to the local image registry, provisioned by K3D.

Modifying the `USE_LOCAL_IMAGE` value in `./run-test.sh` will instead build the `nats-server` image from source and push it to the local registry for helm to use instead. The path location of your `nats-server` repository can be modified through the `LOCAL_NATS_SERVER_REPO` value (also found in `./run-test.sh`). 

### Instructions
1. Clone `nats-server` onto your machine
2. Enable `USE_LOCAL_IMAGE` in `./run-test.sh`
3. Change the value of `LOCAL_NATS_SERVER_REPO` to where you cloned the `nats-server` repository

## Mayhem modes
<!--TODO: Add mayhem mode description-->

### `rolling_restart`

Triggers rolling restart of all servers at regular intervals.

This restart is gracefully rolled out by the controller, which monitors pods state and respects the disruption budget for the stateful set.

### `random_reload`

At random intervals, a server is randomly selected, and a configuration reload is triggered (SIGHUP).

### `random_hard_kill`

At random intervals, a server is randomly selected and killed with SIGKILL.

### `slow_network`

Configures traffic shaping rules to simulate network latency between servers

### `lossy_network`

Configures traffic shaping rules to simulate network packet loss between servers

### `none`

Does not cause any mayhem

## Tests
<!--TODO: Add description for what the purpose of a client test workload is doing-->

### `queue-group-consumer`

Tests (explicit) durable queue group with `N` consumer (on separate connections).

The test consists of:

```
for i in M {
  publish (i)
  waitUntilConsumedAndAcked (i)
}
```

At any given moment, there is only 1 message in-flight and should only be consumed by one subscriber. After a message is published the consumer is expected to receive it before publishing the next message.

The actions of publishing and consuming are resilient to transient failures, meaning they are retried until successful.

The test may fail if:
- one of the operations is retried unsuccessfully for too long
- a published message is not consumed within a specified amount of time
- a previously published message is received out of order

### `durable-pull-consumer`

Tests durable consumer on a replicated stream.

The test consists of:

```
for i in N {
  publish (i)
  consume (i)
  verify i
  ack (i)
}
```

At any given moment, there is only 1 message in-flight.
After publishing message `i`, the consumer expects to receive it.

The client is resilient to transient failures. That is, if an operation fails, it will be retried.

The test may fail if:
 - one of the operations is retried unsuccessfully for too long
 - the message received does not match the message published last

### `kv-cas`

Tests consistency on a replicated KeyValue.

The test consists of:

```
for i in N {
  read(k)
  verify k
  update(k)
}
```

A single client is performing all operations, therefore it has a perfect view of each key, value and revision.

The client is resilient to transient failures and will retry as needed.

The test may fail if:
- the value retrieved does not match the value committed last
- an operation keeps failing for too long

### `add-remove-streams`

Test adding and removing replicated streams.

The tests consists of:

```
for i in N {
  one of {
    add stream
    delete stream
    list streams
  }
  verify streams
}
```

A single client is performing all operations and has a perfect view of what the current streams should be.

The client is resilient to transient failures and will retry as needed.

The test may fail if:
- the list of existing streams does not match the expected
- an operation keeps failing for too long

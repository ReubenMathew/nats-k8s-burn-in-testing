# K8s NATS Burn-in Testing 

### Requirements
- `k3d`
- `kubectl`
- `docker`
- `go`

TODO:
- Add running instructions
- update dependency list
- explain folder config

# Tests

## `queue-group-consumer`

Tests (explicit) durable queue group consumer. 

The test consists of

```
for i in N {
  setupQueueSubscriber (i)
}

for j in M {
  publish (i)
  waitUntilConsume (i)
  verify i
  ack (i)
}
```

At any given moment, there is only 1 message in-flight and should only be consumed by one subscriber. After a message is published the consumer is expected to receive it before publishing the next message.

The actions of publishing and consuming are resilient to transient failures, meaning they are retried until successful.

The test may fail if:
- one of the operations is retried unsuccessfully for too long
- a published message is not consumed within a specified amount of time
- a previously published message is received out of order 

## `durable-pull-consumer`

Tests durable consumer on a replicated stream.

The test consists of 

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

## `kv-cas`

Tests consistency on a replicated KeyValue.

The test consists of

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

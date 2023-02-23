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
- create `.gitignore`

# Tests

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


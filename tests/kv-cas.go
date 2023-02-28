package main

import (
	"bytes"
	"fmt"
	"github.com/nats-io/nats.go"
	"log"
	"math/rand"
	"time"
)

func init() {
	registerTest("kv-cas", KVCasTest)
}

func KVCasTest() error {
	const (
		BucketName             = "test-bucket"
		ProgressUpdateInterval = 3 * time.Second
		DefaultRetryTimeout    = 30 * time.Second
		GetRetryTimeout        = DefaultRetryTimeout
		UpdateRetryTimeout     = DefaultRetryTimeout
		RetryDelay             = 1 * time.Second
		Replicas               = 3
		ValuesSize             = 512
	)

	type TestValue struct {
		RoundNumber uint64
		Data        []byte
	}

	log.Printf("Setting up test")
	nc, err := nats.Connect(
		options.ServerURL,
		nats.MaxReconnects(-1),
		nats.DisconnectErrHandler(func(*nats.Conn, error) {
			log.Printf("Disconnected")
		}),
		nats.ReconnectHandler(func(conn *nats.Conn) {
			log.Printf("Reconnected")
		}),
	)
	if err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}

	// Create JetStream Context
	js, err := nc.JetStream()
	if err != nil {
		return fmt.Errorf("failed to init JetStream: %w", err)
	}

	// Create KV bucket
	kv, err := js.CreateKeyValue(&nats.KeyValueConfig{
		Bucket:   BucketName,
		Replicas: Replicas,
		// TODO: mem vs disk storage
	})
	if err != nil {
		return err
	}
	// Delete bucket
	defer func() {
		err := js.DeleteKeyValue(BucketName)
		if err != nil {
			log.Printf("Could not delete bucket %s: %s\n", BucketName, err)
		}
	}()

	keys := []string{"k1", "k2", "k3"}
	expectedValuesMap := make(map[string]*TestValue)
	expectedRevisionsMap := make(map[string]uint64)

	// Initialize keys, generate and store values
	for _, key := range keys {
		value := &TestValue{
			0,
			[]byte{},
		}

		revision, err := kv.Create(key, marshalOrPanic(value))
		if err != nil {
			return err
		}

		expectedValuesMap[key] = value
		expectedRevisionsMap[key] = revision
	}

	progressTicker := time.NewTicker(ProgressUpdateInterval)
	experimentTimer := time.NewTimer(options.TestDuration)
	startTime := time.Now()

runLoop:
	for currentRoundNumber := uint64(0); true; currentRoundNumber++ {

		select {
		case <-progressTicker.C:
			log.Printf(
				"Performed %d CAS updates in %s",
				currentRoundNumber,
				time.Since(startTime).Round(1*time.Second),
			)
			continue runLoop
		case <-experimentTimer.C:
			// Timer expired, test completed
			break runLoop
		default:
			// If neither timers fired, proceed to Get/Update below
		}

		key := keys[rand.Intn(len(keys))]

		// Get a value (with retries)
		var currentKeyValEntry nats.KeyValueEntry
		var currentValue TestValue
		getTimer := time.NewTimer(GetRetryTimeout)

	getRetryLoop:
		for {
			currentKeyValEntry, err = kv.Get(key)
			if err == nil {
				unmarshalOrPanic(currentKeyValEntry.Value(), &currentValue)
				break getRetryLoop
			}

			log.Printf("Get error: %s", err)

			select {
			case <-experimentTimer.C:
				return nil
			case <-getTimer.C:
				return fmt.Errorf("timed out trying to Get (last error: %s)", err)
			case <-time.After(RetryDelay):
				continue getRetryLoop
			}
		}

		// Retrieve expected value and revision
		expectedValue := expectedValuesMap[key]
		expectedRevision := expectedRevisionsMap[key]

		// Check expected and actual
		if expectedRevision != currentKeyValEntry.Revision() {
			return fmt.Errorf(
				"round: %d, key %s, expected revision: %d, actual revision: #%d",
				currentRoundNumber,
				key,
				expectedRevision,
				currentKeyValEntry.Revision(),
			)

		} else if expectedValue.RoundNumber != currentValue.RoundNumber {
			return fmt.Errorf(
				"round: %d, key %s, expected: #%d, got: #%d",
				currentRoundNumber,
				key,
				expectedValue.RoundNumber,
				currentValue.RoundNumber,
			)
		} else if !bytes.Equal(expectedValue.Data, currentValue.Data) {
			return fmt.Errorf(
				"round: %d, key %s, data mismatch",
				currentRoundNumber,
				key,
			)
		}

		// Create new value
		newValue := &TestValue{
			RoundNumber: currentRoundNumber,
			Data:        make([]byte, ValuesSize),
		}
		rand.Read(newValue.Data)

		// Update the key (with retries)
		var newRevision uint64
		updateTimer := time.NewTimer(UpdateRetryTimeout)

	updateRetryLoop:
		for {
			newRevision, err = kv.Update(key, marshalOrPanic(newValue), currentKeyValEntry.Revision())
			if err == nil {
				break updateRetryLoop
			}

			log.Printf("Update error: %s", err)

			select {
			case <-experimentTimer.C:
				return nil
			case <-updateTimer.C:
				return fmt.Errorf("timed out trying to Update (last error: %s)", err)
			case <-time.After(RetryDelay):
				continue updateRetryLoop
			}
		}

		expectedValuesMap[key] = newValue
		expectedRevisionsMap[key] = newRevision
	}

	return nil
}

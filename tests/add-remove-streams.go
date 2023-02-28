package main

import (
	"errors"
	"fmt"
	"github.com/nats-io/nats.go"
	"log"
	"math/rand"
	"reflect"
	"time"
)

func init() {
	registerTest("add-remove-streams", AddRemoveStreamsTest)
}

func AddRemoveStreamsTest() error {
	const (
		StreamNamePrefix       = "test-stream"
		StreamSubjectPrefix    = "test-subject"
		ProgressUpdateInterval = 3 * time.Second
		OperationTimeout       = 30 * time.Second
		RetryDelay             = 1 * time.Second
		Replicas               = 3
		MinimumStreams         = 1
		MaximumStreams         = 10
	)

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

	progressTicker := time.NewTicker(ProgressUpdateInterval)
	experimentTimer := time.NewTimer(options.TestDuration)
	startTime := time.Now()

	log.Printf("Starting test (running for %s or until error)", options.TestDuration)

	// Track various sequence numbers for debugging
	currentRoundNumber := uint64(0)
	//lastPublishedSequence := uint64(0)
	//lastReceivedSequence := nats.SequencePair{}
	//lastAckedSequence := nats.SequencePair{}
	createdStreams, deletedStreams := 0, 0

	defer func() {
		log.Printf("---")
		log.Printf("Current round number number: %d", currentRoundNumber)
		log.Printf("---")
	}()

	type Op int

	const ListStreams Op = 0
	const CreateStream Op = 1
	const DeleteStream Op = 2

	// Names of the streams currently expected to exist
	// Values in this map are not used, i.e. it is just a set of stream names.
	expectedStreamsMap := map[string]bool{}

	// Cleanup created streams (best effort, may fail)
	defer func() {
		for name, _ := range expectedStreamsMap {
			err := js.DeleteStream(name)
			if err != nil {
				log.Printf("Failed to delete stream: %s: %s", name, err)
			}
		}
	}()

runLoop:
	for currentRoundNumber = uint64(1); true; currentRoundNumber++ {

		select {
		case <-progressTicker.C:
			log.Printf(
				"Created %d streams, deleted %d streams in %s",
				createdStreams,
				deletedStreams,
				time.Since(startTime).Round(1*time.Second),
			)
			continue runLoop
		case <-experimentTimer.C:
			// Timer expired, test completed
			break runLoop
		default:
			// If neither timers fired, proceed to create or delete below
		}

		nextOperation := ListStreams

		if len(expectedStreamsMap) <= MinimumStreams {
			nextOperation = CreateStream
		} else if len(expectedStreamsMap) >= MaximumStreams {
			nextOperation = DeleteStream
		} else {
			nextOperation = Op(rand.Intn(3))
		}

		t := time.NewTimer(OperationTimeout)

		switch nextOperation {
		case CreateStream:
			// Create a config for stream with unique name and subject
			streamName := fmt.Sprintf("%s-%d", StreamNamePrefix, currentRoundNumber)
			streamSubject := fmt.Sprintf("%s-%s", StreamSubjectPrefix, streamName)
			streamConfig := &nats.StreamConfig{
				Name:     streamName,
				Subjects: []string{streamSubject},
				Replicas: Replicas,
			}

		createRetryLoop:
			for {
				// Create the stream
				_, err := js.AddStream(streamConfig)
				if err == nil {
					// Stream created successfully
					expectedStreamsMap[streamName] = true
					createdStreams += 1
					break createRetryLoop
				}

				log.Printf("Stream creation error: %s", err)

				select {
				case <-experimentTimer.C:
					return nil
				case <-t.C:
					return fmt.Errorf("timed out trying to create stream (last error: %s)", err)
				case <-time.After(RetryDelay):
					continue createRetryLoop
				}
			}

		case DeleteStream:
			// Choose a random stream among the ones expected to currently exist
			i, streamIndex := 0, rand.Intn(len(expectedStreamsMap))
			streamName := ""

			for name, _ := range expectedStreamsMap {
				if i == streamIndex {
					streamName = name
					break
				}
				i += 1
			}

			if streamName == "" {
				panic("Bug in random stream selection")
			}

			isFirstAttempt := true
		deleteRetryLoop:
			for {
				// Delete the stream
				err := js.DeleteStream(streamName)
				if err == nil ||
					// A previous attempt may have returned error or timeout, while actually successful
					(!isFirstAttempt && errors.Is(nats.ErrStreamNotFound, err)) {
					delete(expectedStreamsMap, streamName)
					deletedStreams += 1
					break deleteRetryLoop
				}

				log.Printf("Stream deletion error: %s", err)

				select {
				case <-experimentTimer.C:
					return nil
				case <-t.C:
					return fmt.Errorf("timed out trying to delete stream (last error: %s)", err)
				case <-time.After(RetryDelay):
					isFirstAttempt = false
					continue deleteRetryLoop
				}
			}

		case ListStreams:
			// Get the list of streams and compare to the expected
			namesCh := js.StreamNames()
			currentStreamsMap := map[string]bool{}

			// Consume all names from the channel
			// TODO can this block?
			for name := range namesCh {
				currentStreamsMap[name] = true
			}

			if len(currentStreamsMap) != len(expectedStreamsMap) {
				return fmt.Errorf(
					"expected %d streams, but got a list of: %d instead",
					len(expectedStreamsMap),
					len(currentStreamsMap),
				)
			}

			if !reflect.DeepEqual(currentStreamsMap, expectedStreamsMap) {
				return fmt.Errorf(
					"expected streams: %v, actual: %v",
					expectedStreamsMap,
					currentStreamsMap,
				)
			}
		}
	}
	return nil
}

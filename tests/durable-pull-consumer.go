package main

import (
	"encoding/json"
	"fmt"
	"github.com/nats-io/nats.go"
	"log"
	"time"
)

func init() {
	registerTest("durable-pull-consumer", DurablePullConsumerTest)
}

func DurablePullConsumerTest() error {
	const (
		StreamName             = "test-stream"
		StreamSubject          = "test-subject"
		ConsumerName           = "ConsumerName"
		ProgressUpdateInterval = 3 * time.Second
		DefaultRetryTimeout    = 30 * time.Second
		PublishRetryTimeout    = DefaultRetryTimeout
		ConsumeRetryTimeout    = DefaultRetryTimeout
		AckRetryTimeout        = DefaultRetryTimeout
		RetryDelay             = 1 * time.Second
		Replicas               = 3
		ConsumerReplicas       = 3
	)

	type TestMessage struct {
		// In each test iteration a message is published, consumed and acked
		RoundNumber uint64
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

	// Create JetStream Stream
	_, err = js.AddStream(&nats.StreamConfig{
		Name:     StreamName,
		Subjects: []string{StreamSubject},
		Replicas: Replicas,
		//TODO may add other options, e.g.: Mem vs. Disk storage
	})
	if err != nil {
		return fmt.Errorf("failed to create stream: %w", err)
	}
	// Delete stream
	defer func() {
		err := js.DeleteStream(StreamName)
		if err != nil {
			log.Printf("Could not delete stream %s. %v\n", StreamName, err)
		}
	}()

	_, err = js.AddConsumer(
		StreamName,
		&nats.ConsumerConfig{
			Durable:    ConsumerName,
			Replicas:   ConsumerReplicas,
			AckWait:    2 * AckRetryTimeout, // Test times out before re-delivery kicks in
			MaxDeliver: 0,                   // Disable re-delivery
		},
	)
	if err != nil {
		return fmt.Errorf("failed to create consumer: %w", err)
	}
	// Delete consumer
	defer func() {
		err := js.DeleteConsumer(StreamName, ConsumerName)
		if err != nil {
			return
		}
	}()

	// Durable synchronous consumer
	sub, err := js.PullSubscribe(
		"",
		"",
		nats.Bind(StreamName, ConsumerName),
	)
	if err != nil {
		return fmt.Errorf("failed to subscribe: %w", err)
	}
	// Unsubscribe
	defer func(sub *nats.Subscription) {
		err := sub.Unsubscribe()
		if err != nil {
			log.Printf("Error unsubscribing: %s", err)
		}
	}(sub)

	progressTicker := time.NewTicker(ProgressUpdateInterval)
	experimentTimer := time.NewTimer(options.TestDuration)
	startTime := time.Now()

	log.Printf("Starting test (running for %s or until error)", options.TestDuration)

	// Track various sequence numbers for debugging
	currentRoundNumber := uint64(0)
	lastPublishedSequence := uint64(0)
	lastReceivedSequence := nats.SequencePair{}
	lastAckedSequence := nats.SequencePair{}

	defer func() {
		log.Printf("---")
		log.Printf("Current round number number: %d", currentRoundNumber)
		log.Printf("Last published message stream seq: %d", lastPublishedSequence)
		log.Printf("Last consumed message seq: %+v", lastReceivedSequence)
		log.Printf("Last ACKed message seq: %+v", lastAckedSequence)
		log.Printf("---")
	}()

runLoop:
	for currentRoundNumber = uint64(1); true; currentRoundNumber++ {

		select {
		case <-progressTicker.C:
			log.Printf(
				"Sent and received %d messages in %s",
				currentRoundNumber,
				time.Since(startTime).Round(1*time.Second),
			)
			continue runLoop
		case <-experimentTimer.C:
			// Timer expired, test completed
			break runLoop
		default:
			// If neither timers fired, proceed to send/receive/ack below
		}

		// Create a message, it contains the currentRoundNumber
		msg := nats.NewMsg(StreamSubject)
		data, err := json.Marshal(&TestMessage{
			RoundNumber: currentRoundNumber,
		})
		if err != nil {
			return err
		}
		msg.Data = data

		// Publish the message (with retries in case of error)
		publishTimer := time.NewTimer(PublishRetryTimeout)
		var pubAck *nats.PubAck

	publishRetryLoop:
		for {
			pubAck, err = js.PublishMsg(msg)
			if err == nil {
				break publishRetryLoop
			}

			log.Printf("Publish error: %s", err)

			select {
			case <-experimentTimer.C:
				return nil
			case <-publishTimer.C:
				return fmt.Errorf("timed out trying to publish (last error: %s)", err)
			case <-time.After(RetryDelay):
				continue publishRetryLoop
			}
		}

		if pubAck.Sequence != lastPublishedSequence+1 {
			log.Printf(
				"⚠️ Published sequence expected: %d actual: %d (duplicate? %v)",
				lastPublishedSequence+1,
				pubAck.Sequence,
				pubAck.Duplicate,
			)
		}
		lastPublishedSequence = pubAck.Sequence

		// Consume (expecting to receive the message just published)
		var nextMsg *nats.Msg
		consumeTimer := time.NewTimer(ConsumeRetryTimeout)

	consumeRetryLoop:
		for {
			messages, err := sub.Fetch(1)
			if err == nil {
				nextMsg = messages[0]
				break consumeRetryLoop
			}

			log.Printf("NextMsg error: %s", err)

			select {
			case <-experimentTimer.C:
				return nil
			case <-consumeTimer.C:
				return fmt.Errorf("timed out trying to consume (last error: %s)", err)
			case <-time.After(RetryDelay):
				continue consumeRetryLoop
			}
		}

		// Check the message just received contains currentRoundNumber
		received := &TestMessage{}
		err = json.Unmarshal(nextMsg.Data, received)
		if err != nil {
			return err
		}
		msgMetadata, err := nextMsg.Metadata()
		if err != nil {
			return fmt.Errorf("failed to get message metadata: %w", err)
		}

		if msgMetadata.Sequence.Stream != lastReceivedSequence.Stream+1 {
			log.Printf("⚠️ Stream sequence expected: %d, actual: %d", lastReceivedSequence.Stream+1, msgMetadata.Sequence.Stream)
		}

		if msgMetadata.Sequence.Stream != lastReceivedSequence.Consumer+1 {
			log.Printf("⚠️ Consumer sequence expected: %d, actual: %d", lastReceivedSequence.Consumer+1, msgMetadata.Sequence.Consumer)
		}

		if received.RoundNumber != currentRoundNumber {
			// Fail the test
			return fmt.Errorf(
				"expected message #%d (s:%d, c=%d), but received #%d (s:%d, c=%d)",
				currentRoundNumber,
				lastReceivedSequence.Stream+1,
				lastReceivedSequence.Consumer+1,
				received.RoundNumber,
				msgMetadata.Sequence.Stream,
				msgMetadata.Sequence.Consumer,
			)
		}

		lastReceivedSequence = msgMetadata.Sequence

		// Ack the message just consumed (with retries)
		ackTimer := time.NewTimer(AckRetryTimeout)

	ackRetryLoop:
		for {
			err := nextMsg.AckSync()
			if err == nil {
				break ackRetryLoop
			}

			log.Printf("Ack error: %s", err)

			select {
			case <-experimentTimer.C:
				return nil
			case <-ackTimer.C:
				return fmt.Errorf("timed out trying to ack (last error: %s)", err)
			case <-time.After(RetryDelay):
				continue ackRetryLoop
			}
		}

		lastAckedSequence = msgMetadata.Sequence
	}
	return nil
}

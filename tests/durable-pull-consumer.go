package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"github.com/nats-io/nats.go"
	"log"
	"os"
	"time"
)

var options struct {
	TestDuration time.Duration
	ServerURL    string
}

const (
	StreamName             = "test-stream"
	StreamSubject          = "test-subject"
	ProgressUpdateInterval = 3 * time.Second
	FetchMessageTimeout    = 1 * time.Second
	DefaultRetryTimeout    = 30 * time.Second
	PublishRetryTimeout    = DefaultRetryTimeout
	ConsumeRetryTimeout    = DefaultRetryTimeout
	AckRetryTimeout        = DefaultRetryTimeout
	RetryDelay             = 1 * time.Second
	Replicas               = 3
)

func main() {
	flag.DurationVar(&options.TestDuration, "duration", 60*time.Second, "How long to run")
	flag.StringVar(&options.ServerURL, "server", nats.DefaultURL, "Server URL")
	flag.Parse()

	err := run()
	if err != nil {
		log.Printf("Test failed: %s", err)
		os.Exit(1)
	}
	log.Printf("Test completed")
}

type TestMessage struct {
	MessageId int
}

const ConsumerName = "ConsumerName"

const ConsumerReplicas = Replicas

func run() error {
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
			Durable:  ConsumerName,
			Replicas: ConsumerReplicas,
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
	sub, err := js.PullSubscribe("", "", nats.Bind(StreamName, ConsumerName))
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

runLoop:
	for i := 0; true; i++ {
		select {
		case <-progressTicker.C:
			log.Printf(
				"Sent and received %d messages in %s",
				i,
				time.Since(startTime).Round(1*time.Second),
			)
			continue runLoop
		case <-experimentTimer.C:
			// Timer expired, test completed
			return nil
		default:
			// Continue below
		}

		msg := nats.NewMsg(StreamSubject)
		data, err := json.Marshal(&TestMessage{
			MessageId: i,
		})
		if err != nil {
			return err
		}
		msg.Data = data

		publishTimer := time.NewTimer(PublishRetryTimeout)

	publishRetryLoop:
		for {
			_, err := js.PublishMsg(msg)
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
				// Try again
			}
		}

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
				// Try again
			}
		}

		received := &TestMessage{}
		err = json.Unmarshal(nextMsg.Data, received)
		if err != nil {
			return err
		}

		if received.MessageId != i {
			return fmt.Errorf("expected message %d, but received %d", i, received.MessageId)
		}

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
				// Try again
			}
		}
	}
	return nil
}

package main

import (
	"fmt"
	"log"
	"time"

	"github.com/nats-io/nats.go"
)

func init() {
	registerTest("queue-group-consumer", QueuePullConsumerTest)
}

func QueuePullConsumerTest() error {
	const (
		DeliverGroupName       = "test-group"
		DeliverSubjectName     = "test-deliver-subject"
		StreamName             = "test-stream"
		StreamSubject          = "test-subject"
		ProgressUpdateInterval = 3 * time.Second
		DefaultRetryTimeout    = 30 * time.Second
		PublishRetryTimeout    = DefaultRetryTimeout
		AckRetryTimeout        = DefaultRetryTimeout
		ConsumeTimeout         = DefaultRetryTimeout
		RetryDelay             = 1 * time.Second
		Replicas               = 3
		ConsumerName           = "ConsumerName"
		ConsumerReplicas       = Replicas
		SubscriberCount        = 10
	)

	type Message struct {
		SubscriberID string
		SeqNumber    int
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
	defer nc.Close()

	// Create JetStream Context
	js, err := nc.JetStream()
	if err != nil {
		return fmt.Errorf("failed to init JetStream: %w", err)
	}

	// Create JetStream stream
	_, err = js.AddStream(&nats.StreamConfig{
		Name:     StreamName,
		Subjects: []string{StreamSubject},
		Replicas: Replicas,
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

	// Create explicit durable queue consumer
	_, err = js.AddConsumer(
		StreamName,
		&nats.ConsumerConfig{
			Durable:        ConsumerName,
			DeliverSubject: DeliverSubjectName,
			DeliverGroup:   DeliverGroupName,
			AckPolicy:      nats.AckExplicitPolicy,
			Replicas:       ConsumerReplicas,
			AckWait:        2 * AckRetryTimeout, // Test fails before re-delivery kicks in
			MaxDeliver:     0,                   // Disable re-delivery
		},
	)
	if err != nil {
		return fmt.Errorf("failed to create consumer: %w", err)
	}
	// Delete consumer
	defer func() {
		err := js.DeleteConsumer(StreamName, ConsumerName)
		if err != nil {
			log.Printf("failed to delete consumer: %w", err)
		}
	}()

	consumerConns := []*nats.Conn{}
	consumerSubs := []*nats.Subscription{}
	messagesCh := make(chan Message)
	consumerErrorCh := make(chan error, SubscriberCount)

	// Cleanup subscribers
	defer func() {
		for _, sub := range consumerSubs {
			_ = sub.Unsubscribe()
		}
		for _, conn := range consumerConns {
			conn.Close()
		}
	}()
	for i := 0; i < SubscriberCount; i++ {
		subID := fmt.Sprintf("Subscriber-%d", i)
		conn, err := nats.Connect(
			options.ServerURL,
			nats.MaxReconnects(-1),
			nats.DisconnectErrHandler(func(*nats.Conn, error) {
				log.Printf("[%s] Disconnected", subID)
			}),
			nats.ReconnectHandler(func(conn *nats.Conn) {
				log.Printf("[%s] Reconnected", subID)
			}),
		)
		if err != nil {
			return fmt.Errorf("failed to connect: %s", err)
		}

		consumerConns = append(consumerConns, conn)

		sub, err := nc.QueueSubscribe(DeliverSubjectName, DeliverGroupName, func(msg *nats.Msg) {
			ackTimer := time.NewTimer(AckRetryTimeout)
		ackRetryLoop:
			for {
				err := msg.AckSync()
				if err == nil {
					break ackRetryLoop
				}

				log.Printf("Ack error: %s", err)

				select {
				case <-ackTimer.C:
					consumerErrorCh <- fmt.Errorf("timeout trying to ack: %s", err)
				case <-time.After(RetryDelay):
					// Try again
				}
			}

			var recvMsg Message
			unmarshalOrPanic(msg.Data, &recvMsg)
			recvMsg.SubscriberID = subID
			messagesCh <- recvMsg
		})

		consumerSubs = append(consumerSubs, sub)
	}
	log.Printf("Created %d subscribers for group %s", SubscriberCount, DeliverGroupName)

	progressTicker := time.NewTicker(ProgressUpdateInterval)
	experimentTimer := time.NewTimer(options.TestDuration)

	startTime := time.Now()

	log.Printf("Starting test (running for %s or until error)", options.TestDuration)

mainRunLoop:
	for seqNumber := 1; true; seqNumber++ {
		select {
		case <-progressTicker.C:
			log.Printf("Sent and received %d messages in %s\n", seqNumber-1, time.Since(startTime).Round(1*time.Second))
			continue mainRunLoop
		case <-experimentTimer.C:
			return nil
		default:
			// continue below with publish and wait for delivery
		}

		msg := nats.NewMsg(StreamSubject)
		data := marshalOrPanic(&Message{
			SubscriberID: "",
			SeqNumber:    seqNumber,
		})
		msg.Data = data
		msg.Subject = StreamSubject

		publishTimer := time.NewTimer(PublishRetryTimeout)

	publishRetryLoop:
		for {
			_, err = js.PublishMsg(msg)
			if err == nil {
				break publishRetryLoop
			}
			select {
			case <-experimentTimer.C:
				return nil
			case <-publishTimer.C:
				return fmt.Errorf("timed out trying to publish %w", err)
			case <-time.After(RetryDelay):
				// retry publish
			}
		}

		// Wait until one of the subscribers delivers message via channel
		consumeTimer := time.NewTimer(ConsumeTimeout)
		select {
		case nextMessage := <-messagesCh:
			if nextMessage.SeqNumber != seqNumber {
				return fmt.Errorf(
					"expected %d but received %d from %s",
					seqNumber,
					nextMessage.SeqNumber,
					nextMessage.SubscriberID,
				)
			}
		case consumerError := <-consumerErrorCh:
			return fmt.Errorf("consumer fatal error: %s", consumerError)
		case <-experimentTimer.C:
			return nil
		case <-consumeTimer.C:
			return fmt.Errorf("timed out waitinf for message %d", seqNumber)
		}
	}
	return nil
}

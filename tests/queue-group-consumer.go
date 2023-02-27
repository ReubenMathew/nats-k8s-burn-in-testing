package main

import (
	"fmt"
	"log"
	"time"

	"github.com/nats-io/nats.go"
)

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

	// Explicit durable queue consumer
	_, err = js.AddConsumer(
		StreamName,
		&nats.ConsumerConfig{
			Durable:        ConsumerName,
			DeliverSubject: DeliverSubjectName,
			DeliverGroup:   DeliverGroupName,
			AckPolicy:      nats.AckExplicitPolicy,
			Replicas:       ConsumerReplicas,
		},
	)
	if err != nil {
		return fmt.Errorf("failed to create consumer: %w", err)
	}
	// Delete consumer
	defer func() error {
		err := js.DeleteConsumer(StreamName, ConsumerName)
		if err != nil {
			return fmt.Errorf("failed to delete consumer: %w", err)
		}
		return nil
	}()

	content := make(chan Message)
	progressTicker := time.NewTicker(ProgressUpdateInterval)
	experimentTimer := time.NewTimer(options.TestDuration)

	for i := 0; i < SubscriberCount; i++ {
		subscriberID := fmt.Sprintf("Subscriber-%d", i)
		go func(id int) {
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
				log.Fatalf("failed to connect: %v", err)
			}

			_, err = nc.QueueSubscribe(DeliverSubjectName, DeliverGroupName, func(msg *nats.Msg) {
				ackTimer := time.NewTimer(AckRetryTimeout)
			ackRetryLoop:
				for {
					err := msg.AckSync()
					if err == nil {
						break ackRetryLoop
					}

					log.Printf("Ack error: %s", err)

					select {
					case <-experimentTimer.C:
						return
					case <-ackTimer.C:
						log.Fatalf("timed out trying to ack (last error: %s)", err)
					case <-time.After(RetryDelay):
						// Try again
					}
				}

				var recvMsg Message
				unmarshalOrPanic(msg.Data, &recvMsg)
				recvMsg.SubscriberID = subscriberID
				content <- recvMsg
				log.Printf("Received #%d by %s", recvMsg.SeqNumber, subscriberID)
			})

			if err != nil {
				log.Printf("Could not initialize QueueSubscriber-%d %v\n", id, err)
			}
		}(i)
	}
	log.Printf("Created %d subscribers to the delivery group\n", SubscriberCount)

	var seqNumber = 1

mainRunLoop:
	for {
		select {
		case <-progressTicker.C:
			continue mainRunLoop
		case <-experimentTimer.C:
			return nil
		default:
			// publish
			publishTimer := time.NewTimer(PublishRetryTimeout)
		publishRetryLoop:
			for {
				msg := nats.NewMsg(StreamSubject)
				data := marshalOrPanic(&Message{
					SubscriberID: "",
					SeqNumber:    seqNumber,
				})
				msg.Data = data
				msg.Subject = StreamSubject

				_, err = js.PublishMsg(msg)
				if err == nil {
					log.Printf("Published #%d\n", seqNumber)
					seqNumber++
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

			// block until message has been consumed or a timer has expired
			prevSeqNumber := seqNumber - 1
			consumeTimer := time.NewTimer(ConsumeTimeout)
			select {
			case currentData := <-content:
				if currentData.SeqNumber != prevSeqNumber {
					return fmt.Errorf("Expected %d but received %d by %s", prevSeqNumber, currentData.SeqNumber, currentData.SubscriberID)
				}
			case <-experimentTimer.C:
				return fmt.Errorf("Experiment timed before receiving expected message with sequence number: %d", prevSeqNumber)
			case <-consumeTimer.C:
				return fmt.Errorf("Timed out expecting message with sequence number: %d", prevSeqNumber)
			}
		}
	}
}

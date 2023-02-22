package clients

import (
	"fmt"
	"log"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/schollz/progressbar/v3"
)

type BenchDurablePullConsumer struct {
	ClientName string
}

const (
	PUBLISH_TIMEOUT  = time.Second * 30
	CONSUME_TIMEOUT  = time.Second * 30
	RETRY_DURATION   = time.Millisecond * 100
	MSG_COUNT        = 100000
	MAX_STREAM_BYTES = 1024
	MAX_RECONNECTS   = 100
	NATS_URL         = nats.DefaultURL
	STREAM_NAME      = "PROBE"
	CONSUMER_NAME    = "MONITOR"
	STREAM_SUBJECT   = "probe"
)

var (
	total_rtt           int    = 0
	prevConsumerSeqNum  uint64 = 0
	prevStreamMsgSeqNum uint64 = 0
)

func (b *BenchDurablePullConsumer) Run() {
	fmt.Printf("Running: %s\n", b.ClientName)
	defer fmt.Printf("Completed: %s\n", b.ClientName)
	nc, err := nats.Connect(NATS_URL, nats.MaxReconnects(MAX_RECONNECTS), nats.ReconnectWait(RETRY_DURATION))
	if err != nil {
		log.Fatalln("NATS connection error", err)
	}

	// Create JetStream Context
	js, err := nc.JetStream(nats.PublishAsyncMaxPending(256))
	if err != nil {
		log.Fatalln("JetStream initialization error", err)
	}

	// Create JetStream Stream
	_, err = js.AddStream(&nats.StreamConfig{
		Name:     STREAM_NAME,
		Subjects: []string{STREAM_SUBJECT},
		Discard:  nats.DiscardOld,
	})
	if err != nil {
		log.Fatalf("Error creating stream %s. %v\n", STREAM_NAME, err)
	}
	defer func() {
		err := js.DeleteStream(STREAM_NAME)
		if err != nil {
			log.Printf("Could not delete stream %s. %v\n", STREAM_NAME, err)
		}
	}()

	// Create a durable consumer
	_, err = js.AddConsumer(STREAM_NAME, &nats.ConsumerConfig{
		Durable: CONSUMER_NAME,
	})
	if err != nil {
		log.Printf("Error creating durable consumer %s for %s. %v\n", CONSUMER_NAME, STREAM_NAME, err)
	}
	defer func() {
		err := js.DeleteConsumer(STREAM_NAME, CONSUMER_NAME)
		if err != nil {
			log.Printf("Error deleting durable consumer %s for stream %s. %v\n", CONSUMER_NAME, STREAM_NAME, err)
		}
	}()

	// Simple Pull Consumer
	sub, err := js.PullSubscribe(STREAM_SUBJECT, CONSUMER_NAME)
	// Unsubscribe
	defer sub.Unsubscribe()
	// Drain
	defer sub.Drain()
	if err != nil {
		log.Fatalln(err)
	}

	// Stream publish and consume
	bar := progressbar.Default(MSG_COUNT, "Messages:")
	for i := 0; i < MSG_COUNT; i++ {
		start := time.Now()

		publishNext(js)
		consumeNext(sub)

		rtt := time.Since(start)
		total_rtt += int(rtt.Microseconds())
		bar.Add(1)
	}
	fmt.Printf("(Stats) JetStream Pull Durable Consumer Average RTT: %dµs\n", total_rtt/MSG_COUNT)

}

func publishNext(js nats.JetStreamContext) {
	timer := time.NewTimer(PUBLISH_TIMEOUT)
	for {
		_, err := js.Publish(STREAM_SUBJECT, []byte(fmt.Sprintf("ping")))
		if err == nil {
			// no error in publishing message
			break
		}
		select {
		case <-timer.C:
			log.Fatalln("Failed to publish message before timeout")
			return
		case <-time.After(time.Second):
			time.Sleep(RETRY_DURATION)
		}
	}
}

func consumeNext(sub *nats.Subscription) {
	timer := time.NewTimer(CONSUME_TIMEOUT)
	var msg *nats.Msg
	for {
		msgs, err := sub.Fetch(1)
		if err == nil {
			// no error in consuming message
			msg = msgs[0]
			break
		}
		select {
		case <-timer.C:
			log.Fatalln("Failed to consume message before timeout")
			return
		case <-time.After(time.Second):
			time.Sleep(RETRY_DURATION)
		}
	}
	validateSeq(msg)
}

func validateSeq(msg *nats.Msg) {
	metadata, err := msg.Metadata()
	if err != nil {
		log.Println("Unable to get message metadata for", msg)
	}
	currConsumerSeqNum := metadata.Sequence.Consumer
	currStreamMsgSeqNum := metadata.Sequence.Stream

	if currConsumerSeqNum != prevConsumerSeqNum+1 {
		log.Fatalf("Current consumer sequence number (%d) is not incrementally greater than 1 to the previously logged sequence number (%d)", currConsumerSeqNum, prevConsumerSeqNum)
	}
	if currStreamMsgSeqNum != prevStreamMsgSeqNum+1 {
		log.Fatalf("Current stream message sequence number (%d) is not incrementally greater than 1 to the previously logged sequence number (%d)", currStreamMsgSeqNum, prevStreamMsgSeqNum)
	}

	prevConsumerSeqNum = currConsumerSeqNum
	prevStreamMsgSeqNum = currStreamMsgSeqNum
	msg.Ack()
}

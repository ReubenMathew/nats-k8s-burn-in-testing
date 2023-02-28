package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/nats-io/nats.go"
)

var options struct {
	TestDuration time.Duration
	ServerURL    string
	TestName     string
	Wipe         bool
}

func main() {

	flag.DurationVar(&options.TestDuration, "duration", 60*time.Second, "How long to run")
	flag.StringVar(&options.ServerURL, "server", nats.DefaultURL, "Server URL")
	flag.StringVar(&options.TestName, "test", "", "name of test")
	flag.BoolVar(&options.Wipe, "wipe", false, "Delete all resources before starting test")
	flag.Parse()

	log.Printf("Launching test: %s", options.TestName)

	if options.Wipe {
		err := wipe()
		if err != nil {
			log.Printf("Failed to wipe before testing: %s", err)
			os.Exit(1)
		}
	}

	var err error
	switch options.TestName {
	case "durable-pull-consumer":
		err = DurablePullConsumerTest()
	case "kv-cas":
		err = KVCas()
	case "queue-group-consumer":
		err = QueuePullConsumerTest()
	case "add-remove-streams":
		err = AddRemoveStreamsTest()
	default:
		err = fmt.Errorf("invalid test: '%s'", options.TestName)
	}

	if err != nil {
		log.Printf("Test %s failed: %s", options.TestName, err)
		os.Exit(1)
	}

	log.Printf("Test %s completed", options.TestName)
}

package main

import (
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
	TestName     string
}

func main() {

	flag.DurationVar(&options.TestDuration, "duration", 60*time.Second, "How long to run")
	flag.StringVar(&options.ServerURL, "server", nats.DefaultURL, "Server URL")
	flag.StringVar(&options.TestName, "test", "", "name of test")
	flag.Parse()

	log.Printf("Launching test: %s", options.TestName)

	var err error
	switch options.TestName {
	case "durable-pull-consumer":
		err = DurablePullConsumerTest()
	case "kv-cas":
		err = KVCas()
	default:
		err = fmt.Errorf("invalid test: '%s'", options.TestName)
	}

	if err != nil {
		log.Printf("Test %s failed: %s", options.TestName, err)
		os.Exit(1)
	}

	log.Printf("Test %s completed", options.TestName)
}

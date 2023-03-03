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
	TestDuration  time.Duration
	ServerURL     string
	TestName      string
	Wipe          bool
	SkipCleanup   bool
	CleanupFailed bool
}

var testsMap map[string]func() error

func registerTest(testName string, testFunc func() error) {
	if testsMap == nil {
		testsMap = make(map[string]func() error)
	}
	testsMap[testName] = testFunc
}

func main() {

	flag.DurationVar(&options.TestDuration, "duration", 60*time.Second, "How long to run")
	flag.StringVar(&options.ServerURL, "server", nats.DefaultURL, "Server URL")
	flag.StringVar(&options.TestName, "test", "", "name of test")
	flag.BoolVar(&options.Wipe, "wipe", false, "Delete all resources before starting test")
	flag.BoolVar(&options.SkipCleanup, "no-cleanup", false, "Skip deleting all resources after successful test")
	flag.BoolVar(&options.CleanupFailed, "cleanup-failed", false, "Delete all resources after a failed test")
	flag.Parse()

	log.Printf("Launching test: %s", options.TestName)

	// Wipe before test
	if options.Wipe {
		err := wipe()
		if err != nil {
			log.Printf("Failed to wipe before testing: %s", err)
			os.Exit(1)
		}
	}

	testFunc, found := testsMap[options.TestName]

	var err error
	if !found {
		err = fmt.Errorf("invalid test: '%s'", options.TestName)
	} else {
		err = testFunc()
	}

	if err != nil {
		log.Printf("Test %s failed: %s", options.TestName, err)
		if options.CleanupFailed {
			err := wipe()
			if err != nil {
				log.Printf("Failed to wipe after failed testing: %s", err)
			}
		}
		os.Exit(1)
	}

	// Wipe after successful test
	if !options.SkipCleanup {
		err := wipe()
		if err != nil {
			log.Printf("Failed to wipe after successful testing: %s", err)
		}
	}

	log.Printf("Test %s completed", options.TestName)
}

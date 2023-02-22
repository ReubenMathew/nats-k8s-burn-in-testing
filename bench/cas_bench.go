package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
)

type Element struct {
	Owner string `json:"owner"`
	Value int    `json:"value"`
}

const KEY string = "MONITOR"

const (
	MAX_VALUE     int = 100000
	PROCESS_COUNT int = 1000
)

var (
	wg               sync.WaitGroup
	processStartWg   sync.WaitGroup
	casFailsMapMutex sync.RWMutex
	casFails         map[string]int
)

func main() {
	log.SetOutput(ioutil.Discard)
	casFails := make(map[string]int)

	servers := []string{"nats://127.0.0.1:4222"}
	nc, err := nats.Connect(strings.Join(servers, ","))

	if err != nil {
		log.Fatalf("NATS Connection Error: %s\n", err)
	}

	js, err := nc.JetStream()
	if err != nil {
		log.Fatalf("JetStream Initialization Error: %s", err)
	}

	kv_config := &nats.KeyValueConfig{
		Bucket: "store",
	}

	kv, err := js.CreateKeyValue(kv_config)
	if err != nil {
		log.Fatalf("Error initializating KV bucket: %s, %s", kv_config.Bucket, err)
	}
	defer js.DeleteKeyValue(kv_config.Bucket)

	// initial value
	initialValue := &Element{
		Owner: "InitialOwner",
		Value: 1,
	}
	kv.Create(KEY, encode(initialValue))

	// even start for N number of threads
	processStartWg.Add(1)

	for processId := 0; processId < PROCESS_COUNT; processId++ {
		wg.Add(1)
		go func(processId int) {
			defer wg.Done()

			processName := fmt.Sprintf("%d", processId)
			casFailureCount := 0
			defer func() {
				casFailsMapMutex.Lock()
				casFails[processName] += casFailureCount
				casFailsMapMutex.Unlock()
			}()

			// initialize cas failure map entry
			casFailsMapMutex.Lock()
			casFails[processName] = 0
			casFailsMapMutex.Unlock()

			processNC, err := nats.Connect("localhost")
			if err != nil {
				log.Printf("Unable to create nats connection for Process ID: %d. %v\n", processId, err)
			}
			processJS, err := processNC.JetStream()
			if err != nil {
				log.Printf("Unable to retrieve JetStream context for Process ID: %d. %v\n", processId, err)
			}
			processKV, err := processJS.KeyValue("store")
			if err != nil {
				log.Printf("Unable to bind to KV: store for Process ID: %d. %v\n", processId, err)
			}

			// Don't start thread actions until all expected threads have been initialized
			processStartWg.Wait()

			timer := time.NewTimer(1 * time.Minute)
			ticker := time.NewTicker(2 * time.Second)

			for {
				select {
				case <-timer.C:
					return
				case <-ticker.C:
					// print stats
				default:
					// attempt compare-and-swap
					prevValue, err := processKV.Get(KEY)
					prevValueElement := decode(prevValue.Value())
					// terminate thread upon reaching max value and decrement WaitGroup counter by 1
					if prevValueElement.Value >= MAX_VALUE {
						return
					}
					revision, err := processKV.Update(KEY, encode(&Element{
						Owner: processName,
						Value: prevValueElement.Value + 1,
					}), prevValue.Revision())

					if err != nil {
						log.Printf("%s could not perform CAS. %v\n", processName, err)
						casFailureCount++
					} else {
						log.Printf("Revision #%d created by %s", revision, processName)
					}
				}
			}
		}(processId)
	}
	processStartWg.Done()

	// block until a thread reaches max value
	wg.Wait()

	// Dump CSV/TSV at end of execution
	//file, err := os.Create("data.tsv")
	file := os.Stdout
	if err != nil {
		log.Fatalf("failed creating file: %s\n", err)
	}
	fmt.Fprintf(file, "%s\t%s\n", "Process ID", "Failures")
	for k, v := range casFails {
		fmt.Fprintf(file, "%s\t%d\n", k, v)
	}
	file.Close()
}

func encode(mutation *Element) []byte {
	data, _ := json.Marshal(mutation)
	return data
}

func decode(byteArray []byte) Element {
	var decodedData Element
	json.Unmarshal(byteArray, &decodedData)
	return decodedData
}

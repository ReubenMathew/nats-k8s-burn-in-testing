package clients

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/schollz/progressbar/v3"
)

type BenchKVCas struct {
	ClientName string
}

type element struct {
	Owner string `json:"owner"`
	Value int    `json:"value"`
}

const KEY string = "MONITOR"

const (
	CLIENT_NAME   string = "Key-Value Compare-and-Swap Load Test"
	MAX_VALUE     int    = 10000
	PROCESS_COUNT int    = 50
)

var (
	wg               sync.WaitGroup
	processStartWg   sync.WaitGroup
	casFailsMapMutex sync.RWMutex
	casFails         map[string]int
)

func (b *BenchKVCas) Run() {
	fmt.Printf("Running: %s with %d Concurrent Processes\n", b.ClientName, PROCESS_COUNT)
	defer fmt.Printf("Completed: %s\n", b.ClientName)

	casFails := make(map[string]int)

	nc, err := nats.Connect(NATS_URL, nats.MaxReconnects(MAX_RECONNECTS), nats.ReconnectWait(RETRY_DURATION))

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
	initialValue := &element{
		Owner: "InitialOwner",
		Value: 1,
	}
	kv.Create(KEY, encode(initialValue))

	bar := progressbar.Default(int64(MAX_VALUE), "Successful CAS Ops:")

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

			processNC, err := nats.Connect("localhost", nats.MaxReconnects(MAX_RECONNECTS), nats.ReconnectWait(RETRY_DURATION))
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
					if err != nil {
						log.Println("Error getting key from bucket", err)
					}
					prevValueElement := decode(prevValue.Value())
					// terminate thread upon reaching max value and decrement WaitGroup counter by 1
					if prevValueElement.Value >= MAX_VALUE {
						return
					}
					_, err = processKV.Update(KEY, encode(&element{
						Owner: processName,
						Value: prevValueElement.Value + 1,
					}), prevValue.Revision())

					if err != nil {
						casFailureCount++
					} else {
						// successful compare-and-swap
						bar.Set(prevValueElement.Value + 1)
					}
				}
			}
		}(processId)
	}
	processStartWg.Done()

	// block until a thread reaches max value
	wg.Wait()

	// Optional: output to TSV for analysis
	file := ioutil.Discard
	if err != nil {
		log.Fatalf("failed creating file: %s\n", err)
	}
	fmt.Fprintf(file, "%s\t%s\n", "Process ID", "Failures")
	for k, v := range casFails {
		fmt.Fprintf(file, "%s\t\t%d\n", k, v)
	}
	//file.Close()
}

func encode(mutation *element) []byte {
	data, _ := json.Marshal(mutation)
	return data
}

func decode(byteArray []byte) element {
	var decodedData element
	json.Unmarshal(byteArray, &decodedData)
	return decodedData
}

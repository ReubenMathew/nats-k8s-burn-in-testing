package main

import (
	"bench/clients"
)

func main() {
	//var client clients.Client = &clients.BenchKVCas{ClientName: "Key-Value Compare-and-Swap Load Test"}
	//client.Run()
	client := &clients.BenchDurablePullConsumer{ClientName: "JetStream Durable Pull Consumer"}
	client.Run()
}

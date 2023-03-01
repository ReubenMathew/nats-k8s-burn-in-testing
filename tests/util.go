package main

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/nats-io/nats.go"
)

func unmarshalOrPanic(data []byte, v any) {
	err := json.Unmarshal(data, v)
	if err != nil {
		panic(err)
	}
	return
}

func marshalOrPanic(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}

func wipe() error {
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
		return err
	}
	defer nc.Close()

	js, err := nc.JetStream()

	for streamName := range js.StreamNames() {
		for consumerName := range js.ConsumerNames(streamName) {
			err := js.DeleteConsumer(streamName, consumerName)
			if err != nil {
				return fmt.Errorf("failed to delete consumer %s of stream %s: %w", consumerName, streamName, err)
			}
		}
		err := js.DeleteStream(streamName)
		if err != nil {
			return fmt.Errorf("failed to delete stream %s: %w", streamName, err)
		}
	}

	for kvName := range js.KeyValueStoreNames() {
		err := js.DeleteKeyValue(kvName)
		if err != nil {
			return fmt.Errorf("failed to delete KV %s: %w", kvName, err)
		}
	}

	for osName := range js.ObjectStoreNames() {
		err := js.DeleteObjectStore(osName)
		if err != nil {
			return fmt.Errorf("failed to delete ObjectStore %s: %w", osName, err)
		}
	}

	return nil
}

package main

import "encoding/json"

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

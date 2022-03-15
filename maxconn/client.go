package main

import (
	"encoding/json"
	"flag"
	"io"
	"time"
	"sync"
	"net/http"
	"fmt"
	"log"
	"golang.org/x/net/websocket"
)

var useWebsockets = flag.Bool("websockets", false, "Whether to use websockets")

type Message struct {
	Id      int    `json:"id,omitempty"`
	Message string `json:"message,omitempty"`
}


const PORT = "8081" // Haproxy
//const PORT = "4040" // Server direct

const clients = 10

// Client.
func main() {
	flag.Parse()

	var wg sync.WaitGroup
	for i := 0; i  < clients; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			start := time.Now()
			if *useWebsockets {
				ws, err := websocket.Dial("ws://localhost:" + PORT + "/", "", "http://localhost:" + PORT + "")
				for {
					var m Message
					err = websocket.JSON.Receive(ws, &m)
					if err != nil {
						if err == io.EOF {
							break
						}
						fmt.Println(i, err)
					}
					log.Printf("%d Received: %+v\n", i, m)
				}
			} else {
				fmt.Printf("%d Sending request...\n", i)
				req, err := http.NewRequest("GET", "http://localhost:" + PORT, nil)
				if err != nil {
					fmt.Println(i, err)
				}
				resp, err := http.DefaultClient.Do(req)
				if err != nil {
					fmt.Println(i, err)
				}
				if resp.StatusCode != http.StatusOK {
					duration := time.Since(start)
					fmt.Printf("%d Status code is not OK: %v (%s). Time: %v\n", i, resp.StatusCode, resp.Status, duration)
					return
				}

				dec := json.NewDecoder(resp.Body)
				for {
					var m Message
					err := dec.Decode(&m)
					if err != nil {
						if err == io.EOF {
							break
						}
						fmt.Println(i, err)
						break
					} else {
						fmt.Printf("%d Got response: %+v\n", i, m)
					}
				}
			}
			duration := time.Since(start)
			fmt.Printf("%d Server finished request...time: %v\n", i, duration)
		}(i)
	}

	wg.Wait()
}

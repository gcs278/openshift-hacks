package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"log"
	"golang.org/x/net/websocket"
)

type Message struct {
	Id      int    `json:"id,omitempty"`
	Message string `json:"message,omitempty"`
}

// Heavily based on Kubernetes' (https://github.com/GoogleCloudPlatform/kubernetes) detection code.
var connectionUpgradeRegex = regexp.MustCompile("(^|.*,\\s*)upgrade($|\\s*,)")

func isWebsocketRequest(req *http.Request) bool {
	return connectionUpgradeRegex.MatchString(strings.ToLower(req.Header.Get("Connection"))) && strings.ToLower(req.Header.Get("Upgrade")) == "websocket"
}

func Handle(w http.ResponseWriter, r *http.Request) {
	// Handle websockets if specified.
	if isWebsocketRequest(r) {
		websocket.Handler(HandleWebSockets).ServeHTTP(w, r)
	} else {
		HandleHttp(w, r)
	}
	log.Println("Finished sending response...")
}

// GCS: Not using websockets....
func HandleWebSockets(ws *websocket.Conn) {
	for i := 0; i < 5; i++ {
		log.Println("Sending some data: %d", i)
		m := Message{
			Id:      i,
			Message: fmt.Sprintf("Sending you \"%d\"", i),
		}
		err := websocket.JSON.Send(ws, &m)
		if err != nil {
			log.Println("Client stopped listening...")
			return
		}

		// Artificially induce a 1s pause
		time.Sleep(time.Second)
	}
}

func HandleHttp(w http.ResponseWriter, r *http.Request) {
	cn, ok := w.(http.CloseNotifier)
	if !ok {
		http.NotFound(w, r)
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.NotFound(w, r)
		return
	}

	// Send the initial headers saying we're gonna stream the response.
	w.Header().Set("Transfer-Encoding", "chunked")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	enc := json.NewEncoder(w)

	// How many seconds we want to keep sending data
	responseTime := 60
	for i := 0; i < responseTime; i++ {
		select {
		case <-cn.CloseNotify():
			log.Println("Client stopped listening")
			return
		default:
			// Artificially wait a second between reponses.
			time.Sleep(time.Second)

			log.Printf("Sending some data: %d\n", i)
			m := Message{
				Id:      i,
				Message: fmt.Sprintf("Sending you \"%d\"", i),
			}

			// Send some data.
			err := enc.Encode(m)
			if err != nil {
				log.Fatal(err)
			}
			// GCS: Comment out this line in-order to watch haproxy kill the connection because it goes stale
			flusher.Flush()
		}
	}
}

// Server.
func main() {
	flag.Parse()

	http.HandleFunc("/", Handle)

	log.Println("Serving...")
	log.Fatal(http.ListenAndServe(":4040", nil))
}

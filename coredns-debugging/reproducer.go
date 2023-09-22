package main

import (
	"log"
	"net"
)

func resolve() {
	var addrs []*net.SRV
	_, addrs, err := net.LookupSRV("http", "tcp", "google.com") // `http` is the label for the memcached http port number
	if err != nil {
		log.Printf("%+v", err)
	}

	log.Printf("%+v", addrs)
}

func main() {
	resolve()
}

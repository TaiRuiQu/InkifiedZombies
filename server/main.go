package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

var version = "0.2.0-beta"

func main() {
	addr := flag.String("addr", ":7778", "HTTP/WebSocket listen address")
	maxRooms := flag.Int("max-rooms", 256, "maximum simultaneous rooms")
	maxConnections := flag.Int("max-connections", 1024, "maximum simultaneous connections, including handshakes")
	tlsCert := flag.String("tls-cert", "", "optional TLS certificate PEM file (requires -tls-key)")
	tlsKey := flag.String("tls-key", "", "optional TLS private key PEM file (requires -tls-cert)")
	flag.Parse()
	if *maxRooms < 1 || *maxConnections < 4 || ((*tlsCert == "") != (*tlsKey == "")) {
		log.Fatal("Invalid limits or incomplete TLS certificate/key pair")
	}
	relay := newRelay(Config{MaxRooms: *maxRooms, MaxConnections: *maxConnections})
	server := &http.Server{Addr: *addr, Handler: relay.handler(), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 8192}
	stop := make(chan os.Signal, 1)
	shutdownDone := make(chan struct{})
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-stop
		defer close(shutdownDone)
		relay.close()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
		// HTTP Shutdown does not wait for hijacked WebSockets. Let their
		// queued room_closed frames flush before returning from main.
		deadline := time.Now().Add(2 * time.Second)
		for relay.connections.Load() > 0 && time.Now().Before(deadline) {
			time.Sleep(5 * time.Millisecond)
		}
	}()
	log.Printf("Ink Tide relay %s listening on %s; WebSocket /ws; health /healthz; capacity 4 per room", version, *addr)
	var err error
	if *tlsCert != "" {
		err = server.ListenAndServeTLS(*tlsCert, *tlsKey)
	} else {
		err = server.ListenAndServe()
	}
	if err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
	if err == http.ErrServerClosed {
		<-shutdownDone
	}
}

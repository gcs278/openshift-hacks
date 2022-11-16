package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"
)

func main() {
	// this happens about 50% of the time, so try it a few times.
	for i := 0; i < 10; i++ {
		fmt.Println("trying", i)
		try()
	}
}

func try() {
	u := "https://google.com"

        // default dial timeout is 30-second
        // https://golang.org/pkg/net/http/#RoundTripper
	cli := http.DefaultClient

	timeout := 300 * time.Microsecond
	reqs := 20
	errc := make(chan error, reqs)
	for i := 0; i < reqs; i++ {
		go func() {
			ctx, cancel := context.WithTimeout(context.TODO(), timeout)
			defer cancel()

			req, err := http.NewRequest(http.MethodGet, u, nil)
			if err != nil {
				errc <- err
				return
			}
			_, err = cli.Do(req.WithContext(ctx))
			if err != nil {
				// can be: ctx.Err() == nil && err == "i/o timeout"
				// Q. but how is that possible?
				fmt.Println("Do failed with", err, "/ context error:", ctx.Err())
			}
			errc <- err
		}()
	}

	// "context deadline exceeded" for requests after timeout
	exp := `context deadline`
	for i := 0; i < reqs; i++ {
		err := <-errc
		if err == nil {
			continue
		}
		fmt.Println("error:", err)
		if !strings.Contains(err.Error(), exp) {
			panic(fmt.Sprintf("#%d: expected %q, got %v", i, exp, err))
		}
	}
}

package main

import (
	"testing"
	"time"
)

func TestRateLimiterBurstRefillAndCleanup(t *testing.T) {
	now := time.Unix(5000, 0)
	limiter := newRateLimiter(10, time.Minute, 3, 10*time.Minute)
	for i := 0; i < 3; i++ {
		if !limiter.Allow("client", now) {
			t.Fatalf("burst request %d rejected", i+1)
		}
	}
	if limiter.Allow("client", now) {
		t.Fatal("fourth burst request accepted")
	}
	now = now.Add(6 * time.Second)
	if !limiter.Allow("client", now) {
		t.Fatal("refilled request rejected")
	}

	limiter.Allow("old", now)
	now = now.Add(11 * time.Minute)
	limiter.Allow("new", now)
	if _, ok := limiter.buckets["old"]; ok {
		t.Fatal("idle bucket was not cleaned up")
	}
}

//go:build android && cgo

package platform

import (
	"runtime/debug"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// Backpressure thresholds are percentages of the hard fd ceiling (maxFdCount).
// The gap between the high and low water marks is what makes the gate
// hysteretic: once the high mark is crossed the process keeps rejecting new
// connections until the fd count falls back below the low mark, instead of
// flapping between blocked/allowed on every single dial.
const (
	// highWaterPercent closes the gate at 80% of the hard fd ceiling.
	highWaterPercent = 80
	// lowWaterPercent reopens the gate only after usage drops below 65%.
	lowWaterPercent = 65
)

// fdProbeTTL caches the last observed fd count so that a burst of concurrent
// dials does not perform one Dup syscall each.
const fdProbeTTL = 200 * time.Millisecond

var nullFd int

var (
	maxFdCount  int
	highFdCount int
	lowFdCount  int
)

var (
	// blocking holds the hysteresis state: true means the gate is closed
	// until the fd count recovers below lowFdCount.
	blocking atomic.Bool

	probeMu     sync.Mutex
	lastFdCount int
	lastProbeAt time.Time
)

func init() {
	fd, err := syscall.Open("/dev/null", syscall.O_WRONLY, 0644)
	if err != nil {
		panic(err.Error())
	}

	nullFd = fd

	maxFdCount = 1024

	var limit syscall.Rlimit

	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &limit); err == nil {
		maxFdCount = int(limit.Cur)
	}

	maxFdCount = maxFdCount / 4 * 3
	highFdCount = maxFdCount * highWaterPercent / 100
	lowFdCount = maxFdCount * lowWaterPercent / 100
}

// currentFdCount reports how many file descriptors this process currently has
// open, by dup'ing a well-known fd. The result is cached for fdProbeTTL so that
// concurrent dials share a single probe.
func currentFdCount() int {
	probeMu.Lock()
	defer probeMu.Unlock()

	now := time.Now()
	if !lastProbeAt.IsZero() && now.Sub(lastProbeAt) < fdProbeTTL {
		return lastFdCount
	}

	fd, err := syscall.Dup(nullFd)
	if err != nil {
		// If we cannot even dup, the process is already saturated.
		lastFdCount = maxFdCount + 1
		lastProbeAt = now
		return lastFdCount
	}

	_ = syscall.Close(fd)

	lastFdCount = fd
	lastProbeAt = now

	return fd
}

// ShouldBlockConnection reports whether a new outbound connection must be
// rejected to protect the process from fd exhaustion.
//
// Unlike a simple threshold check, this uses hysteresis: the gate is closed
// when the fd count reaches the high water mark and is only reopened once the
// count drops below the low water mark. On the closing transition it also
// schedules a FreeOSMemory so the runtime can release buffered memory (and any
// fd-backed resources it still holds), which helps the count recover.
func ShouldBlockConnection() bool {
	count := currentFdCount()

	if blocking.Load() {
		if count < lowFdCount {
			blocking.Store(false)
			return false
		}
		return true
	}

	if count >= highFdCount {
		blocking.Store(true)
		go debug.FreeOSMemory()
		return true
	}

	return false
}

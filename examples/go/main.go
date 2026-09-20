// Command snapshot reads a broker-time snapshot exported by MT5.
// It does not connect to an account, place trades, or calculate indicators.
package main

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
)

type options struct {
	path      string
	concept   string
	direction string
}

const usage = "Usage: go run . SNAPSHOT.json [--concept CONCEPT] [--direction bullish|bearish|neutral]\n"

var conceptPattern = regexp.MustCompile(`^[A-Z][A-Z0-9_]*$`)

func parseOptions(args []string) (options, error) {
	var result options
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--concept", "--direction":
			name := args[i]
			if i+1 >= len(args) {
				return result, fmt.Errorf("%s requires a value", name)
			}
			i++
			if name == "--concept" {
				if result.concept != "" || !conceptPattern.MatchString(args[i]) {
					return result, fmt.Errorf("--concept requires one uppercase concept name")
				}
				result.concept = args[i]
			} else {
				if result.direction != "" || !validDirection(args[i]) {
					return result, fmt.Errorf("--direction must be bullish, bearish, or neutral")
				}
				result.direction = args[i]
			}
		default:
			if len(args[i]) == 0 || args[i][0] == '-' || result.path != "" {
				return result, fmt.Errorf("expected one snapshot path; unexpected argument %q", args[i])
			}
			result.path = args[i]
		}
	}
	if result.path == "" {
		return result, fmt.Errorf("a snapshot path is required")
	}
	return result, nil
}

func run(args []string, out, errOut io.Writer) int {
	if len(args) == 1 && (args[0] == "--help" || args[0] == "-h") {
		fmt.Fprint(out, usage)
		return 0
	}
	opts, err := parseOptions(args)
	if err != nil {
		fmt.Fprintf(errOut, "error: %v\n%s", err, usage)
		return 2
	}
	file, err := os.Open(opts.path)
	if err != nil {
		fmt.Fprintf(errOut, "error: %v\n", err)
		return 1
	}
	defer file.Close()
	snapshot, err := readSnapshot(file)
	if err != nil {
		fmt.Fprintf(errOut, "error: %v\n", err)
		return 1
	}
	if err := printSnapshot(out, snapshot, opts); err != nil {
		fmt.Fprintf(errOut, "error: %v\n", err)
		return 1
	}
	return 0
}

func printSnapshot(out io.Writer, snapshot snapshot, opts options) error {
	asOf := "null"
	if snapshot.asOf != nil {
		asOf = *snapshot.asOf
	}
	if _, err := fmt.Fprintf(out, "status=%s symbol=%s timeframe=%s as_of=%s time_basis=broker\n", snapshot.status, snapshot.symbol, snapshot.timeframe, asOf); err != nil {
		return err
	}
	sort.Slice(snapshot.records, func(i, j int) bool { return snapshot.records[i].id < snapshot.records[j].id })
	for _, record := range snapshot.records {
		if (opts.concept != "" && opts.concept != record.concept) || (opts.direction != "" && opts.direction != record.direction) {
			continue
		}
		if _, err := fmt.Fprintf(out, "%s\t%s\t%s\t%s\t%.8f\t%.8f\n", record.id, record.concept, record.direction, record.state, record.lower, record.upper); err != nil {
			return err
		}
	}
	return nil
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

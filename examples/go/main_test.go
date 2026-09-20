package main

import (
	"bytes"
	"encoding/json"
	"math"
	"os"
	"strconv"
	"strings"
	"testing"
)

const validJSON = `{
  "schema_version":"1.0", "library_version":"1.0.0", "symbol":"EURUSD", "timeframe":"M15",
  "time_basis":"broker", "as_of":"2026-09-18T12:00:00", "status":"PARTIAL",
  "config":{
    "lookback_bars":500,"max_records_per_concept":100,"swing_strength":5,
    "displacement_baseline":20,"displacement_multiplier":1.5,"displacement_body_fraction":0.6,
    "min_fvg_pips":2,"max_zone_age":200,"bpr_max_separation":50,"po3_expiry_bars":20,
    "smt_symbol":"","smt_radius":1,"enable_draw":false,"enable_calendar":true,
    "enable_smt":false,"enable_po3":true,"enable_displacement":true,"enable_mss":true,
    "enable_ifvg":true,"enable_bpr":true,"enable_cs":false,"enable_vix":false,
    "sessions":[{"name":"Asian","start_minute":0,"end_minute":480},
      {"name":"London","start_minute":420,"end_minute":960},
      {"name":"New York","start_minute":720,"end_minute":1260}]
  },
  "modules":[{"concept":"FVG","status":"READY","as_of":null,"truncated":false,"message":""}],
  "records":[{
    "id":"fvg-a","concept":"FVG","source_time":"2026-09-18T11:00:00",
    "confirmed_at":"2026-09-18T11:30:00","updated_at":"2026-09-18T12:00:00",
    "direction":"bullish","lower":1.1,"upper":1.2,"state":"TESTED","active":true,
    "related_ids":[],"period_start":null,"period_end":null,"reference_price":0,
    "comparison_price":0,"strength":0,"reason":""
  }]
}`

func document(t *testing.T) map[string]any {
	t.Helper()
	var result map[string]any
	if err := json.Unmarshal([]byte(validJSON), &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func encode(t *testing.T, value any) string {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestValidationAndAdditiveVersion(t *testing.T) {
	root := document(t)
	root["schema_version"] = "1.12"
	root["future_field"] = map[string]any{"description": "permitted extension"}
	root["as_of"] = nil
	snap, err := readSnapshot(strings.NewReader(encode(t, root)))
	if err != nil || snap.asOf != nil || len(snap.records) != 1 {
		t.Fatalf("valid snapshot rejected: %#v, %v", snap, err)
	}
}

func TestEveryDeclaredFieldIsRequired(t *testing.T) {
	selectors := map[string]func(map[string]any) map[string]any{
		"root":   func(root map[string]any) map[string]any { return root },
		"config": func(root map[string]any) map[string]any { return root["config"].(map[string]any) },
		"module": func(root map[string]any) map[string]any { return root["modules"].([]any)[0].(map[string]any) },
		"record": func(root map[string]any) map[string]any { return root["records"].([]any)[0].(map[string]any) },
	}
	for name, selectObject := range selectors {
		for field := range selectObject(document(t)) {
			t.Run(name+"/"+field, func(t *testing.T) {
				root := document(t)
				delete(selectObject(root), field)
				if _, err := readSnapshot(strings.NewReader(encode(t, root))); err == nil {
					t.Fatalf("missing %s.%s accepted", name, field)
				}
			})
		}
	}
}

func TestInvalidSnapshots(t *testing.T) {
	cases := map[string]string{
		"unsupported major":         strings.Replace(validJSON, `"schema_version":"1.0"`, `"schema_version":"2.0"`, 1),
		"wrong type":                strings.Replace(validJSON, `"active":true`, `"active":1`, 1),
		"invalid direction":         strings.Replace(validJSON, `"direction":"bullish"`, `"direction":"buy"`, 1),
		"invalid status":            strings.Replace(validJSON, `"status":"PARTIAL"`, `"status":"SUCCESS"`, 1),
		"null record time":          strings.Replace(validJSON, `"source_time":"2026-09-18T11:00:00"`, `"source_time":null`, 1),
		"invalid calendar day":      strings.ReplaceAll(validJSON, "2026-09-18", "2026-02-30"),
		"year zero":                 strings.ReplaceAll(validJSON, "2026-09-18", "0000-09-18"),
		"utc timestamp":             strings.ReplaceAll(validJSON, "12:00:00", "12:00:00Z"),
		"reversed bounds":           strings.Replace(validJSON, `"lower":1.1`, `"lower":1.3`, 1),
		"nonfinite price":           strings.Replace(validJSON, `"lower":1.1`, `"lower":1e400`, 1),
		"nullable price":            strings.Replace(validJSON, `"reference_price":0`, `"reference_price":null`, 1),
		"fraction too large":        strings.Replace(validJSON, `"displacement_body_fraction":0.6`, `"displacement_body_fraction":1.1`, 1),
		"fractional count":          strings.Replace(validJSON, `"lookback_bars":500`, `"lookback_bars":1.5`, 1),
		"count too large":           strings.Replace(validJSON, `"lookback_bars":500`, `"lookback_bars":100001`, 1),
		"missing comparison symbol": strings.Replace(validJSON, `"enable_smt":false`, `"enable_smt":true`, 1),
		"out of range minute":       strings.Replace(validJSON, `"start_minute":0`, `"start_minute":1440`, 1),
		"trailing document":         validJSON + `{}`,
	}
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := readSnapshot(strings.NewReader(data)); err == nil {
				t.Fatal("invalid snapshot accepted")
			}
		})
	}
	root := document(t)
	records := root["records"].([]any)
	root["records"] = append(records, records[0])
	if _, err := readSnapshot(strings.NewReader(encode(t, root))); err == nil {
		t.Fatal("duplicate IDs accepted")
	}
}

func TestOutputSortingAndFilters(t *testing.T) {
	snap, err := readSnapshot(strings.NewReader(validJSON))
	if err != nil {
		t.Fatal(err)
	}
	snap.records = append([]record{{id: "z", concept: "MSS", direction: "bearish", state: "CONFIRMED", lower: 2, upper: 3}}, snap.records...)
	wantHeader := "status=PARTIAL symbol=EURUSD timeframe=M15 as_of=2026-09-18T12:00:00 time_basis=broker\n"
	wantFVG := "fvg-a\tFVG\tbullish\tTESTED\t1.10000000\t1.20000000\n"
	wantMSS := "z\tMSS\tbearish\tCONFIRMED\t2.00000000\t3.00000000\n"
	for _, test := range []struct {
		opts options
		want string
	}{
		{options{}, wantHeader + wantFVG + wantMSS},
		{options{concept: "FVG", direction: "bullish"}, wantHeader + wantFVG},
		{options{concept: "FVG", direction: "bearish"}, wantHeader},
	} {
		var out bytes.Buffer
		if err := printSnapshot(&out, snap, test.opts); err != nil {
			t.Fatal(err)
		}
		if out.String() != test.want {
			t.Fatalf("output mismatch: got %q; want %q", out.String(), test.want)
		}
	}
}

func TestOptions(t *testing.T) {
	for _, args := range [][]string{
		{"sample.json", "--concept", "FVG", "--direction", "bullish"},
		{"--direction", "bullish", "sample.json", "--concept", "FVG"},
	} {
		opts, err := parseOptions(args)
		if err != nil || opts.path != "sample.json" || opts.concept != "FVG" || opts.direction != "bullish" {
			t.Fatalf("valid arguments rejected: %#v, %v", opts, err)
		}
	}
	for _, args := range [][]string{{}, {"a", "b"}, {"a", "--direction"}, {"a", "--direction", "buy"}, {"a", "--concept", "fvg"}} {
		if _, err := parseOptions(args); err == nil {
			t.Fatalf("invalid arguments accepted: %v", args)
		}
	}
}

func TestSharedFixture(t *testing.T) {
	want, err := os.ReadFile("../../tests/fixtures/snapshot-v1.expected.txt")
	if err != nil {
		t.Fatal(err)
	}
	var out, errors bytes.Buffer
	if code := run([]string{"../../tests/fixtures/snapshot-v1.json"}, &out, &errors); code != 0 {
		t.Fatalf("fixture reader exited %d: %s", code, errors.String())
	}
	if out.String() != string(want) {
		t.Fatalf("fixture output mismatch: got %q; want %q", out.String(), want)
	}
}

func TestFormatPrice(t *testing.T) {
	for _, test := range []struct {
		name  string
		value float64
		want  string
	}{
		{"positive tie", 0.001953125, "0.00195312"},
		{"negative tie", -0.001953125, "-0.00195312"},
		{"positive near tie", 1.000000005, "1.00000000"},
		{"negative near tie", -1.000000005, "-1.00000000"},
		{"zero", 0, "0.00000000"},
		{"negative zero", math.Copysign(0, -1), "0.00000000"},
		{"small negative", -1e-12, "0.00000000"},
		{"large", 1e21, "1000000000000000000000.00000000"},
		{"huge", 1e100, "10000000000000000159028911097599180468360808563945281389781327557747838772170381060813469985856815104.00000000"},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := formatPrice(test.value); got != test.want {
				t.Fatalf("formatPrice(%g) = %q; want %q", test.value, got, test.want)
			}
		})
	}
	maximum := formatPrice(math.MaxFloat64)
	if strings.ContainsAny(maximum, "eE") || !strings.HasSuffix(maximum, ".00000000") {
		t.Fatalf("maximum finite price is not fixed point: %q", maximum)
	}
	if parsed, err := strconv.ParseFloat(maximum, 64); err != nil || parsed != math.MaxFloat64 {
		t.Fatalf("maximum finite price does not round-trip: %q, %v", maximum, err)
	}
}

func TestOptionalMessage(t *testing.T) {
	for _, message := range []any{"", "History is loading"} {
		root := document(t)
		root["message"] = message
		if _, err := readSnapshot(strings.NewReader(encode(t, root))); err != nil {
			t.Fatalf("string message rejected: %v", err)
		}
	}
	for _, message := range []any{nil, true, 1, []any{}, map[string]any{}} {
		root := document(t)
		root["message"] = message
		if _, err := readSnapshot(strings.NewReader(encode(t, root))); err == nil {
			t.Fatalf("invalid message accepted: %#v", message)
		}
	}
}

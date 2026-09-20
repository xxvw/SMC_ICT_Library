package main

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"regexp"
	"time"
)

type record struct {
	id, concept, direction, state string
	lower, upper                  float64
}

type snapshot struct {
	status, symbol, timeframe string
	asOf                      *string
	records                   []record
}

// These validators mirror schemas/snapshot.schema.json without dependencies.
// Required fields are checked explicitly; additive version 1 fields are allowed.
type validator func(any, string) error

func object(fields map[string]validator) validator {
	return func(value any, path string) error {
		values, ok := value.(map[string]any)
		if !ok {
			return fmt.Errorf("%s must be an object", path)
		}
		for name, check := range fields {
			item, present := values[name]
			if !present {
				return fmt.Errorf("%s.%s is required", path, name)
			}
			if err := check(item, path+"."+name); err != nil {
				return err
			}
		}
		return nil
	}
}

func array(item validator, count int) validator {
	return func(value any, path string) error {
		values, ok := value.([]any)
		if !ok || (count >= 0 && len(values) != count) {
			return fmt.Errorf("%s must be an array%s", path, requiredCount(count))
		}
		for i, value := range values {
			if err := item(value, fmt.Sprintf("%s[%d]", path, i)); err != nil {
				return err
			}
		}
		return nil
	}
}

func requiredCount(count int) string {
	if count < 0 {
		return ""
	}
	return fmt.Sprintf(" with %d items", count)
}

func textValue(nonempty bool) validator {
	return func(value any, path string) error {
		text, ok := value.(string)
		if !ok || (nonempty && text == "") {
			if nonempty {
				return fmt.Errorf("%s must be a nonempty string", path)
			}
			return fmt.Errorf("%s must be a string", path)
		}
		return nil
	}
}

func enum(values ...string) validator {
	return func(value any, path string) error {
		text, ok := value.(string)
		if ok {
			for _, allowed := range values {
				if text == allowed {
					return nil
				}
			}
		}
		return fmt.Errorf("%s has an unsupported value", path)
	}
}

func boolean(value any, path string) error {
	if _, ok := value.(bool); !ok {
		return fmt.Errorf("%s must be a boolean", path)
	}
	return nil
}

func number(minimum, maximum float64, integer, exclusiveMinimum bool) validator {
	return func(value any, path string) error {
		number, ok := value.(json.Number)
		if !ok {
			return fmt.Errorf("%s must be a number", path)
		}
		v, err := number.Float64()
		if err != nil || math.IsNaN(v) || math.IsInf(v, 0) || v < minimum || v > maximum ||
			(integer && math.Trunc(v) != v) || (exclusiveMinimum && v == minimum) {
			return fmt.Errorf("%s is outside its permitted numeric range", path)
		}
		return nil
	}
}

var timestampPattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$`)
var versionPattern = regexp.MustCompile(`^1\.[0-9]+$`)

func timestamp(nullable bool) validator {
	return func(value any, path string) error {
		if value == nil && nullable {
			return nil
		}
		text, ok := value.(string)
		if ok && timestampPattern.MatchString(text) && text[:4] != "0000" {
			if _, err := time.Parse("2006-01-02T15:04:05", text); err == nil {
				return nil
			}
		}
		return fmt.Errorf("%s must be a valid broker timestamp (YYYY-MM-DDTHH:mm:ss)", path)
	}
}

func validDirection(direction string) bool {
	return direction == "bullish" || direction == "bearish" || direction == "neutral"
}

var statusValue = enum("READY", "PARTIAL", "NOT_READY", "ERROR", "DISABLED")
var conceptValue = enum(
	"SWING_HIGH", "SWING_LOW", "BOS", "CHOCH", "ORDER_BLOCK", "FVG", "LIQUIDITY",
	"PREMIUM_DISCOUNT", "OTE", "KILL_ZONE", "BREAKER", "DISPLACEMENT", "MSS", "IFVG", "BPR",
	"PREVIOUS_DAY_HIGH", "PREVIOUS_DAY_LOW", "PREVIOUS_WEEK_HIGH", "PREVIOUS_WEEK_LOW",
	"SESSION_HIGH", "SESSION_LOW", "DAILY_GAP", "WEEKLY_GAP", "SMT", "PO3",
)

func snapshotValidator() validator {
	unbounded := number(math.Inf(-1), math.Inf(1), false, false)
	configFields := map[string]validator{
		"lookback_bars": number(1, 100000, true, false), "max_records_per_concept": number(1, 100000, true, false),
		"swing_strength": number(1, 5000, true, false), "displacement_baseline": number(1, 5000, true, false),
		"displacement_multiplier":    number(0, math.Inf(1), false, true),
		"displacement_body_fraction": number(0, 1, false, true),
		"min_fvg_pips":               number(0, math.Inf(1), false, false),
		"max_zone_age":               number(1, 10000, true, false), "bpr_max_separation": number(1, 10000, true, false),
		"po3_expiry_bars": number(1, 10000, true, false), "smt_symbol": textValue(false),
		"smt_radius": number(0, 5000, true, false),
		"sessions": array(object(map[string]validator{
			"name":         textValue(true),
			"start_minute": number(0, 1439, true, false),
			"end_minute":   number(0, 1439, true, false),
		}), 3),
	}
	for _, key := range []string{"enable_draw", "enable_calendar", "enable_smt", "enable_po3", "enable_displacement", "enable_mss", "enable_ifvg", "enable_bpr", "enable_cs", "enable_vix"} {
		configFields[key] = boolean
	}
	return object(map[string]validator{
		"schema_version": func(value any, path string) error {
			version, ok := value.(string)
			if !ok || !versionPattern.MatchString(version) {
				return fmt.Errorf("%s must use supported version 1.<minor>", path)
			}
			return nil
		},
		"library_version": textValue(true), "symbol": textValue(true), "timeframe": textValue(true),
		"time_basis": enum("broker"), "as_of": timestamp(true), "status": statusValue,
		"config": object(configFields),
		"modules": array(object(map[string]validator{
			"concept": conceptValue, "status": statusValue, "as_of": timestamp(true),
			"truncated": boolean, "message": textValue(false),
		}), -1),
		"records": array(object(map[string]validator{
			"id": textValue(true), "concept": conceptValue, "source_time": timestamp(false),
			"confirmed_at": timestamp(false), "updated_at": timestamp(false),
			"direction": enum("bullish", "bearish", "neutral"), "lower": unbounded, "upper": unbounded,
			"state": textValue(true), "active": boolean, "related_ids": array(textValue(true), -1),
			"period_start": timestamp(true), "period_end": timestamp(true), "reference_price": unbounded,
			"comparison_price": unbounded, "strength": unbounded, "reason": textValue(false),
		}), -1),
	})
}

func readSnapshot(reader io.Reader) (snapshot, error) {
	var result snapshot
	decoder := json.NewDecoder(reader)
	decoder.UseNumber()
	var document any
	if err := decoder.Decode(&document); err != nil {
		return result, fmt.Errorf("invalid snapshot JSON: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return result, fmt.Errorf("snapshot must contain exactly one JSON document")
	}
	if err := snapshotValidator()(document, "snapshot"); err != nil {
		return result, err
	}
	root := document.(map[string]any)
	if message, present := root["message"]; present {
		if err := textValue(false)(message, "snapshot.message"); err != nil {
			return result, err
		}
	}
	config := root["config"].(map[string]any)
	if config["enable_smt"].(bool) && config["smt_symbol"].(string) == "" {
		return result, fmt.Errorf("snapshot.config.smt_symbol is required when SMT is enabled")
	}
	result.status = root["status"].(string)
	result.symbol = root["symbol"].(string)
	result.timeframe = root["timeframe"].(string)
	if root["as_of"] != nil {
		value := root["as_of"].(string)
		result.asOf = &value
	}
	seenIDs := make(map[string]bool)
	for i, value := range root["records"].([]any) {
		item := value.(map[string]any)
		id := item["id"].(string)
		if seenIDs[id] {
			return snapshot{}, fmt.Errorf("snapshot.records[%d].id is duplicated", i)
		}
		seenIDs[id] = true
		lower, _ := item["lower"].(json.Number).Float64()
		upper, _ := item["upper"].(json.Number).Float64()
		if lower > upper {
			return snapshot{}, fmt.Errorf("snapshot.records[%d].lower exceeds upper", i)
		}
		result.records = append(result.records, record{
			id: id, concept: item["concept"].(string), direction: item["direction"].(string),
			state: item["state"].(string), lower: lower, upper: upper,
		})
	}
	return result, nil
}

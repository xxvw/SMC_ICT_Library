//! Read the versioned JSON snapshot produced by MT5. No trading or detection logic.
use serde_json::{Map, Value};
use std::{collections::HashSet, env, fs, process};

type Result<T> = std::result::Result<T, String>;
type Object = Map<String, Value>;

const STATUSES: &[&str] = &["READY", "PARTIAL", "NOT_READY", "ERROR", "DISABLED"];
const DIRECTIONS: &[&str] = &["bullish", "bearish", "neutral"];
const CONCEPTS: &[&str] = &[
    "SWING_HIGH",
    "SWING_LOW",
    "BOS",
    "CHOCH",
    "ORDER_BLOCK",
    "FVG",
    "LIQUIDITY",
    "PREMIUM_DISCOUNT",
    "OTE",
    "KILL_ZONE",
    "BREAKER",
    "DISPLACEMENT",
    "MSS",
    "IFVG",
    "BPR",
    "PREVIOUS_DAY_HIGH",
    "PREVIOUS_DAY_LOW",
    "PREVIOUS_WEEK_HIGH",
    "PREVIOUS_WEEK_LOW",
    "SESSION_HIGH",
    "SESSION_LOW",
    "DAILY_GAP",
    "WEEKLY_GAP",
    "SMT",
    "PO3",
];

fn object<'a>(value: &'a Value, path: &str) -> Result<&'a Object> {
    value
        .as_object()
        .ok_or_else(|| format!("{path} must be an object"))
}

fn required<'a>(obj: &'a Object, name: &str, path: &str) -> Result<&'a Value> {
    obj.get(name)
        .ok_or_else(|| format!("{path}.{name} is required"))
}

fn string<'a>(obj: &'a Object, name: &str, path: &str) -> Result<&'a str> {
    required(obj, name, path)?
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("{path}.{name} must be a nonempty string"))
}

fn text<'a>(obj: &'a Object, name: &str, path: &str) -> Result<&'a str> {
    required(obj, name, path)?
        .as_str()
        .ok_or_else(|| format!("{path}.{name} must be a string"))
}

fn enumeration<'a>(obj: &'a Object, name: &str, path: &str, choices: &[&str]) -> Result<&'a str> {
    let value = string(obj, name, path)?;
    if !choices.contains(&value) {
        return Err(format!(
            "{path}.{name} must be one of {}",
            choices.join(", ")
        ));
    }
    Ok(value)
}

fn number(obj: &Object, name: &str, path: &str) -> Result<f64> {
    required(obj, name, path)?
        .as_f64()
        .filter(|v| v.is_finite())
        .ok_or_else(|| format!("{path}.{name} must be a finite number"))
}

fn boolean(obj: &Object, name: &str, path: &str) -> Result<bool> {
    required(obj, name, path)?
        .as_bool()
        .ok_or_else(|| format!("{path}.{name} must be a boolean"))
}

fn array<'a>(obj: &'a Object, name: &str, path: &str) -> Result<&'a Vec<Value>> {
    required(obj, name, path)?
        .as_array()
        .ok_or_else(|| format!("{path}.{name} must be an array"))
}

fn valid_concept(value: &str) -> bool {
    let mut bytes = value.bytes();
    matches!(bytes.next(), Some(b'A'..=b'Z'))
        && bytes.all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
}

fn integer(obj: &Object, name: &str, path: &str, minimum: f64, maximum: f64) -> Result<()> {
    let value = number(obj, name, path)?;
    if value.fract() != 0.0 || value < minimum || value > maximum {
        return Err(format!(
            "{path}.{name} must be an integer from {minimum} to {maximum}"
        ));
    }
    Ok(())
}

fn validate_config(value: &Value) -> Result<()> {
    let path = "snapshot.config";
    let config = object(value, path)?;
    for (name, maximum) in [
        ("lookback_bars", 100000.0),
        ("max_records_per_concept", 100000.0),
        ("swing_strength", 5000.0),
        ("displacement_baseline", 5000.0),
        ("max_zone_age", 10000.0),
        ("bpr_max_separation", 10000.0),
        ("po3_expiry_bars", 10000.0),
    ] {
        integer(config, name, path, 1.0, maximum)?;
    }
    integer(config, "smt_radius", path, 0.0, 5000.0)?;
    if number(config, "displacement_multiplier", path)? <= 0.0 {
        return Err(format!(
            "{path}.displacement_multiplier must be greater than zero"
        ));
    }
    let fraction = number(config, "displacement_body_fraction", path)?;
    if fraction <= 0.0 || fraction > 1.0 {
        return Err(format!(
            "{path}.displacement_body_fraction must be greater than zero and at most one"
        ));
    }
    if number(config, "min_fvg_pips", path)? < 0.0 {
        return Err(format!("{path}.min_fvg_pips must be nonnegative"));
    }
    let smt_symbol = text(config, "smt_symbol", path)?;
    if boolean(config, "enable_smt", path)? && smt_symbol.is_empty() {
        return Err(format!(
            "{path}.smt_symbol must be nonempty when enable_smt is true"
        ));
    }
    for name in [
        "enable_draw",
        "enable_calendar",
        "enable_smt",
        "enable_po3",
        "enable_displacement",
        "enable_mss",
        "enable_ifvg",
        "enable_bpr",
        "enable_cs",
        "enable_vix",
    ] {
        boolean(config, name, path)?;
    }
    let sessions = array(config, "sessions", path)?;
    if sessions.len() != 3 {
        return Err(format!(
            "{path}.sessions must contain exactly three sessions"
        ));
    }
    for (index, value) in sessions.iter().enumerate() {
        let path = format!("snapshot.config.sessions[{index}]");
        let session = object(value, &path)?;
        string(session, "name", &path)?;
        integer(session, "start_minute", &path, 0.0, 1439.0)?;
        integer(session, "end_minute", &path, 0.0, 1439.0)?;
    }
    Ok(())
}

// These are broker wall-clock timestamps. Never append Z or convert to local time.
fn valid_timestamp(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 19
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || bytes[10] != b'T'
        || bytes[13] != b':'
        || bytes[16] != b':'
    {
        return false;
    }
    if bytes
        .iter()
        .enumerate()
        .any(|(i, b)| ![4, 7, 10, 13, 16].contains(&i) && !b.is_ascii_digit())
    {
        return false;
    }
    let part = |start: usize, end: usize| value[start..end].parse::<u32>().unwrap();
    let year = part(0, 4);
    let month = part(5, 7);
    let day = part(8, 10);
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        _ => return false,
    };
    year > 0
        && day > 0
        && day <= days
        && part(11, 13) < 24
        && part(14, 16) < 60
        && part(17, 19) < 60
}

fn timestamp(obj: &Object, name: &str, path: &str, nullable: bool) -> Result<()> {
    let value = required(obj, name, path)?;
    if nullable && value.is_null() {
        return Ok(());
    }
    if !value.as_str().is_some_and(valid_timestamp) {
        return Err(format!(
            "{path}.{name} must be a broker timestamp YYYY-MM-DDTHH:mm:ss{}",
            if nullable { " or null" } else { "" }
        ));
    }
    Ok(())
}

fn validate(snapshot: &Value) -> Result<()> {
    let root = object(snapshot, "snapshot")?;
    let version = string(root, "schema_version", "snapshot")?;
    let minor = version.strip_prefix("1.").unwrap_or("");
    if minor.is_empty() || !minor.bytes().all(|b| b.is_ascii_digit()) {
        return Err("snapshot.schema_version must have supported format 1.<digits>".into());
    }
    for name in ["library_version", "symbol", "timeframe"] {
        string(root, name, "snapshot")?;
    }
    enumeration(root, "time_basis", "snapshot", &["broker"])?;
    enumeration(root, "status", "snapshot", STATUSES)?;
    timestamp(root, "as_of", "snapshot", true)?;
    validate_config(required(root, "config", "snapshot")?)?;
    for (index, value) in array(root, "modules", "snapshot")?.iter().enumerate() {
        let path = format!("snapshot.modules[{index}]");
        let module = object(value, &path)?;
        enumeration(module, "concept", &path, CONCEPTS)?;
        boolean(module, "truncated", &path)?;
        text(module, "message", &path)?;
        enumeration(module, "status", &path, STATUSES)?;
        timestamp(module, "as_of", &path, true)?;
    }
    let mut ids = HashSet::new();
    for (index, value) in array(root, "records", "snapshot")?.iter().enumerate() {
        let path = format!("snapshot.records[{index}]");
        let record = object(value, &path)?;
        let id = string(record, "id", &path)?;
        if !ids.insert(id) {
            return Err(format!("{path}.id must be unique: {id}"));
        }
        enumeration(record, "concept", &path, CONCEPTS)?;
        for name in ["source_time", "confirmed_at", "updated_at"] {
            timestamp(record, name, &path, false)?;
        }
        for name in ["period_start", "period_end"] {
            timestamp(record, name, &path, true)?;
        }
        enumeration(record, "direction", &path, DIRECTIONS)?;
        let lower = number(record, "lower", &path)?;
        let upper = number(record, "upper", &path)?;
        if lower > upper {
            return Err(format!("{path}.lower must not exceed upper"));
        }
        string(record, "state", &path)?;
        boolean(record, "active", &path)?;
        for (index, item) in array(record, "related_ids", &path)?.iter().enumerate() {
            if item.as_str().is_none_or(|v| v.is_empty()) {
                return Err(format!(
                    "{path}.related_ids[{index}] must be a nonempty string"
                ));
            }
        }
        for name in ["reference_price", "comparison_price", "strength"] {
            number(record, name, &path)?;
        }
        text(record, "reason", &path)?;
    }
    Ok(())
}

fn render(snapshot: &Value, concept: Option<&str>, direction: Option<&str>) -> Result<String> {
    validate(snapshot)?;
    let root = snapshot.as_object().unwrap();
    let as_of = root["as_of"].as_str().unwrap_or("null");
    let mut output = format!(
        "status={} symbol={} timeframe={} as_of={} time_basis=broker\n",
        root["status"].as_str().unwrap(),
        root["symbol"].as_str().unwrap(),
        root["timeframe"].as_str().unwrap(),
        as_of
    );
    let mut records: Vec<_> = root["records"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|record| concept.is_none_or(|filter| record["concept"].as_str() == Some(filter)))
        .filter(|record| {
            direction.is_none_or(|filter| record["direction"].as_str() == Some(filter))
        })
        .collect();
    records.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    for record in records {
        output.push_str(&format!(
            "{}\t{}\t{}\t{}\t{:.8}\t{:.8}\n",
            record["id"].as_str().unwrap(),
            record["concept"].as_str().unwrap(),
            record["direction"].as_str().unwrap(),
            record["state"].as_str().unwrap(),
            record["lower"].as_f64().unwrap(),
            record["upper"].as_f64().unwrap()
        ));
    }
    Ok(output)
}

fn run(args: &[String]) -> Result<String> {
    if args.is_empty() {
        return Err("usage: smc-snapshot-reader SNAPSHOT.json [--concept FVG] [--direction bullish|bearish|neutral]".into());
    }
    let path = &args[0];
    let mut concept = None;
    let mut direction = None;
    let mut index = 1;
    while index < args.len() {
        let flag = &args[index];
        let value = args
            .get(index + 1)
            .ok_or_else(|| format!("{flag} requires a value"))?;
        match flag.as_str() {
            "--concept" if concept.is_none() && valid_concept(value) => {
                concept = Some(value.as_str())
            }
            "--direction" if direction.is_none() && DIRECTIONS.contains(&value.as_str()) => {
                direction = Some(value.as_str())
            }
            _ => return Err(format!("invalid or repeated argument: {flag} {value}")),
        }
        index += 2;
    }
    let contents = fs::read_to_string(path).map_err(|e| format!("cannot read {path}: {e}"))?;
    let snapshot = serde_json::from_str(&contents).map_err(|e| format!("invalid JSON: {e}"))?;
    render(&snapshot, concept, direction)
}

fn main() {
    match run(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(output) => print!("{output}"),
        Err(error) => {
            eprintln!("error: {error}");
            process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn fixture() -> Value {
        json!({
            "schema_version": "1.0", "library_version": "2.0.0", "symbol": "EURUSD", "timeframe": "H1",
            "time_basis": "broker", "as_of": "2026-09-20T09:00:00", "status": "READY", "config": {
                "lookback_bars": 500, "max_records_per_concept": 100, "swing_strength": 5,
                "displacement_baseline": 20, "displacement_multiplier": 1.5, "displacement_body_fraction": 0.6,
                "min_fvg_pips": 2.0, "max_zone_age": 200, "bpr_max_separation": 50, "po3_expiry_bars": 20,
                "smt_symbol": "", "smt_radius": 1, "enable_draw": false, "enable_calendar": true,
                "enable_smt": false, "enable_po3": true, "enable_displacement": true, "enable_mss": true,
                "enable_ifvg": true, "enable_bpr": true, "enable_cs": false, "enable_vix": false,
                "sessions": [
                    {"name":"Asian", "start_minute":0, "end_minute":480},
                    {"name":"London", "start_minute":420, "end_minute":960},
                    {"name":"New York", "start_minute":720, "end_minute":1260}
                ]
            }, "modules": [{"concept":"FVG", "status":"READY", "as_of":"2026-09-20T09:00:00", "truncated":false, "message":""}],
            "records": [{ "id": "a", "concept": "FVG", "source_time": "2026-09-20T07:00:00",
                "confirmed_at": "2026-09-20T08:00:00", "updated_at": "2026-09-20T09:00:00", "direction": "bullish",
                "lower": 1.1, "upper": 1.2, "state": "ACTIVE", "active": true, "related_ids": [],
                "period_start": null, "period_end": null, "reference_price": 0.0, "comparison_price": 0.0, "strength": 1.0, "reason": "" }]
        })
    }

    #[test]
    fn prints_and_filters_records() {
        let data = fixture();
        let expected = "status=READY symbol=EURUSD timeframe=H1 as_of=2026-09-20T09:00:00 time_basis=broker\na\tFVG\tbullish\tACTIVE\t1.10000000\t1.20000000\n";
        assert_eq!(
            render(&data, Some("FVG"), Some("bullish")).unwrap(),
            expected
        );
        assert_eq!(
            render(&data, None, Some("bearish"))
                .unwrap()
                .lines()
                .count(),
            1
        );
    }

    #[test]
    fn permits_unknown_uppercase_concept_filter() {
        assert!(valid_concept("FUTURE_CONCEPT_1"));
        assert!(!valid_concept("future_concept"));
        assert!(!valid_concept("1_FVG"));
        let output = render(&fixture(), Some("FUTURE_CONCEPT_1"), None).unwrap();
        assert_eq!(output.lines().count(), 1);
    }

    #[test]
    fn permits_additive_fields_and_null_as_of() {
        let mut data = fixture();
        data["as_of"] = Value::Null;
        data["extension"] = json!({"future": true});
        data["records"][0]["extension"] = json!(42);
        assert!(render(&data, None, None).unwrap().contains("as_of=null"));
    }

    #[test]
    fn rejects_invalid_contract_values_even_when_filtered() {
        for (field, value) in [
            ("direction", json!("up")),
            ("concept", json!("fvg")),
            ("active", json!(1)),
            ("upper", json!(1.0)),
            ("lower", json!("1.1")),
            ("lower", Value::Null),
            ("updated_at", json!("2026-09-20T09:00:00Z")),
            ("confirmed_at", json!("2026-02-30T00:00:00")),
            ("related_ids", json!([2])),
            ("state", json!("")),
            ("reason", Value::Null),
        ] {
            let mut data = fixture();
            data["records"][0][field] = value;
            assert!(render(&data, Some("BPR"), None).is_err(), "field {field}");
        }
        let mut data = fixture();
        data["records"][0]
            .as_object_mut()
            .unwrap()
            .remove("period_start");
        assert!(validate(&data).is_err());
        data = fixture();
        data["schema_version"] = json!("2.0");
        assert!(validate(&data).is_err());
        data = fixture();
        data["time_basis"] = json!("UTC");
        assert!(validate(&data).is_err());
        assert!(serde_json::from_str::<Value>("1e999").is_err());
    }

    #[test]
    fn sorts_by_id_before_output() {
        let mut data = fixture();
        let mut second = data["records"][0].clone();
        second["id"] = json!("z");
        data["records"].as_array_mut().unwrap().insert(0, second);
        let output = render(&data, None, None).unwrap();
        assert!(output.lines().nth(1).unwrap().starts_with("a\t"));
        assert!(output.lines().nth(2).unwrap().starts_with("z\t"));
    }

    #[test]
    fn checks_calendar_dates_without_timezone_conversion() {
        assert!(valid_timestamp("2024-02-29T23:59:59"));
        assert!(!valid_timestamp("2025-02-29T23:59:59"));
        assert!(!valid_timestamp("2024-02-29T24:00:00"));
        assert!(!valid_timestamp("2024-02-29T23:59:59Z"));
        assert!(!valid_timestamp("2024-02-29 23:59:59"));
        assert!(!valid_timestamp("éééé-02-29T23:59:59"));
    }

    #[test]
    fn validates_config_modules_and_duplicate_ids() {
        for (field, value) in [
            ("lookback_bars", json!(0)),
            ("lookback_bars", json!(100001)),
            ("swing_strength", json!(5001)),
            ("max_zone_age", json!(10001)),
            ("swing_strength", json!(1.5)),
            ("enable_smt", json!("false")),
            ("displacement_body_fraction", json!(1.1)),
            ("displacement_multiplier", json!(0.0)),
            ("min_fvg_pips", json!(-1)),
            ("smt_radius", json!(-1)),
            ("sessions", json!([])),
        ] {
            let mut data = fixture();
            data["config"][field] = value;
            assert!(validate(&data).is_err(), "config field {field}");
        }
        let mut data = fixture();
        data["config"]["sessions"][0]["start_minute"] = json!(1440);
        assert!(validate(&data).is_err());
        data = fixture();
        data["modules"][0]["truncated"] = json!("false");
        assert!(validate(&data).is_err());
        data = fixture();
        data["modules"][0]["concept"] = json!("FUTURE_CONCEPT");
        assert!(validate(&data).is_err());
        data = fixture();
        let duplicate = data["records"][0].clone();
        data["records"].as_array_mut().unwrap().push(duplicate);
        assert!(validate(&data).is_err());
    }

    #[test]
    fn requires_symbol_only_when_smt_is_enabled() {
        let mut data = fixture();
        assert!(validate(&data).is_ok());
        data["config"]["enable_smt"] = json!(true);
        assert!(validate(&data).is_err());
        data["config"]["smt_symbol"] = json!("GBPUSD");
        assert!(validate(&data).is_ok());
    }

    #[test]
    fn all_required_fields_are_checked() {
        for section in ["root", "config", "module", "record"] {
            let original = fixture();
            let subject = match section {
                "root" => &original,
                "config" => &original["config"],
                "module" => &original["modules"][0],
                _ => &original["records"][0],
            };
            for key in subject.as_object().unwrap().keys() {
                let mut data = original.clone();
                let target = match section {
                    "root" => &mut data,
                    "config" => &mut data["config"],
                    "module" => &mut data["modules"][0],
                    _ => &mut data["records"][0],
                };
                target.as_object_mut().unwrap().remove(key);
                assert!(validate(&data).is_err(), "{section}.{key} must be required");
            }
        }
    }

    #[test]
    fn rejects_missing_or_invalid_arguments() {
        assert!(run(&[]).is_err());
        assert!(run(&["x.json".into(), "--concept".into()]).is_err());
        assert!(run(&["x.json".into(), "--direction".into(), "up".into()]).is_err());
        assert!(run(&["x.json".into(), "--concept".into(), "fvg".into()]).is_err());
    }
}

using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Smc.Examples;

if (args.Length != 1)
{
    Console.Error.WriteLine("Usage: SnapshotReader.Tests <snapshot-v1.json>");
    return 1;
}

var fixturePath = Path.GetFullPath(args[0]);
var fixture = File.ReadAllText(fixturePath);
var expected = File.ReadAllLines(Path.ChangeExtension(fixturePath, "expected.txt"));
var checks = 0;

void Check(bool condition, string description)
{
    checks++;
    if (!condition)
        throw new Exception($"FAIL: {description}");
}

string Change(Action<JsonObject> mutation)
{
    var copy = JsonNode.Parse(fixture)!.AsObject();
    mutation(copy);
    return copy.ToJsonString();
}

void Reject(string input, string description, string? concept = null, string? direction = null)
{
    try
    {
        SnapshotReader.Read(input, concept, direction);
    }
    catch (Exception error) when (error is InvalidDataException or JsonException)
    {
        checks++;
        return;
    }
    throw new Exception($"FAIL: accepted {description}");
}

JsonObject FirstRecord(JsonObject root) => root["records"]![0]!.AsObject();

CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("fr-FR");
Check(SnapshotReader.Read(fixture).SequenceEqual(expected), "shared fixture output matches with non-English locale");
var filtered = SnapshotReader.Read(fixture, "FVG", "bullish");
Check(filtered.Count == 2 && filtered[1].StartsWith("fvg-001\t", StringComparison.Ordinal), "concept and direction filtering");
Check(SnapshotReader.Read(fixture, "FVG", "bearish").Count == 1, "empty result retains header");
Check(SnapshotReader.Read(Change(root => root["as_of"] = null))[0].Contains("as_of=null", StringComparison.Ordinal), "nullable as_of");
Check(SnapshotReader.Read(Change(root => root["schema_version"] = "1.42")).Count == expected.Length, "additive minor version");
Check(SnapshotReader.Read(Change(root => root["message"] = "")).SequenceEqual(expected), "optional empty header message");
Check(SnapshotReader.Read(Change(root => root["message"] = "Waiting for history")).SequenceEqual(expected), "optional header message");
Check(SnapshotReader.Read(Change(root =>
{
    root["future"] = new JsonObject { ["anything"] = true };
    root["config"]!["future"] = "accepted";
    FirstRecord(root)["future"] = 42;
})).SequenceEqual(expected), "unknown additive fields");

foreach (var (price, formatted) in new (double, string)[]
{
    (0.001953125, "0.00195312"), (-0.001953125, "-0.00195312"),
    (1.000000005, "1.00000000"), (-1.000000005, "-1.00000000"),
    (0.0, "0.00000000"), (-0.0, "0.00000000"),
    (1e-12, "0.00000000"), (-1e-12, "0.00000000"),
    (1e21, "1000000000000000000000.00000000"),
    (-1e21, "-1000000000000000000000.00000000")
})
{
    var input = Change(root =>
    {
        FirstRecord(root)["lower"] = price;
        FirstRecord(root)["upper"] = price;
    });
    var recordId = FirstRecord(JsonNode.Parse(fixture)!.AsObject())["id"]!.GetValue<string>();
    var rendered = SnapshotReader.Read(input).Single(line => line.StartsWith(recordId + "\t", StringComparison.Ordinal));
    Check(rendered.EndsWith($"\t{formatted}\t{formatted}", StringComparison.Ordinal), $"exact binary64 price rendering: {price:R}");
}

// Every required field in the fixture must remain required, including nested data.
var source = JsonNode.Parse(fixture)!.AsObject();
foreach (var name in source.Select(entry => entry.Key))
    Reject(Change(root => root.Remove(name)), $"missing header field {name}");
foreach (var name in source["config"]!.AsObject().Select(entry => entry.Key))
    Reject(Change(root => root["config"]!.AsObject().Remove(name)), $"missing config field {name}");
foreach (var name in source["config"]!["sessions"]![0]!.AsObject().Select(entry => entry.Key))
    Reject(Change(root => root["config"]!["sessions"]![0]!.AsObject().Remove(name)), $"missing session field {name}");
foreach (var name in source["modules"]![0]!.AsObject().Select(entry => entry.Key))
    Reject(Change(root => root["modules"]![0]!.AsObject().Remove(name)), $"missing module field {name}");
foreach (var name in FirstRecord(source).Select(entry => entry.Key))
    Reject(Change(root => FirstRecord(root).Remove(name)), $"missing record field {name}");

Reject("{}", "empty snapshot");
Reject("[]", "array root");
Reject("null", "null root");
Reject("{", "malformed JSON");
Reject(fixture, "lowercase concept filter", "fvg");
Reject(fixture, "invalid direction filter", direction: "long");
Reject(Change(root => root["schema_version"] = "2.0"), "unsupported version");
Reject(Change(root => root["schema_version"] = "1.0\n"), "invalid version suffix");
Reject(Change(root => root["status"] = "UNKNOWN"), "unknown status");
Reject(Change(root => root["message"] = null), "null header message");
Reject(Change(root => root["message"] = 42), "numeric header message");
Reject(Change(root => root["message"] = true), "boolean header message");
Reject(Change(root => root["message"] = new JsonObject()), "object header message");
Reject(Change(root => root["time_basis"] = "UTC"), "UTC time basis");
Reject(Change(root => root["symbol"] = 42), "non-string symbol");
Reject(Change(root => root["as_of"] = "2026-09-18T12:00:00Z"), "UTC suffix");
Reject(Change(root => root["as_of"] = "2026-02-30T12:00:00"), "impossible calendar date");
Reject(Change(root => root["config"]!["lookback_bars"] = 0), "nonpositive lookback");
Reject(Change(root => root["config"]!["lookback_bars"] = 100001), "excessive lookback");
Reject(Change(root => root["config"]!["swing_strength"] = 1.5), "fractional integer field");
Reject(Change(root => root["config"]!["enable_draw"] = "false"), "string boolean");
Reject(Change(root => root["config"]!["enable_smt"] = true), "enabled SMT without comparison symbol");
Reject(Change(root => root["config"]!["displacement_body_fraction"] = 1.1), "invalid body fraction");
Reject(Change(root => root["config"]!["sessions"]![0]!["start_minute"] = 1440), "invalid session minute");
Reject(Change(root => root["modules"]![0]!["status"] = "UNKNOWN"), "invalid module status");
Reject(Change(root => FirstRecord(root)["concept"] = "UNKNOWN"), "unknown record concept");
Reject(Change(root => FirstRecord(root)["direction"] = "long"), "invalid record direction");
Reject(Change(root => FirstRecord(root)["lower"] = 10), "reversed bounds");
Reject(Change(root => FirstRecord(root)["lower"] = "NaN"), "string price");
Reject(Change(root => FirstRecord(root)["reference_price"] = null), "null numeric field");
Reject(Change(root => FirstRecord(root)["active"] = 1), "non-boolean active");
Reject(Change(root => FirstRecord(root)["related_ids"] = new JsonArray(1)), "non-string related ID");
Reject(Change(root => root["records"]!.AsArray().Add(FirstRecord(root).DeepClone())), "duplicate ID");
Reject(Change(root => FirstRecord(root)["direction"] = "bad"), "invalid record hidden by filter", "ORDER_BLOCK");
Reject(Change(root => FirstRecord(root)["lower"] = 999).Replace("999", "1e999", StringComparison.Ordinal), "non-finite number");

Console.WriteLine($"C# snapshot reader: {checks} checks passed");
return 0;

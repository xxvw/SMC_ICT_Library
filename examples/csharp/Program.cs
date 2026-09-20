using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Smc.Examples;

public static class Program
{
    public static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0)
                throw new InvalidDataException("Usage: SnapshotReader <snapshot.json> [--concept CONCEPT] [--direction bullish|bearish|neutral]");
            string? concept = null;
            string? direction = null;
            for (var index = 1; index < args.Length; index += 2)
            {
                if (index + 1 >= args.Length)
                    throw new InvalidDataException($"Missing value for {args[index]}");
                switch (args[index])
                {
                    case "--concept" when concept is null:
                        concept = args[index + 1];
                        break;
                    case "--direction" when direction is null:
                        direction = args[index + 1];
                        break;
                    default:
                        throw new InvalidDataException($"Unknown or repeated option: {args[index]}");
                }
            }
            var lines = SnapshotReader.Read(File.ReadAllText(args[0]), concept, direction);
            Console.Write(string.Join('\n', lines) + "\n");
            return 0;
        }
        catch (Exception error) when (error is InvalidDataException or IOException or UnauthorizedAccessException or JsonException or ArgumentException)
        {
            Console.Error.WriteLine($"error: {error.Message}");
            return 1;
        }
    }
}

public static class SnapshotReader
{
    private static readonly HashSet<string> Statuses = ["READY", "PARTIAL", "NOT_READY", "ERROR", "DISABLED"];
    private static readonly HashSet<string> Directions = ["bullish", "bearish", "neutral"];
    private static readonly HashSet<string> Concepts =
    [
        "SWING_HIGH", "SWING_LOW", "BOS", "CHOCH", "ORDER_BLOCK", "FVG", "LIQUIDITY",
        "PREMIUM_DISCOUNT", "OTE", "KILL_ZONE", "BREAKER", "DISPLACEMENT", "MSS", "IFVG", "BPR",
        "PREVIOUS_DAY_HIGH", "PREVIOUS_DAY_LOW", "PREVIOUS_WEEK_HIGH", "PREVIOUS_WEEK_LOW",
        "SESSION_HIGH", "SESSION_LOW", "DAILY_GAP", "WEEKLY_GAP", "SMT", "PO3"
    ];

    public static IReadOnlyList<string> Read(string json, string? concept = null, string? direction = null)
    {
        if (concept is not null && !IsConcept(concept))
            throw new InvalidDataException("--concept must be an uppercase concept name");
        if (direction is not null && !Directions.Contains(direction))
            throw new InvalidDataException("--direction must be bullish, bearish, or neutral");
        using var document = JsonDocument.Parse(json);
        var snapshot = document.RootElement;
        Object(snapshot, "snapshot");
        var version = Text(snapshot, "schema_version");
        if (!Regex.IsMatch(version, @"\A1\.[0-9]+\z", RegexOptions.CultureInvariant))
            throw new InvalidDataException("schema_version must use supported major version 1 (1.<minor>)");
        Text(snapshot, "library_version");
        var symbol = Text(snapshot, "symbol");
        var timeframe = Text(snapshot, "timeframe");
        if (Text(snapshot, "time_basis") != "broker")
            throw new InvalidDataException("time_basis must be broker");
        var asOf = Timestamp(snapshot, "as_of", nullable: true);
        var status = Choice(snapshot, "status", Statuses);
        if (snapshot.TryGetProperty("message", out var message))
            String(message, "message", allowEmpty: true);
        ValidateConfig(Property(snapshot, "config"));
        foreach (var module in Array(snapshot, "modules"))
            ValidateModule(module);
        var records = Array(snapshot, "records").ToArray();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var record in records)
        {
            ValidateRecord(record);
            if (!ids.Add(Text(record, "id")))
                throw new InvalidDataException("record IDs must be unique");
        }
        var lines = new List<string>
        {
            $"status={status} symbol={symbol} timeframe={timeframe} as_of={asOf ?? "null"} time_basis=broker"
        };
        foreach (var record in records.OrderBy(record => Text(record, "id"), StringComparer.Ordinal))
        {
            if (concept is not null && Text(record, "concept") != concept)
                continue;
            if (direction is not null && Text(record, "direction") != direction)
                continue;
            lines.Add(string.Join('\t', Text(record, "id"), Text(record, "concept"),
                Text(record, "direction"), Text(record, "state"),
                FormatPrice(Number(record, "lower")), FormatPrice(Number(record, "upper"))));
        }
        return lines;
    }

    // .NET formats the exact binary64 value with nearest, ties-to-even rounding.
    private static string FormatPrice(double value)
    {
        var formatted = value.ToString("F8", CultureInfo.InvariantCulture);
        return formatted == "-0.00000000" ? "0.00000000" : formatted;
    }

    private static void ValidateConfig(JsonElement config)
    {
        Object(config, "config");
        foreach (var field in new[] { "lookback_bars", "max_records_per_concept" })
            Integer(config, field, 1, 100000);
        foreach (var field in new[] { "swing_strength", "displacement_baseline" })
            Integer(config, field, 1, 5000);
        foreach (var field in new[] { "max_zone_age", "bpr_max_separation", "po3_expiry_bars" })
            Integer(config, field, 1, 10000);
        Integer(config, "smt_radius", 0, 5000);
        if (Number(config, "displacement_multiplier") <= 0)
            throw new InvalidDataException("displacement_multiplier must be positive");
        var fraction = Number(config, "displacement_body_fraction");
        if (fraction <= 0 || fraction > 1)
            throw new InvalidDataException("displacement_body_fraction must be in (0, 1]");
        if (Number(config, "min_fvg_pips") < 0)
            throw new InvalidDataException("min_fvg_pips must be nonnegative");
        var comparisonSymbol = Text(config, "smt_symbol", allowEmpty: true);
        foreach (var field in new[] { "enable_draw", "enable_calendar", "enable_smt", "enable_po3",
            "enable_displacement", "enable_mss", "enable_ifvg", "enable_bpr", "enable_cs", "enable_vix" })
            Boolean(config, field);
        if (Boolean(config, "enable_smt") && comparisonSymbol.Length == 0)
            throw new InvalidDataException("enabled SMT requires a comparison symbol");
        var sessions = Array(config, "sessions").ToArray();
        if (sessions.Length != 3)
            throw new InvalidDataException("config sessions must contain exactly three sessions");
        foreach (var session in sessions)
        {
            Object(session, "session");
            Text(session, "name");
            Integer(session, "start_minute", 0, 1439);
            Integer(session, "end_minute", 0, 1439);
        }
    }

    private static void ValidateModule(JsonElement module)
    {
        Object(module, "module");
        Choice(module, "concept", Concepts);
        Choice(module, "status", Statuses);
        Timestamp(module, "as_of", nullable: true);
        Boolean(module, "truncated");
        Text(module, "message", allowEmpty: true);
    }

    private static void ValidateRecord(JsonElement record)
    {
        Object(record, "record");
        Text(record, "id");
        Choice(record, "concept", Concepts);
        Timestamp(record, "source_time");
        Timestamp(record, "confirmed_at");
        Timestamp(record, "updated_at");
        Choice(record, "direction", Directions);
        var lower = Number(record, "lower");
        var upper = Number(record, "upper");
        if (lower > upper)
            throw new InvalidDataException("record lower must not exceed upper");
        Text(record, "state");
        Boolean(record, "active");
        foreach (var relatedId in Array(record, "related_ids"))
            String(relatedId, "related_ids item");
        Timestamp(record, "period_start", nullable: true);
        Timestamp(record, "period_end", nullable: true);
        Number(record, "reference_price");
        Number(record, "comparison_price");
        Number(record, "strength");
        Text(record, "reason", allowEmpty: true);
    }

    private static JsonElement Property(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var value))
            throw new InvalidDataException($"Missing required field: {name}");
        return value;
    }

    private static void Object(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException($"{name} must be an object");
    }

    private static string String(JsonElement value, string name, bool allowEmpty = false)
    {
        if (value.ValueKind != JsonValueKind.String || (!allowEmpty && value.GetString()!.Length == 0))
            throw new InvalidDataException($"{name} must be {(allowEmpty ? "a" : "a nonempty")} string");
        return value.GetString()!;
    }

    private static string Text(JsonElement parent, string name, bool allowEmpty = false) =>
        String(Property(parent, name), name, allowEmpty);

    private static JsonElement.ArrayEnumerator Array(JsonElement parent, string name)
    {
        var value = Property(parent, name);
        if (value.ValueKind != JsonValueKind.Array)
            throw new InvalidDataException($"{name} must be an array");
        return value.EnumerateArray();
    }

    private static double Number(JsonElement parent, string name)
    {
        var value = Property(parent, name);
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out var number) || !double.IsFinite(number))
            throw new InvalidDataException($"{name} must be a finite number");
        return number;
    }

    private static bool Boolean(JsonElement parent, string name)
    {
        var value = Property(parent, name);
        if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new InvalidDataException($"{name} must be a boolean");
        return value.GetBoolean();
    }

    private static void Integer(JsonElement parent, string name, double minimum, double maximum = double.MaxValue)
    {
        var value = Number(parent, name);
        if (value != Math.Truncate(value) || value < minimum || value > maximum)
            throw new InvalidDataException($"{name} must be an integer in [{minimum}, {maximum}]");
    }

    private static string Choice(JsonElement parent, string name, HashSet<string> choices)
    {
        var value = Text(parent, name);
        if (!choices.Contains(value))
            throw new InvalidDataException($"Invalid {name}: {value}");
        return value;
    }

    private static string? Timestamp(JsonElement parent, string name, bool nullable = false)
    {
        var value = Property(parent, name);
        if (nullable && value.ValueKind == JsonValueKind.Null)
            return null;
        var text = String(value, name);
        if (!DateTime.TryParseExact(text, "yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out _))
            throw new InvalidDataException($"{name} must be a broker timestamp YYYY-MM-DDTHH:mm:ss");
        return text;
    }

    private static bool IsConcept(string value) =>
        Regex.IsMatch(value, @"\A[A-Z][A-Z0-9_]*\z", RegexOptions.CultureInvariant);
}

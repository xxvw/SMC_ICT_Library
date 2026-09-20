package org.smcict.examples;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;
import org.junit.jupiter.api.io.TempDir;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;

final class SnapshotReaderTest {
    @TempDir Path temporary;

    private static String resource(String name) throws IOException {
        try (var input = Objects.requireNonNull(SnapshotReaderTest.class.getResourceAsStream("/" + name),
                "Shared resource missing: " + name)) {
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private static ObjectNode fixture() throws IOException {
        return (ObjectNode) SnapshotReader.JSON.readTree(resource("snapshot-v1.json"));
    }

    @Test void matchesSharedOutput() throws IOException {
        var snapshot = fixture();
        SnapshotValidation.validate(snapshot);
        assertEquals(resource("snapshot-v1.expected.txt"), SnapshotReader.render(snapshot, null, null));
    }

    @Test void combinesFiltersAndRetainsHeaderForNoMatches() throws IOException {
        var snapshot = fixture();
        String header = resource("snapshot-v1.expected.txt").lines().findFirst().orElseThrow() + "\n";
        assertEquals(header + "fvg-001\tFVG\tbullish\tBROKEN\t1.11000000\t1.11050000\n",
                SnapshotReader.render(snapshot, "FVG", "bullish"));
        assertEquals(header, SnapshotReader.render(snapshot, "FVG", "bearish"));
    }

    @Test void permitsAdditiveFieldsAndMinorVersions() throws IOException {
        var snapshot = fixture();
        snapshot.put("schema_version", "1.42");
        for (String path : List.of("", "/config", "/config/sessions/0", "/modules/0", "/records/0")) {
            ((ObjectNode) snapshot.at(path)).putObject("new_metadata").put("value", true);
        }
        ((ObjectNode) snapshot.at("/records/0")).put("state", "FUTURE_STATE");
        assertDoesNotThrow(() -> SnapshotValidation.validate(snapshot));
    }

    @Test void permitsNullableUnavailableValuesAndEmptyResults() throws IOException {
        var snapshot = fixture();
        snapshot.put("status", "NOT_READY");
        snapshot.putNull("as_of");
        snapshot.putArray("records");
        assertDoesNotThrow(() -> SnapshotValidation.validate(snapshot));
        assertEquals("status=NOT_READY symbol=EURUSD timeframe=M5 as_of=null time_basis=broker\n",
                SnapshotReader.render(snapshot, null, null));
    }

    @TestFactory Stream<DynamicTest> pricesRoundExactBinary64WithTiesToEven() {
        String[][] cases = {
                {"0.001953125", "0.00195312"}, {"-0.001953125", "-0.00195312"},
                {"0.005859375", "0.00585938"}, {"-0.005859375", "-0.00585938"},
                {"1.000000005", "1.00000000"}, {"-1.000000005", "-1.00000000"},
                {"0.0", "0.00000000"}, {"-0.0", "0.00000000"},
                {"-0.000000001", "0.00000000"}
        };
        return Stream.of(cases).map(test -> DynamicTest.dynamicTest("price " + test[0], () -> {
            var snapshot = fixture();
            ObjectNode record = (ObjectNode) snapshot.at("/records/0");
            JsonNode price = SnapshotReader.JSON.readTree(test[0]);
            record.set("lower", price);
            record.set("upper", price);
            SnapshotValidation.validate(snapshot);
            String line = SnapshotReader.render(snapshot, "MSS", null).lines().skip(1).findFirst().orElseThrow();
            assertEquals("mss-001\tMSS\tbearish\tCONFIRMED\t" + test[1] + "\t" + test[1], line);
        }));
    }

    @Test void optionalTopLevelMessageMustBeAString() throws IOException {
        var snapshot = fixture();
        snapshot.remove("message");
        assertDoesNotThrow(() -> SnapshotValidation.validate(snapshot));
        snapshot.put("message", "Waiting for broker history");
        assertDoesNotThrow(() -> SnapshotValidation.validate(snapshot));
        snapshot.put("message", "");
        assertDoesNotThrow(() -> SnapshotValidation.validate(snapshot));
        for (String invalid : List.of("null", "0", "false", "[]", "{}")) {
            snapshot.set("message", SnapshotReader.JSON.readTree(invalid));
            assertThrows(IllegalArgumentException.class, () -> SnapshotValidation.validate(snapshot));
        }
    }

    @TestFactory Stream<DynamicTest> everyRequiredFieldIsChecked() throws IOException {
        List<DynamicTest> tests = new ArrayList<>();
        for (String path : List.of("", "/config", "/config/sessions/0", "/modules/0", "/records/0")) {
            var fields = fixture().at(path).fieldNames();
            while (fields.hasNext()) {
                String field = fields.next();
                tests.add(DynamicTest.dynamicTest("required " + path + "/" + field, () -> {
                    var snapshot = fixture();
                    ((ObjectNode) snapshot.at(path)).remove(field);
                    assertThrows(IllegalArgumentException.class, () -> SnapshotValidation.validate(snapshot));
                }));
            }
        }
        return tests.stream();
    }

    @TestFactory Stream<DynamicTest> rejectsInvalidValues() {
        String[][] cases = {
                {"/schema_version", "\"2.0\""}, {"/schema_version", "1"},
                {"/library_version", "null"}, {"/symbol", "\"\""},
                {"/status", "\"STALE\""}, {"/time_basis", "\"UTC\""},
                {"/as_of", "\"2026-02-30T12:00:00\""}, {"/as_of", "\"2026-09-18T12:00:00Z\""},
                {"/config", "[]"}, {"/config/lookback_bars", "0"}, {"/config/lookback_bars", "1.5"},
                {"/config/enable_calendar", "\"true\""}, {"/config/displacement_multiplier", "0"},
                {"/config/displacement_body_fraction", "1.1"}, {"/config/min_fvg_pips", "-1"},
                {"/config/smt_radius", "-1"}, {"/config/sessions", "[]"},
                {"/config/sessions/0/start_minute", "1440"},
                {"/config/sessions/0/end_minute", "0"}, {"/config/sessions/0/name", "\"London\""},
                {"/config/enable_smt", "true"}, {"/modules", "{}"},
                {"/modules/0/concept", "\"UNKNOWN\""}, {"/modules/0/status", "\"UNKNOWN\""},
                {"/modules/0/as_of", "\"2025-02-29T12:00:00\""},
                {"/modules/0/truncated", "0"}, {"/modules/0/message", "null"},
                {"/records", "null"}, {"/records/0/id", "\"\""},
                {"/records/0/id", "\"fvg-001\""}, {"/records/0/concept", "\"ICT_MSS\""},
                {"/records/0/source_time", "null"}, {"/records/0/confirmed_at", "\"invalid\""},
                {"/records/0/updated_at", "\"2026-09-18T24:00:00\""},
                {"/records/0/direction", "\"up\""}, {"/records/0/lower", "2"},
                {"/records/0/lower", "\"1.0\""}, {"/records/0/upper", "1e999"},
                {"/records/0/state", "\"\""}, {"/records/0/active", "1"},
                {"/records/0/related_ids", "[1]"}, {"/records/0/related_ids", "[\"\"]"},
                {"/records/0/period_start", "\"2026-02-30T12:00:00\""},
                {"/records/0/period_end", "\"2026-09-18T12:00:00+00:00\""},
                {"/records/0/reference_price", "null"}, {"/records/0/comparison_price", "true"},
                {"/records/0/strength", "1e999"}, {"/records/0/reason", "false"}
        };
        return Stream.of(cases).map(test -> DynamicTest.dynamicTest(test[0] + "=" + test[1], () -> {
            var snapshot = fixture();
            int separator = test[0].lastIndexOf('/');
            ObjectNode parent = (ObjectNode) snapshot.at(test[0].substring(0, separator));
            parent.set(test[0].substring(separator + 1), SnapshotReader.JSON.readTree(test[1]));
            assertThrows(IllegalArgumentException.class, () -> SnapshotValidation.validate(snapshot));
        }));
    }

    @Test void allowsMoreThanTwoRelatedIdsAndOvernightSessions() throws IOException {
        var snapshot = fixture();
        ((ArrayNode) snapshot.at("/records/0/related_ids")).add("third-source");
        ((ObjectNode) snapshot.at("/config/sessions/0")).put("start_minute", 1320).put("end_minute", 120);
        assertDoesNotThrow(() -> SnapshotValidation.validate(snapshot));
    }

    @Test void cliReadsUtf8PathAndValidatesBeforeFiltering() throws IOException {
        Path input = temporary.resolve("snapshot 日本語.json");
        Files.writeString(input, resource("snapshot-v1.json"));
        var valid = invoke(input.toString());
        assertEquals(0, valid.code());
        assertEquals(resource("snapshot-v1.expected.txt"), valid.output());
        assertEquals("", valid.error());
        var snapshot = fixture();
        ((ObjectNode) snapshot.at("/records/0")).putNull("reason");
        Files.writeString(input, snapshot.toString());
        var invalid = invoke(input.toString(), "--concept", "FVG");
        assertEquals(2, invalid.code());
        assertEquals("", invalid.output());
        assertTrue(invalid.error().startsWith("error: "));
    }

    @Test void cliRejectsMalformedJsonAndArguments() throws IOException {
        Path input = temporary.resolve("bad.json");
        for (String json : List.of("", "null", "[]", "{\"x\":1,\"x\":2}", resource("snapshot-v1.json") + " {}")) {
            Files.writeString(input, json);
            assertEquals(2, invoke(input.toString()).code());
        }
        Files.write(input, new byte[] {(byte) 0xff});
        assertEquals(2, invoke(input.toString()).code());
        assertEquals(2, invoke(temporary.resolve("missing.json").toString()).code());
        assertEquals(2, invoke().code());
        assertEquals(2, invoke(input.toString(), "--concept").code());
        assertEquals(2, invoke(input.toString(), "--concept", "fvg").code());
        assertEquals(2, invoke(input.toString(), "--direction", "up").code());
        assertEquals(2, invoke(input.toString(), "--concept", "FVG", "--concept", "IFVG").code());
        assertEquals(2, invoke(input.toString(), "--unknown", "x").code());
    }

    private record Result(int code, String output, String error) {}

    private static Result invoke(String... args) {
        var output = new ByteArrayOutputStream();
        var error = new ByteArrayOutputStream();
        int code = SnapshotReader.run(args,
                new PrintStream(output, true, StandardCharsets.UTF_8),
                new PrintStream(error, true, StandardCharsets.UTF_8));
        return new Result(code, output.toString(StandardCharsets.UTF_8), error.toString(StandardCharsets.UTF_8));
    }
}

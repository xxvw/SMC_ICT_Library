package org.smcict.examples;

import com.fasterxml.jackson.databind.JsonNode;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SpecVersion;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;
import java.util.HashSet;
import java.util.Set;

/** Validates against the repository schema bundled into the executable JAR. */
final class SnapshotValidation {
    private static final DateTimeFormatter BROKER_TIMESTAMP = DateTimeFormatter
            .ofPattern("uuuu-MM-dd'T'HH:mm:ss")
            .withResolverStyle(ResolverStyle.STRICT);

    private SnapshotValidation() {}

    static void validate(JsonNode snapshot) {
        if (snapshot == null) {
            throw new IllegalArgumentException("snapshot must be a JSON object");
        }
        finiteNumbers(snapshot, "$");
        var errors = schema().validate(snapshot);
        if (!errors.isEmpty()) {
            String first = errors.stream().map(Object::toString).sorted().findFirst().orElseThrow();
            throw new IllegalArgumentException("invalid snapshot: " + first);
        }
        timestamp(snapshot.get("as_of"), "$.as_of");
        Set<String> sessionNames = new HashSet<>();
        for (JsonNode session : snapshot.get("config").get("sessions")) {
            if (!sessionNames.add(session.get("name").textValue())) {
                throw new IllegalArgumentException("session names must be unique");
            }
            if (session.get("start_minute").intValue() == session.get("end_minute").intValue()) {
                throw new IllegalArgumentException("session start_minute and end_minute must differ");
            }
        }
        if (snapshot.get("config").get("enable_smt").booleanValue()
                && snapshot.get("config").get("smt_symbol").textValue().isEmpty()) {
            throw new IllegalArgumentException("enable_smt requires smt_symbol");
        }
        for (JsonNode module : snapshot.get("modules")) {
            timestamp(module.get("as_of"), "$.modules[].as_of");
        }
        Set<String> ids = new HashSet<>();
        for (JsonNode record : snapshot.get("records")) {
            String id = record.get("id").textValue();
            if (!ids.add(id)) {
                throw new IllegalArgumentException("duplicate record id: " + id);
            }
            if (record.get("lower").decimalValue().compareTo(record.get("upper").decimalValue()) > 0) {
                throw new IllegalArgumentException("record " + id + ": lower must not exceed upper");
            }
            for (String field : Set.of("source_time", "confirmed_at", "updated_at", "period_start", "period_end")) {
                timestamp(record.get(field), "record " + id + "." + field);
            }
        }
    }

    private static JsonSchema schema() {
        try (var input = SnapshotValidation.class.getResourceAsStream("/snapshot.schema.json")) {
            if (input == null) {
                throw new IllegalArgumentException("snapshot.schema.json is missing from the JAR; rebuild from the repository");
            }
            return JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)
                    .getSchema(SnapshotReader.JSON.readTree(input));
        } catch (IOException ex) {
            throw new IllegalArgumentException("cannot load bundled snapshot schema", ex);
        }
    }

    private static void finiteNumbers(JsonNode value, String path) {
        if (value.isNumber() && !Double.isFinite(value.doubleValue())) {
            throw new IllegalArgumentException(path + " must be a finite number");
        }
        if (value.isObject()) {
            var fields = value.fields();
            while (fields.hasNext()) {
                var field = fields.next();
                finiteNumbers(field.getValue(), path + "." + field.getKey());
            }
        } else if (value.isArray()) {
            for (int i = 0; i < value.size(); i++) {
                finiteNumbers(value.get(i), path + "[" + i + "]");
            }
        }
    }

    private static void timestamp(JsonNode value, String path) {
        if (value.isNull()) {
            return;
        }
        try {
            LocalDateTime.parse(value.textValue(), BROKER_TIMESTAMP);
        } catch (DateTimeParseException ex) {
            throw new IllegalArgumentException(path + " must be a valid broker timestamp YYYY-MM-DDTHH:mm:ss");
        }
    }
}

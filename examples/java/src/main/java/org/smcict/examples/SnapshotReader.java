package org.smcict.examples;

import com.fasterxml.jackson.core.StreamReadFeature;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.PrintStream;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;

/** Reads the MT5 snapshot contract. Detection remains in the MQL5 library. */
public final class SnapshotReader {
    static final JsonMapper JSON = JsonMapper.builder()
            .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)
            .build();

    private SnapshotReader() {}

    public static void main(String[] args) {
        System.exit(run(args, System.out, System.err));
    }

    static int run(String[] args, PrintStream out, PrintStream err) {
        try {
            Options options = Options.parse(args);
            JsonNode snapshot;
            try (var reader = Files.newBufferedReader(options.path(), StandardCharsets.UTF_8)) {
                snapshot = JSON.readTree(reader);
            }
            SnapshotValidation.validate(snapshot);
            out.print(render(snapshot, options.concept(), options.direction()));
            return 0;
        } catch (IOException | IllegalArgumentException ex) {
            err.println("error: " + ex.getMessage());
            return 2;
        }
    }

    static String render(JsonNode snapshot, String concept, String direction) {
        StringBuilder output = new StringBuilder();
        output.append("status=").append(snapshot.get("status").textValue())
                .append(" symbol=").append(snapshot.get("symbol").textValue())
                .append(" timeframe=").append(snapshot.get("timeframe").textValue())
                .append(" as_of=").append(snapshot.get("as_of").isNull()
                        ? "null" : snapshot.get("as_of").textValue())
                .append(" time_basis=broker\n");
        List<JsonNode> selected = new ArrayList<>();
        for (JsonNode record : snapshot.get("records")) {
            if ((concept == null || concept.equals(record.get("concept").textValue()))
                    && (direction == null || direction.equals(record.get("direction").textValue()))) {
                selected.add(record);
            }
        }
        selected.sort(Comparator.comparing(record -> record.get("id").textValue()));
        for (JsonNode record : selected) {
            output.append(record.get("id").textValue()).append('\t')
                    .append(record.get("concept").textValue()).append('\t')
                    .append(record.get("direction").textValue()).append('\t')
                    .append(record.get("state").textValue()).append('\t')
                    .append(formatPrice(record.get("lower").doubleValue()))
                    .append('\t')
                    .append(formatPrice(record.get("upper").doubleValue()))
                    .append('\n');
        }
        return output.toString();
    }

    private static String formatPrice(double value) {
        // Construct from the exact binary64 value, not its shortest decimal string.
        BigDecimal rounded = new BigDecimal(value).setScale(8, RoundingMode.HALF_EVEN);
        return rounded.signum() == 0 ? "0.00000000" : rounded.toPlainString();
    }

    private record Options(Path path, String concept, String direction) {
        static Options parse(String[] args) {
            if (args.length == 0 || args[0].startsWith("--")) {
                throw new IllegalArgumentException("usage: java -jar snapshot-reader-1.0.0.jar "
                        + "SNAPSHOT.json [--concept CONCEPT] [--direction bullish|bearish|neutral]");
            }
            String concept = null;
            String direction = null;
            for (int index = 1; index < args.length; index += 2) {
                String flag = args[index];
                if (index + 1 == args.length) {
                    throw new IllegalArgumentException("missing value for " + flag);
                }
                String value = args[index + 1];
                switch (flag) {
                    case "--concept" -> {
                        if (concept != null || !value.matches("[A-Z][A-Z0-9_]*")) {
                            throw new IllegalArgumentException("--concept must occur once and use uppercase letters, digits or underscores");
                        }
                        concept = value;
                    }
                    case "--direction" -> {
                        if (direction != null || !Set.of("bullish", "bearish", "neutral").contains(value)) {
                            throw new IllegalArgumentException("--direction must occur once and be bullish, bearish or neutral");
                        }
                        direction = value;
                    }
                    default -> throw new IllegalArgumentException("unknown option: " + flag);
                }
            }
            return new Options(Path.of(args[0]), concept, direction);
        }
    }
}

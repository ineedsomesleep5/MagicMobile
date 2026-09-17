import com.google.gson.Gson;
import com.google.gson.JsonObject;
import mage.filter.FilterMana;
import com.j256.ormlite.dao.DaoManager;
import com.j256.ormlite.dao.Dao;
import com.j256.ormlite.jdbc.JdbcConnectionSource;
import io.magicmobile.core.Json;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.MobileCardFactories;
import mage.cards.Sets;
import mage.cards.repository.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.Supplier;
import java.util.zip.GZIPOutputStream;

/** BUILD TIME ONLY: export original XMage/H2 query results into immutable bundled data. */
public final class CardMetadataExporter {
    private static final Gson GSON = new Gson();
    private static BufferedWriter compressed(Path file) throws IOException {
        return new BufferedWriter(new OutputStreamWriter(new GZIPOutputStream(Files.newOutputStream(file)), StandardCharsets.UTF_8));
    }
    private static String hash(Path file) throws Exception {
        MessageDigest hash = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(file)) {
            byte[] buffer = new byte[65536];
            for (int n; (n = input.read(buffer)) >= 0;) hash.update(buffer, 0, n);
        }
        return HexFormat.of().formatHex(hash.digest());
    }
    public static void main(String[] args) throws Exception {
        Path output = Path.of(args[0]);
        Files.createDirectories(output);
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        List<String> errors = new ArrayList<>();
        CardScanner.scan(errors);
        if (!errors.isEmpty()) throw new IllegalStateException("XMage metadata export failed: " + errors);
        List<CardInfo> rows;
        try (JdbcConnectionSource source = new JdbcConnectionSource(DatabaseUtils.prepareH2Connection(DatabaseUtils.DB_NAME_CARDS, true))) {
            Dao<CardInfo, Object> cards = DaoManager.createDao(source, CardInfo.class);
            rows = cards.queryForAll();
        }
        int printings = Sets.getInstance().values().stream().mapToInt(set -> set.getSetCardInfo().size()).sum();
        long mainRows = rows.stream().filter(row -> !row.isSplitCardHalf()).count();
        if (mainRows != printings) throw new IllegalStateException("Metadata export lost printings: " + mainRows + " != " + printings);
        // SQL without ORDER BY has no specified order. Make bundled rows reproducible, main split cards first.
        rows.sort(Comparator.comparing(CardInfo::getSetCode).thenComparing(CardInfo::getCardNumber)
                .thenComparing(CardInfo::isSplitCardHalf).thenComparing(CardInfo::isNightCard).thenComparing(CardInfo::getName));
        Path metadata = output.resolve("card-metadata.jsonl.gz");
        try (BufferedWriter stream = compressed(metadata)) {
            stream.write(Json.write(Json.map("format", 1, "rows", rows.size())));stream.newLine();
            for (CardInfo row : rows) {
                JsonObject data = GSON.toJsonTree(row).getAsJsonObject();
                // Synthetic split-half repository rows are not independently creatable.
                // The main card already includes both halves in its engine identity.
                if (row.isSplitCardHalf()) {
                    stream.write(GSON.toJson(data));stream.newLine();
                    continue;
                }
                // Ask the actual card, including its reverse/spell/split face. Repository
                // display metadata alone does not contain those faces' color indicators.
                FilterMana identity = row.createCard().getColorIdentity();
                List<String> colors = new ArrayList<>();
                if (identity.isWhite()) colors.add("W");
                if (identity.isBlue()) colors.add("U");
                if (identity.isBlack()) colors.add("B");
                if (identity.isRed()) colors.add("R");
                if (identity.isGreen()) colors.add("G");
                data.add("colorIdentity", GSON.toJsonTree(colors));
                stream.write(GSON.toJson(data));stream.newLine();
            }
        }
        Map<String, Supplier<Set<String>>> queries = new LinkedHashMap<>();
        queries.put("getNames", CardRepository.instance::getNames);
        queries.put("getLandNames", CardRepository.instance::getLandNames);
        queries.put("getNonLandNames", CardRepository.instance::getNonLandNames);
        queries.put("getNonbasicLandNames", CardRepository.instance::getNonbasicLandNames);
        queries.put("getNotBasicLandNames", CardRepository.instance::getNotBasicLandNames);
        queries.put("getCreatureNames", CardRepository.instance::getCreatureNames);
        queries.put("getArtifactNames", CardRepository.instance::getArtifactNames);
        queries.put("getNonLandAndNonCreatureNames", CardRepository.instance::getNonLandAndNonCreatureNames);
        queries.put("getNonArtifactAndNonLandNames", CardRepository.instance::getNonArtifactAndNonLandNames);
        Map<String, Set<String>> names = new LinkedHashMap<>();
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (Map.Entry<String, Supplier<Set<String>>> query : queries.entrySet()) {
            Set<String> values = new TreeSet<>(query.getValue().get());
            if (values.isEmpty()) throw new IllegalStateException("Empty original card-name query: " + query.getKey());
            names.put(query.getKey(), values);counts.put(query.getKey(), values.size());
        }
        Path nameFile = output.resolve("card-names.json.gz");
        try (BufferedWriter stream = compressed(nameFile)) {
            GSON.toJson(Map.of("format", 1, "names", names), stream);
        }
        Map<String, Object> report = Json.map("format", 1, "upstream", "8aea65ae9ae3c89970fe865e1316105539e097ca",
                "registryHash", GeneratedCardFactory.CATALOGUE_HASH, "printings", printings,
                "rowsIncludingSplitHalves", rows.size(), "nameCounts", counts,
                "resources", Json.map("card-metadata.jsonl.gz", hash(metadata), "card-names.json.gz", hash(nameFile)),
                "scope", "Original XMage CardScanner and H2 queries at build time; not native runtime acceptance");
        Files.writeString(output.resolve("card-metadata-report.json"), Json.write(report) + "\n");
        System.out.println(Json.write(report));
    }
}

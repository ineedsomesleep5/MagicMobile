import io.magicmobile.core.Json;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.Sets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Build-time metadata only: uses the same set-type predicate as pinned Commander. */
public final class CommanderSetExporter {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected output path");
        GeneratedSetRegistry.install();
        var codes = Sets.getInstance().values().stream().filter(set -> set.getSetType().isEternalLegal())
            .map(set -> set.getCode()).sorted().toList();
        Files.writeString(Path.of(args[0]), Json.write(Json.map("upstreamCommit",
            "8aea65ae9ae3c89970fe865e1316105539e097ca", "eternalLegalSetCodes", codes)) + "\n");
        System.out.println("Exported " + codes.size() + " upstream eternal-legal set codes");
    }
}

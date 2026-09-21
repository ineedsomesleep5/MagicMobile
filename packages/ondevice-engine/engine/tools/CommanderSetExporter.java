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
            "4825513287ba6c42c32fd205d227f4a5fc44c2f3", "eternalLegalSetCodes", codes)) + "\n");
        System.out.println("Exported " + codes.size() + " upstream eternal-legal set codes");
    }
}

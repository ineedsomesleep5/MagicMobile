import mage.cards.repository.TokenInfo;
import mage.cards.repository.TokenRepository;
import mage.cards.repository.TokenType;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HexFormat;
import java.util.List;

/** Real repository/resource regression, not token rules or iPhone acceptance. */
public final class TokenResourceProbe {
    public static void main(String[] args) throws Exception {
        // Keep this first: the baseline must fail inside upstream's resource loader.
        List<TokenInfo> all = TokenRepository.instance.getAll();
        String tokenClass = "mage.game.permanent.token.SaprolingToken";
        TokenInfo saproling = TokenRepository.instance.findPreferredTokenInfoForClass(tokenClass, null);
        if (all.isEmpty() || saproling == null || saproling.getTokenType() != TokenType.TOKEN
                || !tokenClass.equals(saproling.getFullClassFileName())
                || !"Saproling".equals(saproling.getName()) || saproling.getSetCode().isEmpty()) {
            throw new AssertionError("Real Saproling metadata was not resolved");
        }
        // Compare every parsed row (including built-in XMage metadata), not a reduced fixture.
        List<String> rows = new ArrayList<>();
        for (TokenInfo info : all) {
            rows.add(info.getTokenType() + "\t" + info.getName() + "\t" + info.getSetCode()
                    + "\t" + info.getImageNumber() + "\t" + info.getFullClassFileName()
                    + "\t" + info.getDownloadUrl());
        }
        Collections.sort(rows);
        String metadataHash = hash(String.join("\n", rows).getBytes(StandardCharsets.UTF_8));
        try (InputStream resource = TokenRepository.class.getClassLoader()
                .getResourceAsStream("tokens-database.txt")) {
            if (resource == null) throw new AssertionError("Native token resource disappeared");
            System.out.println("PASS SaprolingToken rows=" + all.size()
                    + " resource=" + hash(resource.readAllBytes()) + " metadata=" + metadataHash);
        }
    }

    private static String hash(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
}

/* SPDX-License-Identifier: MIT. Builder planner tests, NOT engine/device execution. */
import com.oracle.svm.hosted.image.MagicMobileTrampolineLayout;
import java.util.Random;

public final class TrampolineLayoutTests {
    static int checks;
    static void check(boolean value) { checks++; if (!value) throw new AssertionError("check " + checks); }
    static void refused(Runnable block) {
        checks++; try { block.run(); } catch (IllegalArgumentException | ArithmeticException expected) { return; }
        throw new AssertionError("Expected refusal " + checks);
    }
    static void verify(int[] lengths, int[][] targets, int[][] sites, int limit) {
        var result = MagicMobileTrampolineLayout.plan(lengths, targets, sites, 16, limit);
        int next = 0;
        for (int i = 0; i < lengths.length; i++) {
            check(result.starts[i] == next && next % 16 == 0);
            for (int address : result.veneers[i].values()) {
                check(address >= result.starts[i] + lengths[i]);
                check(address + 12 <= result.starts[i] + result.spans[i]);
            }
            for (int j = 0; j < targets[i].length; j++) {
                int target = targets[i][j];
                int address = result.veneers[i].getOrDefault(target, result.starts[target]);
                check(MagicMobileTrampolineLayout.fits((long) address - result.starts[i] - sites[i][j], limit));
            }
            next += result.spans[i];
        }
        check(next == result.size);
    }
    public static void main(String[] args) {
        int limit = MagicMobileTrampolineLayout.ARM64_CALL_LIMIT;
        check(MagicMobileTrampolineLayout.fits(limit, limit));
        check(!MagicMobileTrampolineLayout.fits((long) limit + 4, limit));
        check(!MagicMobileTrampolineLayout.fits(-(long) limit - 4, limit));
        check(!MagicMobileTrampolineLayout.fits(2, limit));
        // Real ARM64 +/-128 MiB boundary, represented as sizes, not allocated filler code.
        int[] lengths = {16, 140 * 1024 * 1024, 16};
        int[][] targets = {{2, 2}, {}, {0}}, sites = {{0, 4}, {}, {0}};
        var layout = MagicMobileTrampolineLayout.plan(lengths, targets, sites, 16, limit);
        check(layout.veneers[0].size() == 1 && layout.veneers[2].size() == 1);
        verify(lengths, targets, sites, limit);
        // Small limits force cascades, sharing and both call directions deterministically.
        Random random = new Random(4096);
        for (int sample = 0; sample < 200; sample++) {
            int n = 4 + random.nextInt(30);
            int[] sizes = new int[n]; int[][] calls = new int[n][], offsets = new int[n][];
            for (int i = 0; i < n; i++) {
                sizes[i] = 16 + 4 * random.nextInt(8);
                int count = random.nextInt(4); calls[i] = new int[count]; offsets[i] = new int[count];
                for (int j = 0; j < count; j++) { calls[i][j] = random.nextInt(n); offsets[i][j] = 0; }
            }
            verify(sizes, calls, offsets, 128);
        }
        refused(() -> MagicMobileTrampolineLayout.plan(new int[]{16}, new int[][]{{1}}, new int[][]{{0}},16,limit));
        refused(() -> MagicMobileTrampolineLayout.plan(new int[]{16}, new int[][]{{0}}, new int[][]{{2}},16,limit));
        refused(() -> MagicMobileTrampolineLayout.plan(new int[]{16}, new int[][]{{}}, new int[][]{{}},3,limit));
        refused(() -> MagicMobileTrampolineLayout.plan(new int[]{Integer.MAX_VALUE - 3,16},new int[][]{{},{}},new int[][]{{},{}},16,limit));
        refused(() -> MagicMobileTrampolineLayout.plan(new int[]{256,16},new int[][]{{1},{}},new int[][]{{0},{}},16,128));
        System.out.println("PASS: " + checks + " compiler-layout assertions; not native XMage execution");
    }
}

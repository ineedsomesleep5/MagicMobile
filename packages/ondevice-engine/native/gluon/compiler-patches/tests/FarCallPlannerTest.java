import com.oracle.svm.hosted.image.FarCallPlanner;
import com.oracle.svm.hosted.image.FarCallPlanner.CallSite;
import com.oracle.svm.hosted.image.FarCallPlanner.Layout;
import java.util.*;

public final class FarCallPlannerTest {
    static int checks;
    static void check(boolean value) { checks++; if (!value) throw new AssertionError("check " + checks); }
    static void rejects(Runnable body) {
        checks++;
        try { body.run(); } catch (IllegalArgumentException | IllegalStateException expected) { return; }
        throw new AssertionError("Expected rejection");
    }
    public static void main(String[] args) {
        check(FarCallPlanner.fitsBranch(-(1L << 27)));
        check(FarCallPlanner.fitsBranch((1L << 27) - 4));
        check(!FarCallPlanner.fitsBranch(1L << 27));
        check(!FarCallPlanner.fitsBranch(-(1L << 27) - 4));
        check(!FarCallPlanner.fitsBranch(3));
        List<CallSite> near = Arrays.asList(new CallSite(0, 1, 0), new CallSite(1, 0, 4));
        Layout n = FarCallPlanner.plan(new int[] {16, 16}, near, 16, FarCallPlanner.MAX_DISTANCE);
        check(n.veneerCount == 0 && n.size == 32 && n.passes == 1);
        List<CallSite> far = Arrays.asList(new CallSite(0, 2, 0), new CallSite(0, 2, 4), new CallSite(2, 0, 0));
        Layout f = FarCallPlanner.plan(new int[] {16, 1 << 27, 16}, far, 16, FarCallPlanner.MAX_DISTANCE);
        check(f.veneerCount == 2 && f.veneers(0).size() == 1 && f.veneers(2).size() == 1);
        check(f.veneers(0).get(2) == 16);
        check(f.veneers(2).get(0) == f.start(2) + 16);
        check(f.extent(0) == 32 && f.extent(2) == 32);
        check(f.size == (1 << 27) + 64 && f.passes == 2);
        // Added veneers push a previously in-range call over the diagnostic threshold.
        List<CallSite> cascade = Arrays.asList(new CallSite(0, 2, 0), new CallSite(1, 4, 0), new CallSite(4, 0, 0));
        Layout c = FarCallPlanner.plan(new int[] {16, 16, 16, 16, 16}, cascade, 16, 32);
        check(c.veneerCount >= 2 && c.passes >= 3);
        for (CallSite call : cascade) check(FarCallPlanner.fitsBranch((long)c.destination(call)-c.start(call.caller)-call.offset));
        rejects(() -> FarCallPlanner.plan(new int[] {12}, near, 16, 4));
        rejects(() -> FarCallPlanner.plan(new int[] {3}, Collections.emptyList(), 16, 4));
        rejects(() -> FarCallPlanner.plan(new int[] {16}, Collections.emptyList(), 3, 4));
        rejects(() -> FarCallPlanner.plan(new int[] {Integer.MAX_VALUE - 3, 16}, Collections.emptyList(), 16, 4));
        rejects(() -> FarCallPlanner.plan(new int[] {(1<<27) + 4, 16}, Collections.singletonList(new CallSite(0,1,0)), 16, 4));
        Random random = new Random(61719);
        for (int iteration = 0; iteration < 500; ++iteration) {
            int count = 2 + random.nextInt(30);
            int[] sizes = new int[count];
            for (int i = 0; i < count; ++i) sizes[i] = 4 * (1 + random.nextInt(300));
            List<CallSite> calls = new ArrayList<>();
            for (int i = 0; i < count * 5; ++i) {
                int caller = random.nextInt(count), callee = random.nextInt(count);
                calls.add(new CallSite(caller, callee, 4 * random.nextInt(sizes[caller] / 4)));
            }
            Layout a = FarCallPlanner.plan(sizes, calls, 16, 64);
            Layout b = FarCallPlanner.plan(sizes, calls, 16, 64);
            check(a.size == b.size && a.veneerCount == b.veneerCount);
            for (int i = 0; i < count; ++i) {
                check(a.start(i) % 16 == 0 && a.extent(i) >= sizes[i]);
                check(a.veneers(i).equals(b.veneers(i)));
                if (i + 1 < count) check(a.start(i) + a.extent(i) == a.start(i + 1));
                for (int address : a.veneers(i).values()) check(address >= a.start(i)+sizes[i] && address+12 <= a.start(i)+a.extent(i));
            }
            for (CallSite call : calls) check(FarCallPlanner.fitsBranch((long)a.destination(call)-a.start(call.caller)-call.offset));
        }
        System.out.println("PASS: FarCallPlanner " + checks + " assertions (layout model, not native execution)");
    }
}

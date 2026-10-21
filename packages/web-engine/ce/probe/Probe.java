// Toolchain smoke test (packages/web-engine/ce/build_web_image_tool.sh): concurrent maps, atomics, a VarHandle and
// reflective field access, the Unsafe-style paths the builder fixes touch. Prints the same line on the JVM and in Wasm.
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.lang.reflect.Field;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.AtomicReference;

public class Probe {
    static class Base { int inherited = 3; }
    static class Box extends Base { int a = 1; String s = "x"; volatile long v; }
    static final VarHandle V;
    static {
        try { V = MethodHandles.lookup().findVarHandle(Box.class, "v", long.class); } catch (ReflectiveOperationException e) { throw new Error(e); }
    }
    public static void main(String[] args) throws Exception {
        ConcurrentHashMap<String, Integer> m = new ConcurrentHashMap<>();
        for (int i = 0; i < 1000; i++) m.merge("k" + (i % 37), 1, Integer::sum);
        AtomicInteger ai = new AtomicInteger(); ai.incrementAndGet();
        AtomicReference<String> ar = new AtomicReference<>("a"); ar.compareAndSet("a", "b");
        AtomicLongArray al = new AtomicLongArray(4); al.addAndGet(2, 5);
        ConcurrentLinkedQueue<Integer> q = new ConcurrentLinkedQueue<>(); q.offer(1); q.offer(2); q.poll();
        Box b = new Box(); V.compareAndSet(b, 0L, 42L);
        Field f = Box.class.getDeclaredField("a"); f.setAccessible(true); f.setInt(b, 7);
        Field g = Box.class.getDeclaredField("s"); g.set(b, "y");
        Field h = Base.class.getDeclaredField("inherited"); h.setInt(b, 9);
        System.out.println("probe " + m.size() + " " + m.get("k0") + " " + ai.get() + " " + ar.get() + " " + al.get(2) + " " + q.peek()
                + " " + b.v + " " + f.getInt(b) + " " + g.get(b) + " " + h.getInt(b) + " " + new TreeMap<>(m).firstKey());
    }
}

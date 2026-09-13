import java.lang.management.ManagementFactory;

/** HotSpot builder-heap stress only. This is not the native engine or its GC. */
public final class BuilderHeapProbe {
    private static volatile byte[][] retained;
    private static volatile byte[] scratch;

    public static void main(String[] args) {
        retained = new byte[Integer.parseInt(args[0])][];
        for (int i = 0; i < retained.length; i++) {
            retained[i] = new byte[1024];
            retained[i][0] = (byte) i;
        }
        // Promote retained analysis-like data, then require allocation progress.
        System.gc();
        for (int i = 0; i < 100_000; i++) {
            scratch = new byte[1024];
        }
        long checksum = 0;
        for (byte[] value : retained) checksum += value[0];
        System.out.println("PASS retained=" + retained.length + " checksum=" + checksum
                + " collectors=" + ManagementFactory.getGarbageCollectorMXBeans().stream()
                .map(bean -> bean.getName()).toList());
    }
}

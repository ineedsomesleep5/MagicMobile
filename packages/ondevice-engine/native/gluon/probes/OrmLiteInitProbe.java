import com.j256.ormlite.field.DatabaseField;
import com.j256.ormlite.field.DataType;
import com.j256.ormlite.field.types.DateStringType;
import com.j256.ormlite.field.types.DateStringFormatConfig;
import com.j256.ormlite.field.types.SqlDateType;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

/** Compiler-initialization reproduction only. This is NOT an engine or application backend. */
public final class OrmLiteInitProbe {
    @DatabaseField(dataType = DataType.STRING)
    public String value;

    public static void main(String[] args) throws Exception {
        if (args.length > 0) Locale.setDefault(Locale.forLanguageTag(args[0]));
        DatabaseField annotation = OrmLiteInitProbe.class.getField("value").getAnnotation(DatabaseField.class);
        if (annotation.dataType() != DataType.STRING) throw new AssertionError("Wrong annotation value");
        System.out.println(annotation.dataType().getDataPersister().getClass().getName());
        String expected = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSSSSS").format(new Date(0));
        CountDownLatch start = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        Thread[] threads = new Thread[8];
        for (int i = 0; i < threads.length; i++) {
            threads[i] = new Thread(() -> {
                try {
                    start.await();
                    for (int j = 0; j < 100; j++) {
                        Object actual = DateStringType.getSingleton().javaToSqlArg(null, new Date(0));
                        if (!expected.equals(actual)) throw new AssertionError("Build-time date defaults leaked: " + actual + " != " + expected);
                    }
                } catch (Throwable e) { failure.compareAndSet(null, e); }
            });
            threads[i].start();
        }
        start.countDown();
        for (Thread thread : threads) thread.join();
        if (failure.get() != null) throw new AssertionError(failure.get());
        Date sql = (Date) SqlDateType.getSingleton().parseDefaultString(null, "1970-01-02");
        if (sql.getTime() != new SimpleDateFormat("yyyy-MM-dd").parse("1970-01-02").getTime())
            throw new AssertionError("SQL-date defaults leaked");
        DateStringFormatConfig fresh = new DateStringFormatConfig("yyyy MMMM dd HH:mm");
        String freshExpected = new SimpleDateFormat("yyyy MMMM dd HH:mm").format(new Date(0));
        DateFormat clone = fresh.getDateFormat();
        if (!clone.format(new Date(0)).equals(freshExpected)) throw new AssertionError("Runtime config mismatch");
        clone.setTimeZone(TimeZone.getTimeZone("Pacific/Auckland"));
        if (!fresh.getDateFormat().format(new Date(0)).equals(freshExpected)) throw new AssertionError("Clone escaped");
        System.out.println("PASS runtime defaults, SQL date, 800 concurrent accesses, fresh config and clone isolation: " + expected + "; " + freshExpected);
    }
}

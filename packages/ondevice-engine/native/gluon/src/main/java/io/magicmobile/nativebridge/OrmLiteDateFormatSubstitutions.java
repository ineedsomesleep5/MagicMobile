package io.magicmobile.nativebridge;

import com.oracle.svm.core.annotate.Alias;
import com.oracle.svm.core.annotate.RecomputeFieldValue;
import com.oracle.svm.core.annotate.Substitute;
import com.oracle.svm.core.annotate.TargetClass;
import java.text.DateFormat;
import java.text.SimpleDateFormat;

/** ORMLite 5.7 AOT adaptation, not Magic rules. Never freeze the builder's date defaults. */
@TargetClass(className = "com.j256.ormlite.field.types.DateStringFormatConfig")
final class Target_OrmLite_DateStringFormatConfig {
    @Alias private String dateFormatStr;
    @Alias @RecomputeFieldValue(kind = RecomputeFieldValue.Kind.Reset, isFinal = false)
    private DateFormat dateFormat;

    @Substitute
    public synchronized DateFormat getDateFormat() {
        // Compiled-in configs initialize on first runtime use. Runtime-created configs
        // retain their original constructor-created formatter and clone behavior.
        if (dateFormat == null) dateFormat = new SimpleDateFormat(dateFormatStr);
        return (DateFormat) dateFormat.clone();
    }
}

/** Keep optional Joda reflection caches runtime-local even if a build tool inspected them. */
@TargetClass(className = "com.j256.ormlite.field.types.DateTimeType")
final class Target_OrmLite_DateTimeType {
    @Alias @RecomputeFieldValue(kind = RecomputeFieldValue.Kind.Reset)
    private static Class<?> dateTimeClass;
    @Alias @RecomputeFieldValue(kind = RecomputeFieldValue.Kind.Reset)
    private static java.lang.reflect.Method getMillisMethod;
    @Alias @RecomputeFieldValue(kind = RecomputeFieldValue.Kind.Reset)
    private static java.lang.reflect.Constructor<?> millisConstructor;
}

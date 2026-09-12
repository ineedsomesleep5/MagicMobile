/* SPDX-License-Identifier: MIT
 * MagicMobile's builder-only range planner. No game/rules code is changed.
 * The append-only veneer strategy follows Graal vm-22.2.0's code-cache design;
 * the emitter inserted into the upstream file retains that file's GPL/Classpath license.
 */
package com.oracle.svm.hosted.image;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public final class MagicMobileTrampolineLayout {
    public static final int ARM64_CALL_LIMIT = (1 << 27) - 4;
    public static final int VENEER_BYTES = 12;

    public static final class Layout {
        public final int[] starts;
        public final int[] spans;
        public final Map<Integer, Integer>[] veneers;
        public final int size;
        public final int passes;
        private Layout(int[] starts, int[] spans, Map<Integer, Integer>[] veneers,
                       int size, int passes) {
            this.starts = starts; this.spans = spans; this.veneers = veneers;
            this.size = size; this.passes = passes;
        }
    }

    private static int align(int value, int alignment) {
        return Math.addExact(value, alignment - 1) & -alignment;
    }

    public static boolean fits(long distance, int limit) {
        // Conservatively use the smaller, positive side of signed imm26 * 4.
        return distance % 4 == 0 && distance >= -((long) limit) && distance <= limit;
    }

    @SuppressWarnings("unchecked")
    public static Layout plan(int[] lengths, int[][] targets, int[][] callOffsets,
                              int alignment, int limit) {
        int n = lengths.length;
        if (n == 0 || targets.length != n || callOffsets.length != n || alignment < 4
                || (alignment & (alignment - 1)) != 0 || limit < 16
                || limit > ARM64_CALL_LIMIT || limit % 4 != 0) {
            throw new IllegalArgumentException("Invalid ARM64 layout parameters");
        }
        Map<Integer, Integer>[] veneers = (Map<Integer, Integer>[]) new Map<?, ?>[n];
        int[] starts = new int[n], spans = new int[n];
        long callCount = 0;
        for (int i = 0; i < n; i++) {
            if (lengths[i] <= 0 || lengths[i] % 4 != 0 || targets[i].length != callOffsets[i].length) {
                throw new IllegalArgumentException("Invalid compiled method or call table");
            }
            veneers[i] = new LinkedHashMap<>();
            callCount += targets[i].length;
            for (int j = 0; j < targets[i].length; j++) {
                if (targets[i][j] < 0 || targets[i][j] >= n || callOffsets[i][j] < 0
                        || callOffsets[i][j] >= lengths[i] || callOffsets[i][j] % 4 != 0) {
                    throw new IllegalArgumentException("Invalid direct call site");
                }
            }
        }
        int passes = 0, size;
        boolean changed;
        do {
            if (++passes > callCount + 1) throw new IllegalStateException("Non-converging veneer layout");
            int cursor = 0;
            for (int i = 0; i < n; i++) {
                starts[i] = cursor;
                cursor = Math.addExact(cursor, lengths[i]);
                for (Map.Entry<Integer, Integer> entry : veneers[i].entrySet()) {
                    cursor = align(cursor, 4);
                    entry.setValue(cursor);
                    cursor = Math.addExact(cursor, VENEER_BYTES);
                }
                cursor = align(cursor, alignment);
                spans[i] = cursor - starts[i];
            }
            size = cursor;
            changed = false;
            for (int i = 0; i < n; i++) {
                for (int j = 0; j < targets[i].length; j++) {
                    int target = targets[i][j];
                    long distance = (long) starts[target] - starts[i] - callOffsets[i][j];
                    if (!fits(distance, limit) && !veneers[i].containsKey(target)) {
                        veneers[i].put(target, 0);
                        changed = true;
                    }
                }
            }
        } while (changed);
        // Verify the final call sites, including callers with extremely large bodies.
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < targets[i].length; j++) {
                int target = targets[i][j];
                int address = veneers[i].getOrDefault(target, starts[target]);
                long distance = (long) address - starts[i] - callOffsets[i][j];
                if (!fits(distance, limit)) {
                    throw new IllegalArgumentException("A compiled method is too large for a nearby ARM64 veneer");
                }
            }
            veneers[i] = Collections.unmodifiableMap(veneers[i]);
        }
        return new Layout(starts, spans, veneers, size, passes);
    }
    private MagicMobileTrampolineLayout() { }
}

/*
 * MagicMobile build-time adaptation, 2026.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 * Layout only: never changes, omits, or substitutes a compiled game method.
 */
package com.oracle.svm.hosted.image;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Deterministic fixed-point layout for AArch64 direct-call veneers.
 * Kept independent of Graal so the exact planner used by the compiler is testable.
 * Each veneer is ADRP + ADD + BR (12 bytes), using Graal's reserved scratch register.
 */
public final class FarCallPlanner {
    public static final int VENEER_SIZE = 12;
    public static final int MAX_DISTANCE = (1 << 27) - 4;

    public static final class CallSite {
        public final int caller, callee, offset;
        public CallSite(int caller, int callee, int offset) {
            this.caller = caller; this.callee = callee; this.offset = offset;
        }
    }

    public static final class Layout {
        private final int[] starts, extents;
        private final List<Map<Integer, Integer>> veneers;
        public final int size, passes, veneerCount;
        private Layout(int[] starts, int[] extents, List<LinkedHashMap<Integer, Integer>> veneers,
                       int size, int passes) {
            this.starts = starts.clone(); this.extents = extents.clone();
            List<Map<Integer, Integer>> result = new ArrayList<>();
            int count = 0;
            for (Map<Integer, Integer> map : veneers) {
                result.add(Collections.unmodifiableMap(new LinkedHashMap<>(map)));
                count = Math.addExact(count, map.size());
            }
            this.veneers = Collections.unmodifiableList(result);
            this.size = size; this.passes = passes; this.veneerCount = count;
        }
        public int start(int method) { return starts[method]; }
        public int extent(int method) { return extents[method]; }
        public Map<Integer, Integer> veneers(int method) { return veneers.get(method); }
        public int destination(CallSite call) {
            return veneers.get(call.caller).getOrDefault(call.callee, starts[call.callee]);
        }
    }

    public static boolean fitsBranch(long displacement) {
        return (displacement & 3L) == 0 && displacement >= -(1L << 27) && displacement < (1L << 27);
    }

    public static Layout plan(int[] methodSizes, List<CallSite> calls, int alignment, int distance) {
        if (methodSizes.length == 0 || alignment < 4 || (alignment & (alignment - 1)) != 0
                || distance < 4 || distance > MAX_DISTANCE || (distance & 3) != 0) {
            throw new IllegalArgumentException("Invalid AArch64 layout configuration");
        }
        int[] sizes = methodSizes.clone();
        List<CallSite> stableCalls = new ArrayList<>(calls);
        List<LinkedHashMap<Integer, Integer>> veneers = new ArrayList<>();
        for (int size : sizes) {
            if (size <= 0 || (size & 3) != 0) throw new IllegalArgumentException("Unaligned/empty method");
            veneers.add(new LinkedHashMap<>());
        }
        for (CallSite c : stableCalls) {
            if (c.caller < 0 || c.caller >= sizes.length || c.callee < 0 || c.callee >= sizes.length
                    || c.offset < 0 || c.offset > sizes[c.caller] - 4 || (c.offset & 3) != 0) {
                throw new IllegalArgumentException("Invalid direct call site");
            }
        }
        int[] starts = new int[sizes.length], extents = new int[sizes.length];
        int passes = 0, total;
        boolean changed;
        do {
            if (++passes > stableCalls.size() + 1L) throw new IllegalStateException("Non-convergent veneer layout");
            long cursor = 0;
            for (int i = 0; i < sizes.length; ++i) {
                starts[i] = checked(cursor);
                cursor += sizes[i];
                for (Map.Entry<Integer, Integer> v : veneers.get(i).entrySet()) {
                    cursor = align(cursor, 4);
                    v.setValue(checked(cursor));
                    cursor += VENEER_SIZE;
                }
                cursor = align(cursor, alignment);
                extents[i] = checked(cursor - starts[i]);
            }
            total = checked(cursor);
            changed = false;
            for (CallSite c : stableCalls) {
                if (veneers.get(c.caller).containsKey(c.callee)) continue;
                long delta = (long) starts[c.callee] - starts[c.caller] - c.offset;
                if (!fitsBranch(delta) || Math.abs(delta) > distance) {
                    veneers.get(c.caller).put(c.callee, 0);
                    changed = true;
                }
            }
        } while (changed);
        Layout layout = new Layout(starts, extents, veneers, total, passes);
        for (CallSite c : stableCalls) {
            long delta = (long) layout.destination(c) - layout.start(c.caller) - c.offset;
            if (!fitsBranch(delta)) {
                throw new IllegalStateException("Method too large for a local AArch64 veneer: caller=" + c.caller);
            }
        }
        return layout;
    }

    private static long align(long value, int alignment) {
        return (value + alignment - 1) & -(long) alignment;
    }
    private static int checked(long value) {
        if (value < 0 || value > Integer.MAX_VALUE) {
            throw new IllegalStateException("Native image code area exceeds the supported 2 GiB range");
        }
        return (int) value;
    }
    private FarCallPlanner() {}
}

/*
 * Copyright (c) 2022, 2025, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

/*
 * Modified by MagicMobile (2026-10-21) from oracle/graal commit 95ce1499c8c96ab7d5a6697c5b4bf42160f3b68b
 * (Oracle GraalVM 25.4.4.1.1): releaseNodes() releases the method's variables once it is lowered. See packages/web-engine/builder-patch/build_patch.sh.
 */
package com.oracle.svm.webimage.hightiercodegen.variables;

import java.util.Map;

import org.graalvm.nativeimage.Platform;
import org.graalvm.nativeimage.Platforms;

import jdk.graal.compiler.nodes.ValueNode;
import jdk.graal.compiler.util.EconomicHashMap;

/**
 * Storing variable allocation result for a method.
 */
@Platforms(Platform.HOSTED_ONLY.class)
public final class VariableMap {
    public static final String LOCAL_PREFIX = "l";

    /** Counter for generating unique ids in the scope of a method. */
    private int count = 0;

    /**
     * The nodes stored with the resolved variables.
     */
    private final Map<ValueNode, ResolvedVar> resolvedVars;

    public VariableMap() {
        resolvedVars = new EconomicHashMap<>();
    }

    public ResolvedVar getVarByNode(ValueNode n) {
        assert n != null;
        return resolvedVars.get(n);
    }

    /**
     * Allocate a variable for the given node.
     */
    public ResolvedVar allocate(ValueNode n) {
        assert !resolvedVars.containsKey(n) : "already allocated for " + n;
        ResolvedVar var = new ResolvedVar(n);
        var.birth(LOCAL_PREFIX + count);
        resolvedVars.put(n, var);
        count++;
        return var;
    }

    /**
     * MagicMobile: lets every variable of the method drop its node once the method has been lowered to Wasm.
     */
    public void releaseNodes() {
        for (ResolvedVar var : resolvedVars.values()) {
            var.release();
        }
        resolvedVars.clear();
    }

    @Override
    public String toString() {
        return "Variable count: " + resolvedVars.size() + "\n" + resolvedVars;
    }
}

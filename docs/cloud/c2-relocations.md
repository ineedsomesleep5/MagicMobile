# libmmengine.so load-time relocations: research and proposal (C2, 2026-10-15)

Research only. Nothing here changes a build, and no workflow was dispatched. The Mac session decides
whether to apply the diff below and runs the native build. Tags: **[C]** confirmed from source or
docs (linked), **[I]** inferred, **[?]** unknown until measured.

Inputs: the REA audit (PR #157, `docs/audits/APP_AUDIT_2026-10.md`, item 9) counted 4,508,867
`R_AARCH64_RELATIVE` relocations in Android build 22's `libmmengine.so`, plus 125 JUMP_SLOT, 70 ABS64
and 5 GLOB_DAT, with BIND_NOW. Toolchain: Gluon GraalVM 22.1.0.1-Final (Java 17) through
`gluonfx-maven-plugin` 1.0.29, `scripts/android/build_native.sh`. Its Android-only POM already adds
`-H:+SpawnIsolates` and links with `-Wl,--pack-dyn-relocs=android`. App minSdk is 26.

## Answer in brief

1. **No native-image option in 22.1 removes these relocations.** The option that does,
   `-H:+RelativeCodePointers` (GR-64584), first ships, as experimental, in GraalVM 25, and is on by
   default from 25.1 (GR-74988) [C: [substratevm CHANGELOG](https://github.com/oracle/graal/blob/master/substratevm/CHANGELOG.md),
   checked by this session]. `UseCompressedReferences`, `ImageHeapReferenceCompression` and
   `UseHeapBaseRegister` are not 22.1 hosted options [C, research agent, 22.1 source].
2. **The biggest flag-level win is already taken.** With `-H:+SpawnIsolates` (heap-base mode),
   image-heap references and object headers are written as plain offsets, with no relocation. Only
   code pointers stored in the heap still relocate [C: `NativeImageHeapWriter` at `vm-22.1.0`,
   `writeReference`, `writeObjectHeader`, `addNonDataRelocation`]. Gluon's own Android target passes
   `-H:-SpawnIsolates`; our later `-H:+SpawnIsolates` wins. Without it the count would be far higher.
3. **What remains is almost certainly the vtables.** Every type's `DynamicHub.vtable` holds one 8-byte
   `MethodPointer` per slot, filler slots included [C: `UniverseBuilder` at `vm-22.1.0`]. XMage's tens
   of thousands of card, ability and effect classes with deep interface hierarchies average about
   150 slots per type, which gives about 4.5 M [I: arithmetic; M2 below tests it].
4. **Linker packing changes the table size, not the work or the dirty memory.** `--pack-dyn-relocs=android`
   (APS2, API 23+) is the right choice at minSdk 26. RELR needs API 28 with Android's private tags
   (`--pack-dyn-relocs=android+relr --use-android-relr-tags`) and API 30 with the official ones
   (`-z pack-relative-relocs`). Either way bionic still writes every one of the 4.5 M pointers and
   dirties the same pages [C: lld `ld.lld.1`; bionic `android-changes-for-ndk-developers.md`, RELR;
   AOSP Soong `cc/linker.go` uses exactly this ladder]. **Do not raise minSdk for RELR.**
5. **There is a second memory cost.** In 22.1, `LinuxImageHeapProvider` (Android extends Linux) can't
   reuse the loader-mapped heap in place under the default `UseNullRegion`. Each isolate maps the heap
   again from the file and copies the relocated partition into fresh anonymous pages. So expect about
   twice the relocatable partition as Private_Dirty while a game runs: the loader's copy plus the
   isolate's [C: code path at `vm-22.1.0`; I: magnitude]. It doesn't depend on how the table is packed.

The levers that actually reduce relocations: fewer reachable types and narrower hot interfaces
(fewer vtable slots), a GraalVM 25+ toolchain with `RelativeCodePointers` (Gluon has no such release
today), or a patch to the 22.1 SubstrateVM fork. None is a flag change. Measure first.

## Proposed change to scripts/android/build_native.sh

Measurement only. The link flags, their order and the produced library are unchanged, so it needs no
relocation revalidation and can ride along with the next R2 native build. It also corrects the RELR
comment.

```diff
@@ (inside the Android POM generator)
-# Android-packed relocations shrink millions of image-heap RELATIVE entries (API 23+; minSdk
-# 26 rules out RELR, which needs API 28). stage_native.py requires them.
+# Android-packed relocations (APS2, API 23+) shrink the table for millions of vtable RELATIVE
+# entries; stage_native.py requires them. RELR would need minSdk 28 (Android tags,
+# --use-android-relr-tags) or 30 (official tags) and still applies every relocation.
+# docs/cloud/c2-relocations.md.
 for value in ['-Wl,-z,max-page-size=16384','-Wl,-soname,libmmengine.so','-Wl,--pack-dyn-relocs=android',
               '-L'+sys.argv[3],'-lmmawtstub']:
@@ (after native-output-files.txt, before stage_native.py)
 find "$BUILD/gluonfx" -type f \( -name '*.so' -o -name '*.dylib' -o -name '*.h' \) -print | tee "$OUT/native-output-files.txt"
+# Relocation report (M1/M2 in docs/cloud/c2-relocations.md). Informational: never fails the build.
+LLVM="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
+LIB=$(grep '/libmmengine\.so$' "$OUT/native-output-files.txt" | head -1 || true)
+if [[ -n "$LIB" ]]; then
+  python3 -I - "$LLVM" "$LIB" > "$OUT/reloc-report.txt" 2>&1 <<'PY' || echo "relocation report failed (ignored)" >&2
+import collections, subprocess, sys
+llvm, lib = sys.argv[1], sys.argv[2]
+run = lambda *a: subprocess.run(a, capture_output=True, text=True, check=True).stdout
+kinds, relative = collections.Counter(), []
+for line in run(f'{llvm}/llvm-readelf', '-r', '--elf-output-style=GNU', lib).splitlines():
+    fields = line.split()
+    if len(fields) >= 3 and fields[2].startswith('R_AARCH64_'):
+        kinds[fields[2]] += 1
+        if fields[2] == 'R_AARCH64_RELATIVE': relative.append(int(fields[0], 16))
+symbols = {f[2]: int(f[0], 16) for f in (l.split() for l in run(f'{llvm}/llvm-nm', lib).splitlines()) if len(f) == 3}
+print('relocations', dict(kinds))
+begin, end = symbols.get('__svm_heap_relocatable_begin'), symbols.get('__svm_heap_relocatable_end')
+if begin is not None and end is not None:
+    inside = sum(begin <= offset < end for offset in relative)
+    print(f'relocatable partition {(end - begin) / 2**20:.1f} MiB; RELATIVE inside it {inside} of {len(relative)}')
+print(*[l.strip() for l in run(f'{llvm}/llvm-readelf', '-d', lib).splitlines() if 'REL' in l or 'BIND_NOW' in l], sep='\n')
+PY
+  cat "$OUT/reloc-report.txt"
+fi
 python3 "$REPO/scripts/android/stage_native.py" "$REPO" "$BUILD"
```

Checked here: the Python block, run against x86-64 system libraries with LLVM's `llvm-readelf` and
`llvm-nm` (relocation type swapped to `R_X86_64_*`), counts exactly the `RELACOUNT` RELATIVE entries.
The partition lines could not be exercised without a native engine library. Notes for applying it: the report runs on the unstripped library under `$BUILD/gluonfx`, where the
`__svm_heap_*` symbols still exist; `llvm-readelf -r` prints about 4.5 M lines, so it takes a few
seconds and some memory but no more than the build already uses. The `|| echo` keeps a multi-hour
build from failing on a reporting problem. The workflow should upload `reloc-report.txt` with the
other native size evidence.

**Expected effect:** none on the library, its size, load time or memory. It records, on every native
build, the numbers this research could only infer: the relocation mix, the packed table size
(`ANDROID_RELASZ`), the partition size P and the share of RELATIVE entries inside it.

**Not proposed:** an `android+relr` switch. It can't ship at minSdk 26 (an older loader ignores the
unknown tags, skips the relocations and the first engine call crashes) and it would not reduce the
4.5 M writes. If Caleb ever raises minSdk to 28 for other reasons, it saves roughly 5–10 MB of table
at most [I].

## How to measure (before and after any future change)

**M1, static counts** (NDK r28, on the built or downloaded library):

```
RE=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf
$RE -r --elf-output-style=GNU libmmengine.so | awk '{print $3}' | sort | uniq -c   # relocation mix
$RE -d libmmengine.so | grep -E 'ANDROID_REL|RELR|BIND_NOW'                         # packed table bytes
$RE -S -W libmmengine.so | grep -E 'svm_heap|rela|relr|\.text'                       # section sizes
```

`DT_RELACOUNT` is absent in an APS2 build; that's expected. `stage_native.py` already records
`packedAndroidRelaBytes`.

**M2, where they land:** the report above. Expect about 100% of RELATIVE entries inside
`__svm_heap_relocatable_begin..end` and a partition of 35–60 MiB (at least 4.5 M × 8 B = 34.4 MiB).
If many land outside, heap-base mode is not in effect or the vtable explanation is wrong.

**M3, memory on a phone** (release install, after launch, then again with a game open):

```
PID=$(adb shell pidof com.calebfeliciano.magicmobile.android)
adb shell cat /proc/$PID/smaps | awk '/^[0-9a-f]+-[0-9a-f]+ /{n=$6} /^Private_Dirty:/{d[n]+=$2} END{for(k in d) if(d[k]>2048) print d[k]" kB", k}' | sort -rn | head
adb shell dumpsys meminfo $PID | head -40
```

Expect about P kB dirty in the `libmmengine.so` mapping from launch, plus about P kB of anonymous dirty
memory once a game's isolate exists. An anonymous mapping near 167 MB would mean the full-heap
copying fallback fired, which is worth knowing on its own.

**M4, time:** `adb shell am start -W -n <package>/.MainActivity` (TotalTime, median of 10 cold starts
after `am force-stop`), and a Perfetto trace with the `bionic` atrace category: the
`dlopen: …/libmagicmobile_jni.so - loading and linking` slice includes `libmmengine.so`'s relocation
because it is a DT_NEEDED of the JNI library. Time `graal_create_isolate` separately for the
per-game copy.

## Sources

- GraalVM 22.1 SubstrateVM: https://github.com/oracle/graal/tree/vm-22.1.0/substratevm/src
  (`NativeImageHeapWriter`, `NativeImageHeap`, `UniverseBuilder`, `HostedConfiguration`,
  `LinuxImageHeapProvider`, `HeapImpl`, `SubstrateOptions`, `NativeImage`). The Gluon fork tag
  `gluon-22.1.0.1-Final` differs from it in two unrelated files under `substratevm/src`.
- Gluon's Android flags (substrate 0.0.69, used by gluonfx 1.0.29):
  https://github.com/gluonhq/substrate/blob/0.0.69/src/main/java/com/gluonhq/substrate/target/AndroidTargetConfiguration.java
- `RelativeCodePointers`: https://github.com/oracle/graal/blob/master/substratevm/CHANGELOG.md (GR-64584 in 25, GR-74988 in 25.1)
- lld options: https://github.com/llvm/llvm-project/blob/main/lld/docs/ld.lld.1
- bionic RELR and packed relocations: https://android.googlesource.com/platform/bionic/+/refs/heads/main/android-changes-for-ndk-developers.md
- AOSP packing by API level: https://android.googlesource.com/platform/build/soong/+/refs/heads/main/cc/linker.go

The GraalVM-source claims came from a research subagent that read the 22.1 tags; this session
checked the GraalVM 25 changelog entries and the repo-side facts (`stage_native.py`,
`scripts/android/tests/test_native_size.py`, the current link flags) directly.

# Cloud push test

Date: 2026-10-15 05:31:33 UTC

## Gradle

`gradle -v | head -3` (the JAVA_TOOL_OPTIONS proxy line is left out):

```

------------------------------------------------------------
Gradle 8.11.1
```

`which gradle`: `/opt/gradle/bin/gradle`

/opt/gradle points at /opt/gradle-8.11.1: yes (`/opt/gradle -> /opt/gradle-8.11.1`)

## Java

`java -version 2>&1 | head -1` (first line after the JAVA_TOOL_OPTIONS notice): `openjdk version "21.0.12.1" 2026-08-18`

## Machine

`nproc`: 4

`free -g | head -2`:

```
               total        used        free      shared  buff/cache   available
Mem:              15           0          13           0           1          15
```

Cloud push OK

$ErrorActionPreference = 'Stop'
$Root = $env:MAGICMOBILE_LAUNCHER_DIR
if (-not $Root) { $Root = $PSScriptRoot }
function Read-Properties([string]$Path, [string[]]$Allowed) {
    $Values = @{}
    foreach ($Line in [IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($Line) -or $Line.StartsWith('#')) { continue }
        $Pair = $Line.Split(@('='), 2)
        if ($Pair.Length -ne 2 -or $Allowed -notcontains $Pair[0] -or $Values.ContainsKey($Pair[0])) { throw "Invalid configuration line in $Path" }
        $Values[$Pair[0]] = $Pair[1].Trim()
    }
    return $Values
}
$Config = Read-Properties (Join-Path $Root 'server.properties') @('SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY','UPSTREAM_COMMIT','CATALOGUE_HASH','ADAPTER_VERSION','DATABASE_MIGRATION_READY','BIND_ADDRESS','PORT','JAVA_HEAP_MAX')
if ($Config.SUPABASE_URL -cnotmatch '^https://[A-Za-z0-9.-]+$' -or $Config.SUPABASE_PUBLISHABLE_KEY -cnotmatch '^sb_publishable_[A-Za-z0-9_-]+$') { throw 'Use an HTTPS Supabase URL and public publishable key only.' }
if ($Config.UPSTREAM_COMMIT -cnotmatch '^[a-f0-9]{40}$' -or $Config.CATALOGUE_HASH -cnotmatch '^[a-f0-9]{64}$' -or $Config.ADAPTER_VERSION -cnotmatch '^[A-Za-z0-9._/-]+$') { throw 'Invalid build identity.' }
if ($Config.PORT -notmatch '^\d+$' -or [int]$Config.PORT -lt 1 -or [int]$Config.PORT -gt 65535 -or $Config.JAVA_HEAP_MAX -notmatch '^[1-9][0-9]*[mMgG]$') { throw 'Invalid port or heap size.' }
if (@('127.0.0.1','0.0.0.0','::1') -notcontains $Config.BIND_ADDRESS) { throw 'Unsupported bind address.' }
if ($Config.DATABASE_MIGRATION_READY -cne 'true') { throw 'Setup pending: install the reviewed Supabase matchmaking migration before setting DATABASE_MIGRATION_READY=true in server.properties.' }
$Java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' } else { (Get-Command java.exe -ErrorAction Stop).Source }
$Probe = New-Object Diagnostics.ProcessStartInfo
$Probe.FileName = $Java; $Probe.Arguments = '-version'; $Probe.UseShellExecute = $false
$Probe.RedirectStandardError = $true; $Probe.RedirectStandardOutput = $true
$Process = [Diagnostics.Process]::Start($Probe)
$Version = $Process.StandardError.ReadToEnd() + $Process.StandardOutput.ReadToEnd(); $Process.WaitForExit()
if ($Process.ExitCode -ne 0 -or $Version -notmatch 'version "17\.') { throw 'Install/select Java 17 (Temurin): https://adoptium.net/temurin/releases/?version=17 . No installer or system setting was changed.' }
$RuntimeInfo = Read-Properties (Join-Path $Root 'runtime.properties') @('URL','SHA256','DIRECTORY')
if ($RuntimeInfo.URL -cnotmatch '^https://github\.com/ineedsomesleep5/MagicMobile/releases/download/.+$' -or $RuntimeInfo.SHA256 -cnotmatch '^[a-f0-9]{64}$' -or $RuntimeInfo.DIRECTORY -cnotmatch '^runtime-[A-Za-z0-9._-]+$') { throw 'Invalid pinned runtime manifest.' }
$Cache = Join-Path $Root '.runtime'; $Runtime = Join-Path $Cache $RuntimeInfo.DIRECTORY
$Marker = Join-Path $Runtime '.verified-archive-sha256'
if (-not (Test-Path -LiteralPath $Marker)) {
    $null = Get-Command tar.exe -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $Cache -Force
    $Archive = Join-Path $Cache ($RuntimeInfo.DIRECTORY + '.tar.gz')
    if (-not (Test-Path -LiteralPath $Archive)) {
        Write-Host 'Downloading verified MagicMobile runtime (about 136 MB)...'
        Invoke-WebRequest -UseBasicParsing -Uri $RuntimeInfo.URL -OutFile ($Archive + '.part')
        Move-Item -LiteralPath ($Archive + '.part') -Destination $Archive
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash.ToLowerInvariant() -cne $RuntimeInfo.SHA256) { throw 'Runtime checksum failed. Nothing was executed; remove only the downloaded archive and retry.' }
    $Staging = Join-Path $Cache ('unpack-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $Staging
    & tar.exe -xzf $Archive -C $Staging
    if ($LASTEXITCODE -ne 0) { throw 'Runtime extraction failed.' }
    [IO.File]::WriteAllText((Join-Path $Staging '.verified-archive-sha256'), $RuntimeInfo.SHA256)
    if (Test-Path -LiteralPath $Runtime) { throw 'An incomplete runtime directory exists; preserve or move it before retrying.' }
    Move-Item -LiteralPath $Staging -Destination $Runtime
}
if ([IO.File]::ReadAllText($Marker).Trim() -cne $RuntimeInfo.SHA256) { throw 'Cached runtime does not match the pinned release.' }
foreach ($Key in @('SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY','BIND_ADDRESS','PORT')) { [Environment]::SetEnvironmentVariable($Key,$Config[$Key],'Process') }
$env:MAX_MATCHES = '1'
$env:MAGICMOBILE_BUILD_IDENTITY = @{ protocolVersion=1; upstreamCommit=$Config.UPSTREAM_COMMIT; catalogueHash=$Config.CATALOGUE_HASH; adapterVersion=$Config.ADAPTER_VERSION } | ConvertTo-Json -Compress
# Artifact classpath is relative POSIX form. Windows Java requires semicolons.
$ClasspathEntries = [IO.File]::ReadAllText((Join-Path $Runtime 'runtime-classpath.txt')).Trim().Split(':')
foreach ($Entry in $ClasspathEntries) { if ($Entry -notmatch '^cp/[A-Za-z0-9._/-]+$' -or $Entry.Contains('..')) { throw 'Unsafe runtime classpath.' } }
$Classpath = [string]::Join(';',$ClasspathEntries)
Write-Host "Keep this terminal open. Local health check: http://127.0.0.1:$($Config.PORT)/health"
Write-Host 'Stop with Ctrl+C. Public phone access additionally requires HTTPS/DNS and a configured app endpoint.'
Push-Location $Runtime
try {
    & $Java '-Xms64m' "-Xmx$($Config.JAVA_HEAP_MAX)" '-XX:ActiveProcessorCount=1' '-Djava.awt.headless=true' '-Dsun.net.httpserver.maxReqTime=15' '-Dsun.net.httpserver.maxRspTime=20' '-Dsun.net.httpserver.maxConnections=64' '-cp' $Classpath 'io.magicmobile.server.Main'
    if ($LASTEXITCODE -ne 0) { throw "Server exited with code $LASTEXITCODE" }
} finally { Pop-Location }

# Rebuild lists/telegram-ip-candidates.txt from official Telegram IPv4 CIDRs.
# Source: https://core.telegram.org/resources/cidr.txt
# Только seed + выборка из CIDR (без слияния со старым файлом — [5] полностью обновляет пул).
param(
    [string]$CidrUrl = 'https://core.telegram.org/resources/cidr.txt'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Системный прокси (только этот процесс PS) — для Invoke-WebRequest [5] и не трогает VPN/другие программы.
try {
    $px = [System.Net.WebRequest]::DefaultWebProxy
    if ($null -ne $px) {
        $px.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    }
} catch {}

# Принудительно держим TrueType в этой же консоли — Write-Host ниже иначе печатается растром.
$ttfHelper = Join-Path $PSScriptRoot 'ensure-console-ttf.ps1'
if (Test-Path -LiteralPath $ttfHelper) { . $ttfHelper }

$Root = Split-Path -Parent $PSScriptRoot
$OutFile = Join-Path $Root 'lists\telegram-ip-candidates.txt'
$FailedFile = Join-Path $Root 'lists\telegram-ip-failed.txt'
$ListDir = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $ListDir)) {
    New-Item -ItemType Directory -Path $ListDir -Force | Out-Null
}

function ConvertTo-UInt32IPv4([string]$s) {
    $a = $s.Split('.')
    return [uint32]([uint32]$a[0] * 16777216 + [uint32]$a[1] * 65536 + [uint32]$a[2] * 256 + [uint32]$a[3])
}

function ConvertTo-StringIPv4([uint32]$u) {
    $a0 = [int](($u -shr 24) -band 0xFF)
    $a1 = [int](($u -shr 16) -band 0xFF)
    $a2 = [int](($u -shr 8) -band 0xFF)
    $a3 = [int]($u -band 0xFF)
    return '{0}.{1}.{2}.{3}' -f $a0, $a1, $a2, $a3
}

function Get-CidrSampleIPv4s {
    param([string]$CidrStr)
    if ($CidrStr -notmatch '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$') { return @() }
    $netStr = $Matches[1]
    $pref = [int]$Matches[2]
    if ($pref -lt 8 -or $pref -gt 32) { return @() }
    $ipUint = ConvertTo-UInt32IPv4 $netStr
    $hostBits = 32 - $pref
    if ($hostBits -le 0) {
        return @(ConvertTo-StringIPv4 $ipUint)
    }
    [uint64]$size = 1
    for ($i = 0; $i -lt $hostBits; $i++) { $size = $size * 2 }
    [uint32]$mask = 0
    for ($i = 0; $i -lt $pref; $i++) {
        $mask = [uint32](([uint64]$mask -shl 1) -bor 1)
    }
    for ($i = 0; $i -lt $hostBits; $i++) {
        $mask = [uint32]([uint64]$mask -shl 1)
    }
    $net = [uint32]($ipUint -band $mask)
    $last = [uint32](([uint64]$net + $size - 1) -band 0xFFFFFFFF)

    $offsets = New-Object 'System.Collections.Generic.HashSet[uint64]'
    foreach ($x in @(1, 2, 5, 10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 200, 250, 300, 400, 500, 600, 700, 800, 900, 1000, 1500, 2000, 2500, 3000)) {
        $xu = [uint64]$x
        if ($xu -lt $size) { [void]$offsets.Add($xu) }
    }
    if ($size -gt 2) { [void]$offsets.Add($size - 2) }
    $step = [uint64][math]::Max(1, [math]::Floor([double]$size / 40))
    for ([uint64]$o = 0; $o -lt $size; $o += $step) {
        if ($o -gt 0 -and $o -lt $size - 1) { [void]$offsets.Add($o) }
    }

    $out = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($off in $offsets) {
        if ($off -ge $size) { continue }
        $u = [uint32](([uint64]$net + $off) -band 0xFFFFFFFF)
        if ($u -ge $net -and $u -le $last) {
            [void]$out.Add((ConvertTo-StringIPv4 $u))
        }
    }
    return @($out)
}

Write-Host "  [update] download: $CidrUrl" -ForegroundColor Cyan
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("tg-cidr-{0}.txt" -f [Guid]::NewGuid().ToString('n'))
try {
    Invoke-WebRequest -Uri $CidrUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 20
} catch {
    Write-Host ("  [update] ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    if (Test-Path -LiteralPath $ttfHelper) { . $ttfHelper }
    exit 1
}

$lines = Get-Content -LiteralPath $tmp -ErrorAction Stop
Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

$cidrRows = @(
    $lines | ForEach-Object {
        $t = $_.Trim()
        if ($t -match '^\s*#' -or $t.Length -lt 7) { return }
        if ($t -match '::') { return }
        if ($t -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$') { $t }
    }
) | Select-Object -Unique

if (-not $cidrRows -or $cidrRows.Count -eq 0) {
    Write-Host '  [update] ERROR: no IPv4 CIDR lines in cidr.txt' -ForegroundColor Red
    if (Test-Path -LiteralPath $ttfHelper) { . $ttfHelper }
    exit 1
}

$seed = @(
    '149.154.175.50', '149.154.175.100', '149.154.175.209', '149.154.170.96',
    '149.154.167.40', '149.154.167.50', '149.154.167.51', '149.154.167.91',
    '149.154.167.99', '149.154.167.220', '149.154.168.98', '149.154.172.98',
    '91.108.56.100', '91.108.56.130', '91.108.56.181', '185.76.151.43'
)

$all = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $seed) { [void]$all.Add($s) }

foreach ($row in $cidrRows) {
    foreach ($ip in (Get-CidrSampleIPv4s $row)) {
        [void]$all.Add($ip)
    }
}

function Sort-IPv4Strings {
    param([string[]]$Ips)
    return @(
        $Ips | Sort-Object {
            $p = $_.Split('.')
            [uint32]([uint32]$p[0] * 16777216 + [uint32]$p[1] * 65536 + [uint32]$p[2] * 256 + [uint32]$p[3])
        }
    )
}

$seedOrdered = @($seed | Where-Object { $all.Contains($_) })
$rest = @($all | Where-Object { $seedOrdered -notcontains $_ })
$restSorted = Sort-IPv4Strings $rest
$ordered = @($seedOrdered) + @($restSorted)

$built = (Get-Date).ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$header = @(
    '# Telegram Web Fix — IPv4 candidates for menu [4]',
    '# Source: https://core.telegram.org/resources/cidr.txt',
    '# Refresh: menu [5] or: powershell -File utils\update-ip-candidates.ps1',
    ('# twf-build {0} | CIDR blocks: {1} | unique IPv4: {2} (seed + CIDR only, no merge with old file)' -f $built, $cidrRows.Count, $ordered.Count),
    ''
)

$utf8 = [System.Text.UTF8Encoding]::new($false)
$body = ($ordered -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($OutFile, (($header -join "`r`n") + $body), $utf8)

# Новый список — сбрасываем кэш неудачных TCP, чтобы [4] не пропускал устаревшие «плохие» IP.
if (Test-Path -LiteralPath $FailedFile) {
    Remove-Item -LiteralPath $FailedFile -Force -ErrorAction SilentlyContinue
    Write-Host '  [update] сброшен кэш lists\telegram-ip-failed.txt (старые неудачи не мешают новому списку)' -ForegroundColor DarkGray
}

Write-Host ("  [update] OK -> {0}" -f $OutFile) -ForegroundColor Green
Write-Host ("  [update] CIDR lines: {0} | IPs written: {1}" -f $cidrRows.Count, $ordered.Count) -ForegroundColor Gray

if (Test-Path -LiteralPath $ttfHelper) { . $ttfHelper }

exit 0

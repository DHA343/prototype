$ErrorActionPreference = 'Stop'
$experimentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$desktopRoot = [Environment]::GetFolderPath('Desktop')
$localTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Tokyo Standard Time')
$bundleRoot = Join-Path $desktopRoot ('flipper-load-2026-11-22-' + $localTime.ToString('HHmmss'))
if (-not (Test-Path -LiteralPath $desktopRoot) -or (Test-Path -LiteralPath $bundleRoot)) {
    throw 'Desktop is unavailable or the export destination already exists.'
}
$manifestPath = Join-Path $experimentRoot 'evidence/load_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $bundleRoot | Out-Null
$bytes = 0
foreach ($file in $manifest.files) {
    $source = [IO.Path]::GetFullPath((Join-Path $experimentRoot $file.path))
    $target = [IO.Path]::GetFullPath((Join-Path $bundleRoot $file.path))
    if (-not $source.StartsWith($experimentRoot + [IO.Path]::DirectorySeparatorChar) -or
        -not $target.StartsWith($bundleRoot + [IO.Path]::DirectorySeparatorChar)) {
        throw 'A manifest path escaped the export directory.'
    }
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $target
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Copy verification failed: $($file.path)"
    }
    $bytes += $file.bytes
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $bundleRoot 'evidence/load_manifest.json')
$readme = @'
# B/B＋4・ゲーム全体の性能監査

[詳細報告書](evidence/load_audit.md) を開いてください。
evidence/ に全測定データ、tests/ と直下に検証スクリプト・シーンを保存しています。
load_manifest.json のSHA-256で元ファイルと照合済みです。

このフォルダ単体はGodotプロジェクトではありません。
再実行は元の C:/GameDev/Projects/prototype/ で、報告書のコマンドを使用してください。
本番Bの採用変更や最適化は行っていません。
'@
Set-Content -LiteralPath (Join-Path $bundleRoot 'README.md') -Value $readme -Encoding utf8
[pscustomobject]@{
    destination = $bundleRoot
    report = Join-Path $bundleRoot 'evidence/load_audit.md'
    source_files = $manifest.files.Count
    total_mb = [math]::Round($bytes / 1MB, 2)
    sha256_verified = $true
} | ConvertTo-Json

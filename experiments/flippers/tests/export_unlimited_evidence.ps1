$ErrorActionPreference = 'Stop'
$experimentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$desktopRoot = [Environment]::GetFolderPath('Desktop')
$localTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Tokyo Standard Time')
$bundleRoot = Join-Path $desktopRoot ('flipper-unlimited-2026-11-23-' + $localTime.ToString('HHmmss'))
if (-not (Test-Path -LiteralPath $desktopRoot) -or (Test-Path -LiteralPath $bundleRoot)) {
    throw 'Desktop is unavailable or export destination already exists.'
}
$manifestPath = Join-Path $experimentRoot 'evidence/unlimited_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $bundleRoot | Out-Null
$bytes = 0
foreach ($file in $manifest.files) {
    $source = [IO.Path]::GetFullPath((Join-Path $experimentRoot $file.path))
    $target = [IO.Path]::GetFullPath((Join-Path $bundleRoot $file.path))
    if (-not $source.StartsWith($experimentRoot + [IO.Path]::DirectorySeparatorChar) -or
        -not $target.StartsWith($bundleRoot + [IO.Path]::DirectorySeparatorChar)) {
        throw 'Manifest path escaped export directory.'
    }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Source changed after manifest creation: $($file.path)"
    }
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $target
    $bytes += $file.bytes
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $bundleRoot 'evidence/unlimited_manifest.json')
$guide = @'
# ③解除時の距離上限なし分離

[詳細報告書](evidence/unlimited_audit.md) を開いてください。
evidence/ に生データと集計、tests/ と直下に実験ソースがあります。
evidence/unlimited_manifest.json のSHA-256でコピーを照合済みです。

このフォルダー単体はGodotプロジェクトではありません。
再実行は C:/GameDev/Projects/prototype/ で、報告書に記載したコマンドを使用してください。
本番は変更していません。距離制限なしの安全分離は採用保留です。

unlimited_preview.tscn：1＝現行解除、2＝12 px、3＝制限なし。4/5/6＝既知3配置、7＝最大補正例、P/N＝停止と1更新。
安全な候補がなければ未解消で試行停止。Rで再試行できます。
'@
Set-Content -LiteralPath (Join-Path $bundleRoot 'START_HERE.md') -Value $guide -Encoding utf8
foreach ($file in $manifest.files) {
    $target = Join-Path $bundleRoot $file.path
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Final hash mismatch: $($file.path)"
    }
}
[pscustomobject]@{
    destination = $bundleRoot
    report = Join-Path $bundleRoot 'evidence/unlimited_audit.md'
    source_files = $manifest.files.Count
    total_mb = [math]::Round($bytes / 1MB, 2)
    sha256_verified = $true
} | ConvertTo-Json


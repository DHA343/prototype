$ErrorActionPreference = 'Stop'
$experimentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$desktopRoot = [Environment]::GetFolderPath('Desktop')
$localTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Tokyo Standard Time')
$bundleRoot = Join-Path $desktopRoot ('flipper-separation-2026-11-22-' + $localTime.ToString('HHmmss'))
if (-not (Test-Path -LiteralPath $desktopRoot) -or (Test-Path -LiteralPath $bundleRoot)) {
    throw 'Desktop is unavailable or the export destination already exists.'
}
$manifestPath = Join-Path $experimentRoot 'evidence/separation_manifest.json'
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
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Source changed after the manifest was generated: $($file.path)"
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
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $bundleRoot 'evidence/separation_manifest.json')
$readme = @'
# 3条件＋新接触の法線分離：4構成比較

[詳細報告書](evidence/separation_audit.md) を開いてください。
evidence/ に測定データ、tests/ と直下に実験ソースと再現入力を保存しています。
evidence/separation_manifest.json のSHA-256で元ファイル・コピーを照合済みです。

このフォルダ単体はGodotプロジェクトではありません。
再実行は元の C:/GameDev/Projects/prototype/ で、報告書のコマンドを使用してください。
本番は変更していません。separation_preview.tscn は組み合わせ案が初期値です。
1＝現行、2＝3条件のみ、3＝新接触の法線分離のみ、4＝両方、R＝リセット。
'@
Set-Content -LiteralPath (Join-Path $bundleRoot 'START_HERE.md') -Value $readme -Encoding utf8
[pscustomobject]@{
    destination = $bundleRoot
    report = Join-Path $bundleRoot 'evidence/separation_audit.md'
    source_files = $manifest.files.Count
    total_mb = [math]::Round($bytes / 1MB, 2)
    sha256_verified = $true
} | ConvertTo-Json

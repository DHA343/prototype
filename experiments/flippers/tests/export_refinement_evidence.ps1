$ErrorActionPreference = 'Stop'
$experimentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$desktopRoot = [Environment]::GetFolderPath('Desktop')
if (-not [IO.Directory]::Exists($desktopRoot)) {
    throw 'Desktop directory is unavailable.'
}
$bundleName = 'flipper-refinement-' + (Get-Date -Format 'yyyy-MM-dd-HHmmss')
$bundleRoot = Join-Path $desktopRoot $bundleName
if (Test-Path -LiteralPath $bundleRoot) {
    throw 'The export destination already exists.'
}
$manifestPath = Join-Path $experimentRoot 'evidence/refinement_manifest.json'
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
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $file.sha256) {
        throw "Copy verification failed: $($file.path)"
    }
    $bytes += $file.bytes
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $bundleRoot 'evidence/refinement_manifest.json')
$readme = @'
# フリッパー接触時刻の絞り込み比較

[詳細報告書](evidence/refinement_audit.md) を開いてください。
[データと再実行について](evidence/refinement_bundle_readme.md) に構成を記載しています。

evidence/ のJSONが全条件の測定結果です。tests/ と直下のスクリプトは実験ソースの写しです。
元のGodotプロジェクトは C:/GameDev/Projects/prototype/ です。このフォルダ単体はGodotプロジェクトではありません。
'@
Set-Content -LiteralPath (Join-Path $bundleRoot 'README.md') -Value $readme -Encoding utf8
[pscustomobject]@{
    destination = $bundleRoot
    report = Join-Path $bundleRoot 'evidence/refinement_audit.md'
    source_files = $manifest.files.Count
    total_mb = [math]::Round($bytes / 1MB, 2)
    sha256_verified = $true
} | ConvertTo-Json

[CmdletBinding()]
param(
    [string]$AssetsBinPath = 'C:\Program Files (x86)\Steam\steamapps\common\sbox\download\assets\_bin',
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'extracted_packages'),
    [string]$Filter = '*',
    [int]$Index = -1,
    [string]$PackagePath,
    [switch]$IncludeReferencedAssets,
    [switch]$DecompileCompiledAssets,
    [string[]]$AssetSearchRoots,
    [string]$VrfCliPath = (Join-Path $PSScriptRoot 'Source2Viewer-CLI.exe'),
    [switch]$KeepDecompressedBlob,
    [switch]$CopyXml,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PackageDisplayName {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $match = [regex]::Match($baseName, '^package_(?<id>.+?)\.[0-9a-fA-F]{8,}$')
    if ($match.Success) {
        return $match.Groups['id'].Value
    }

    $match = [regex]::Match($baseName, '^package_(?<id>.+)$')
    if ($match.Success) {
        return $match.Groups['id'].Value
    }

    return $baseName
}

function Select-PackageFile {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$NameFilter,
        [int]$SelectedIndex
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "Directory not found: $Directory"
    }

    $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.cll' -File |
        Where-Object {
            $_.Name -like $NameFilter -or (Get-PackageDisplayName $_) -like $NameFilter
        } |
        Sort-Object LastWriteTime -Descending)

    if (-not $files -or $files.Count -eq 0) {
        throw "No .cll file found in '$Directory' with filter '$NameFilter'."
    }

    if ($SelectedIndex -ge 0) {
        if ($SelectedIndex -ge $files.Count) {
            throw "Index invalide $SelectedIndex. Index max: $($files.Count - 1)."
        }
        return $files[$SelectedIndex]
    }

    Write-Host ''
    Write-Host 'Available .cll packages:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $files.Count; $i++) {
        $file = $files[$i]
        $display = Get-PackageDisplayName $file
        $sizeMb = [math]::Round($file.Length / 1MB, 2)
        Write-Host ("[{0}] {1}  ({2} MB)" -f $i, $display, $sizeMb)
        Write-Host ("     {0}" -f $file.FullName) -ForegroundColor DarkGray
    }

    do {
        $choice = Read-Host 'Enter the package index to extract'
    } while (-not [int]::TryParse($choice, [ref]$SelectedIndex) -or $SelectedIndex -lt 0 -or $SelectedIndex -ge $files.Count)

    return $files[$SelectedIndex]
}

function Read-AssetExtractionOptions {
    param(
        [ref]$IncludeReferencedAssets,
        [ref]$DecompileCompiledAssets
    )

    Write-Host ''
    $extractAssets = Read-Host 'Do you want to extract referenced assets (models, materials, etc.)? (Y/n)'
    if ($extractAssets -notmatch '^n') {
        $IncludeReferencedAssets.Value = $true
        
        $decompile = Read-Host 'Do you want to decompile compiled assets (*_c) with Source2Viewer? (Y/n)'
        if ($decompile -notmatch '^n') {
            $DecompileCompiledAssets.Value = $true
        }
    }
}

function Expand-GzipFile {
    param(
        [Parameter(Mandatory)][string]$InputFile,
        [Parameter(Mandatory)][string]$OutputFile
    )

    $inStream = $null
    $gzipStream = $null
    $outStream = $null

    try {
        $inStream = [System.IO.File]::OpenRead($InputFile)
        $gzipStream = [System.IO.Compression.GZipStream]::new($inStream, [System.IO.Compression.CompressionMode]::Decompress)
        $outStream = [System.IO.File]::Create($OutputFile)
        $gzipStream.CopyTo($outStream)
    }
    finally {
        if ($outStream) { $outStream.Dispose() }
        if ($gzipStream) { $gzipStream.Dispose() }
        if ($inStream) { $inStream.Dispose() }
    }
}

function Remove-ExtractionIntermediateFiles {
    param(
        [Parameter(Mandatory)][string[]]$Paths
    )

    foreach ($path in $Paths | Select-Object -Unique) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }

        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Unable to delete intermediate file '$path': $($_.Exception.Message)"
        }
    }
}

function Convert-EscapedJsonString {
    param([Parameter(Mandatory)][string]$EscapedText)

    $json = '{"value":"' + $EscapedText + '"}'
    $doc = [System.Text.Json.JsonDocument]::Parse($json)
    try {
        return $doc.RootElement.GetProperty('value').GetString()
    }
    finally {
        $doc.Dispose()
    }
}

function Get-BlobText {
    param([Parameter(Mandatory)][string]$BlobPath)

    $bytes = [System.IO.File]::ReadAllBytes($BlobPath)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Export-GmcaTextEntries {
    param(
        [Parameter(Mandatory)][string]$BlobText,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )

    $regex = [System.Text.RegularExpressions.Regex]::new('"Text":"(.*?)","LocalPath":"(.*?)"\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $textEntryMatches = $regex.Matches($BlobText)

    $written = 0
    foreach ($match in $textEntryMatches) {
        $relativePath = $match.Groups[2].Value
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
        if ($relativePath.StartsWith('/.obj/')) { continue }

        try {
            $content = Convert-EscapedJsonString -EscapedText $match.Groups[1].Value
            $targetPath = Join-Path $DestinationDirectory $relativePath
            $targetDir = Split-Path -Parent $targetPath
            if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            [System.IO.File]::WriteAllText($targetPath, $content, [System.Text.UTF8Encoding]::new($false))
            $written++
        }
        catch {
            Write-Warning "Skipped entry: $relativePath :: $($_.Exception.Message)"
        }
    }

    return $written
}

function Get-ReferencedAssetPaths {
    param([Parameter(Mandatory)][string]$BlobText)

    $extensions = @(
        'scene','vscene','vmap','prefab','vmdl','vmat','vtex','vpcf','vsnd','sound',
        'png','jpg','jpeg','tga','gif','webp','svg','wav','mp3','ogg','txt','json'
    )

    $extPattern = ($extensions | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $roots = @('Assets','data','images','materials','models','prefabs','sounds','textures')
    $rootPattern = ($roots | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $regex = [System.Text.RegularExpressions.Regex]::new('(?:u0022)?(?<path>(?:' + $rootPattern + ')[/\\][A-Za-z0-9_./\\-]+\.(?:' + $extPattern + '))', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = [System.Collections.Generic.List[string]]::new()

    foreach ($match in $regex.Matches($BlobText)) {
        $raw = $match.Groups['path'].Value
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $normalized = $raw.Trim('"', '''') -replace '\\', '/'
        if ($normalized.StartsWith('u0022', [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(5)
        }
        $normalized = $normalized.TrimStart('./')

        if ($normalized.StartsWith('/')) { continue }
        if ($normalized.StartsWith('http://', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($normalized.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($normalized.StartsWith('www.', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($normalized -notmatch '/') { continue }
        if ($normalized -match '^C:/') { continue }
        if ($normalized -match '^/mnt/') { continue }

        if ($seen.Add($normalized)) {
            $results.Add($normalized)
        }
    }

    return $results | Sort-Object
}

function Resolve-AssetSearchRoots {
    param(
        [Parameter(Mandatory)][string]$AssetsBinDirectory,
        [string[]]$CustomRoots
    )

    if ($CustomRoots -and $CustomRoots.Count -gt 0) {
        return $CustomRoots
    }

    $assetsRoot = Split-Path -Parent $AssetsBinDirectory
    $downloadRoot = Split-Path -Parent $assetsRoot
    $sboxRoot = Split-Path -Parent $downloadRoot

    return @($assetsRoot, $downloadRoot, $sboxRoot) | Select-Object -Unique
}

function Get-AssetPathVariants {
    param([Parameter(Mandatory)][string]$RelativeAssetPath)

    $variants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalized = $RelativeAssetPath -replace '\\', '/'
    $variants.Add($normalized) | Out-Null

    if ($normalized.StartsWith('Assets/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $variants.Add($normalized.Substring(7)) | Out-Null
    }

    return $variants
}

function Find-AssetCandidatesByPattern {
    param(
        [Parameter(Mandatory)][string]$Variant,
        [Parameter(Mandatory)][string[]]$SearchRoots
    )

    $variantWindows = $Variant -replace '/', '\\'
    $relativeDir = Split-Path -Parent $variantWindows
    $leaf = Split-Path -Leaf $variantWindows
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    $extension = [System.IO.Path]::GetExtension($leaf)

    $searchDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        if ($relativeDir) {
            $directDir = Join-Path $root $relativeDir
            if (Test-Path -LiteralPath $directDir -PathType Container) {
                $searchDirs.Add($directDir)
            }
        }

        $fallbackDirName = Split-Path -Leaf $relativeDir
        if ($fallbackDirName) {
            $fallbackDirs = Get-ChildItem -LiteralPath $root -Recurse -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq $fallbackDirName }
            foreach ($dir in $fallbackDirs) {
                $searchDirs.Add($dir.FullName)
            }
        }
    }

    $patterns = @(
        "$leaf",
        "$baseName.*$extension",
        "$baseName.*$extension`_c",
        "$baseName$extension`_c"
    ) | Select-Object -Unique

    $matchedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $searchDirs | Select-Object -Unique) {
        foreach ($pattern in $patterns) {
            $files = Get-ChildItem -LiteralPath $dir -File -Filter $pattern -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $matchedFiles.Add($file.FullName)
            }
        }
    }

    return $matchedFiles | Select-Object -Unique
}

function Find-AssetFile {
    param(
        [Parameter(Mandatory)][string]$RelativeAssetPath,
        [Parameter(Mandatory)][string[]]$SearchRoots
    )

    foreach ($variant in Get-AssetPathVariants -RelativeAssetPath $RelativeAssetPath) {
        $relativeWindows = $variant -replace '/', '\\'
        $leaf = Split-Path -Leaf $relativeWindows

        foreach ($root in $SearchRoots) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

            $direct = Join-Path $root $relativeWindows
            if (Test-Path -LiteralPath $direct -PathType Leaf) {
                return (Get-Item -LiteralPath $direct).FullName
            }
        }

        foreach ($root in $SearchRoots) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

            $candidates = Get-ChildItem -LiteralPath $root -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue
            foreach ($candidate in $candidates) {
                $fullNormalized = $candidate.FullName -replace '\\', '/'
                if ($fullNormalized.EndsWith('/' + $variant, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $candidate.FullName
                }
            }
        }

        $hashedCandidates = @(Find-AssetCandidatesByPattern -Variant $variant -SearchRoots $SearchRoots)
        if ($hashedCandidates.Count -gt 0) {
            return $hashedCandidates[0]
        }
    }

    return $null
}

function Convert-CopiedAssets {
    param(
        [Parameter(Mandatory)][object[]]$CopiedAssets,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string]$CliPath
    )

    if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        throw "Source2Viewer-CLI.exe not found: $CliPath"
    }

    $decompiledRoot = Join-Path $DestinationDirectory 'decompiled_assets'
    New-Item -ItemType Directory -Path $decompiledRoot -Force | Out-Null

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($asset in $CopiedAssets) {
        $compiledSource = $asset.Source
        if (-not $compiledSource.EndsWith('_c', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $assetRelDir = Split-Path -Parent $asset.AssetPath
        $outDir = if ($assetRelDir) { Join-Path $decompiledRoot ($assetRelDir -replace '/', '\\') } else { $decompiledRoot }
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null

        $commandOutput = & $CliPath -i $compiledSource -o $outDir -d 2>&1
        $results.Add([pscustomobject]@{
            AssetPath = $asset.AssetPath
            Source    = $compiledSource
            OutputDir = $outDir
            Output    = ($commandOutput | Out-String).Trim()
        })
    }

    return $results
}

function Copy-ReferencedAssets {
    param(
        [Parameter(Mandatory)][string[]]$AssetPaths,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string[]]$SearchRoots
    )

    $found = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($assetPath in $AssetPaths) {
        $source = Find-AssetFile -RelativeAssetPath $assetPath -SearchRoots $SearchRoots
        if (-not $source) {
            $missing.Add($assetPath)
            continue
        }

        $target = Join-Path $DestinationDirectory ($assetPath -replace '/', '\\')
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $source -Destination $target -Force
        $found.Add([pscustomobject]@{
            AssetPath = $assetPath
            Source    = $source
            Target    = $target
        })
    }

    return [pscustomobject]@{
        Found   = $found
        Missing = $missing
    }
}

function Copy-ClosestXml {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$SelectedClL,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )

    $displayName = Get-PackageDisplayName $SelectedClL
    $pattern = "package_${displayName}*.xml"
    $xml = Get-ChildItem -LiteralPath $SelectedClL.DirectoryName -Filter '*.xml' -File |
        Where-Object { $_.Name -like $pattern } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($xml) {
        Copy-Item -LiteralPath $xml.FullName -Destination (Join-Path $DestinationDirectory $xml.Name) -Force
        return $xml.FullName
    }

    return $null
}

if ($PackagePath) {
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "PackagePath not found: $PackagePath"
    }
    $selectedFile = Get-Item -LiteralPath $PackagePath
}
else {
    $selectedFile = Select-PackageFile -Directory $AssetsBinPath -NameFilter $Filter -SelectedIndex $Index
}

# Prompt for asset extraction if not provided via CLI
if (-not $IncludeReferencedAssets -and -not $DecompileCompiledAssets) {
    $refInclude = [ref]$IncludeReferencedAssets
    $refDecompile = [ref]$DecompileCompiledAssets
    Read-AssetExtractionOptions -IncludeReferencedAssets $refInclude -DecompileCompiledAssets $refDecompile
    $IncludeReferencedAssets = $refInclude.Value
    $DecompileCompiledAssets = $refDecompile.Value
}

$packageName = Get-PackageDisplayName $selectedFile
$safeName = ($packageName -replace '[^a-zA-Z0-9._-]', '_')
$destination = Join-Path $OutputRoot $safeName

if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    throw "Output directory already exists: $destination`nUse -Force to overwrite it."
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null

$gzipCopyPath = Join-Path $destination ($safeName + '.gz')
$gmcaBlobPath = Join-Path $destination ($safeName + '.gmca')
$intermediatePaths = @($gzipCopyPath, $gmcaBlobPath)

if (-not $KeepDecompressedBlob) {
    Remove-ExtractionIntermediateFiles -Paths $intermediatePaths
}

try {
    Copy-Item -LiteralPath $selectedFile.FullName -Destination $gzipCopyPath -Force
    Expand-GzipFile -InputFile $gzipCopyPath -OutputFile $gmcaBlobPath
    $blobText = Get-BlobText -BlobPath $gmcaBlobPath
    $writtenCount = Export-GmcaTextEntries -BlobText $blobText -DestinationDirectory $destination
    $assetPaths = Get-ReferencedAssetPaths -BlobText $blobText

    $assetCopyResult = $null
    $assetRoots = $null
    $decompileResults = $null
    if ($IncludeReferencedAssets) {
        $assetRoots = Resolve-AssetSearchRoots -AssetsBinDirectory $AssetsBinPath -CustomRoots $AssetSearchRoots
        $assetCopyResult = Copy-ReferencedAssets -AssetPaths $assetPaths -DestinationDirectory $destination -SearchRoots $assetRoots

        if ($DecompileCompiledAssets -and $assetCopyResult.Found.Count -gt 0) {
            $decompileResults = Convert-CopiedAssets -CopiedAssets $assetCopyResult.Found -DestinationDirectory $destination -CliPath $VrfCliPath
        }

        $report = [pscustomobject]@{
            SearchRoots          = $assetRoots
            ReferencedAssetCount = $assetPaths.Count
            FoundCount           = $assetCopyResult.Found.Count
            MissingCount         = $assetCopyResult.Missing.Count
            Found                = $assetCopyResult.Found
            Missing              = $assetCopyResult.Missing
            DecompiledCount      = if ($decompileResults) { $decompileResults.Count } else { 0 }
            Decompiled           = $decompileResults
        }

        $reportPath = Join-Path $destination 'asset-report.json'
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    }

    $xmlPath = $null
    if ($CopyXml) {
        $xmlPath = Copy-ClosestXml -SelectedClL $selectedFile -DestinationDirectory $destination
    }

    $summary = [pscustomobject]@{
        PackageName        = $packageName
        SelectedClL        = $selectedFile.FullName
        OutputDirectory    = $destination
        ExtractedFileCount = $writtenCount
        ReferencedAssetCount = $assetPaths.Count
        CopiedAssetCount   = if ($assetCopyResult) { $assetCopyResult.Found.Count } else { 0 }
        MissingAssetCount  = if ($assetCopyResult) { $assetCopyResult.Missing.Count } else { 0 }
        DecompiledAssetCount = if ($decompileResults) { $decompileResults.Count } else { 0 }
        DecompressedBlob   = if ($KeepDecompressedBlob) { $gmcaBlobPath } else { "Deleted" }
        XmlCopied          = [bool]$xmlPath
        XmlPath            = $xmlPath
    }

    Write-Host ''
    Write-Host 'Extraction completed.' -ForegroundColor Green
    $summary | Format-List
}
finally {
    if (-not $KeepDecompressedBlob) {
        Remove-ExtractionIntermediateFiles -Paths $intermediatePaths
    }
}

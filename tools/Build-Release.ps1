[CmdletBinding()]
param(
    [string] $Version = '1.1.0',
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts\extguide-release' }
$privateDirectory = Join-Path $repositoryRoot 'src\ExtGuide\Private'
$resourceDirectory = Join-Path $repositoryRoot 'src\ExtGuide\Resources'
$assetDirectory = Join-Path $repositoryRoot 'src\ExtGuide\Assets'
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$outputPath = Join-Path $OutputDirectory ("ExtGuide-v$Version.ps1")

$header = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [uri] $ManifestUri
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
'@
$resourceLines = @('$script:ExtGuideEmbeddedResources = @{')
Get-ChildItem -LiteralPath $resourceDirectory -Filter 'strings.*.json' | Sort-Object Name | ForEach-Object {
    $language = $_.BaseName.Substring('strings.'.Length)
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName))
    $resourceLines += "    '$language' = '$base64'"
}
$resourceLines += '}'
$assetLines = @('$script:ExtGuideEmbeddedAssets = @{')
Get-ChildItem -LiteralPath $assetDirectory -Filter '*.png' | Sort-Object Name | ForEach-Object {
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName))
    $assetLines += "    '$($_.Name)' = '$base64'"
}
$assetLines += '}'
$parts = @($header, ($resourceLines -join "`r`n"), ($assetLines -join "`r`n"))
Get-ChildItem -LiteralPath $privateDirectory -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
    $parts += Get-Content -LiteralPath $_.FullName -Raw
}
$parts += '$script:ExtGuideHostAdapter = New-ExtGuideWindowsHostAdapter'
$parts += 'Invoke-ExtGuideBootstrap -ManifestUri $ManifestUri'
$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($outputPath, ($parts -join "`r`n`r`n"), $utf8WithBom)

$parseErrors = $null
$tokens = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($outputPath, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | ForEach-Object Message | Out-String) }

[pscustomobject]@{ Script = $outputPath; Sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant() }

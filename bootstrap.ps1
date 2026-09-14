[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [uri] $ManifestUri
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'src\ExtGuide\ExtGuide.psd1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw 'This source bootstrap must be run from an ExtGuide release checkout. For the one-line installer, use the self-contained release asset.'
}

Import-Module $modulePath -Force
Invoke-ExtGuideBootstrap -ManifestUri $ManifestUri

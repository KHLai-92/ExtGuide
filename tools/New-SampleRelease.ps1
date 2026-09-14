[CmdletBinding()]
param(
    [string] $OutputDirectory,
    [string] $AssetBaseUrl = 'https://github.com/YOUR-ORG/extguide-sample/releases/download/v1.0.0'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts\sample-release' }
$extensionDirectory = Join-Path $repositoryRoot 'examples\sample-extension\extension'
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$archivePath = Join-Path $OutputDirectory 'extguide-sample-v1.0.0.zip'
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
Compress-Archive -LiteralPath $extensionDirectory -DestinationPath $archivePath -CompressionLevel Optimal
$digest = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    schemaVersion = 1
    displayName = 'ExtGuide Sample'
    publisher = 'ExtGuide'
    installFolderName = 'SampleExtension'
    archiveUrl = "$AssetBaseUrl/extguide-sample-v1.0.0.zip"
    sha256 = $digest
    extensionRoot = 'extension'
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'installer-manifest.json') -Encoding UTF8
$digest | Set-Content -LiteralPath (Join-Path $OutputDirectory 'extguide-sample-v1.0.0.zip.sha256') -Encoding ASCII

[pscustomobject]@{ Archive = $archivePath; Digest = $digest; Manifest = (Join-Path $OutputDirectory 'installer-manifest.json') }

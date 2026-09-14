Set-StrictMode -Version 2.0

$script:ExtGuideModuleRoot = $PSScriptRoot
$script:ExtGuideEmbeddedResources = $null
$script:ExtGuideEmbeddedAssets = $null
$privateScripts = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' |
    Sort-Object Name

foreach ($privateScript in $privateScripts) {
    . $privateScript.FullName
}

$script:ExtGuideHostAdapter = New-ExtGuideWindowsHostAdapter

Export-ModuleMember -Function 'Invoke-ExtGuideBootstrap'

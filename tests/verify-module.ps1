$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1'
$moduleSourcePath = Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psm1'

$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $moduleSourcePath,
    [ref] $tokens,
    [ref] $parseErrors
)

if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List
    exit 1
}

Import-Module $modulePath -Force
$exportedCommands = @(Get-Command -Module ExtGuide)

if ($exportedCommands.Count -ne 1 -or $exportedCommands[0].Name -ne 'Invoke-ExtGuideBootstrap') {
    throw 'ExtGuide must export only Invoke-ExtGuideBootstrap.'
}

$manifestParameter = $exportedCommands[0].Parameters['ManifestUri']
if ($null -eq $manifestParameter -or $manifestParameter.ParameterType -ne [uri]) {
    throw 'Invoke-ExtGuideBootstrap must accept a URI through ManifestUri.'
}

[pscustomobject]@{
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ExportedCommand = $exportedCommands[0].Name
    ManifestParameterType = $manifestParameter.ParameterType.FullName
}

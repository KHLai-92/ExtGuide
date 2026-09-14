[CmdletBinding()]
param(
    [string] $ScreenshotPath,
    [string] $Culture
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
$module = Get-Module -Name ExtGuide
if ($Culture) { & $module { param($Name) Set-ExtGuideCultureOverride -CultureName $Name } $Culture }

if ($ScreenshotPath) {
    $resolvedParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($ScreenshotPath))
    $null = New-Item -ItemType Directory -Path $resolvedParent -Force
    & $module { param($Path) Export-ExtGuideGuidancePreview -Path $Path } ([System.IO.Path]::GetFullPath($ScreenshotPath))
}
else {
    & $module {
        $previewName = Get-ExtGuideText -Key 'PreviewDisplayName'
        Show-ExtGuideGuidanceWindow -DisplayName $previewName -InstalledRoot 'C:\Users\Example\AppData\Local\ExtGuide\SampleExtension\extension' -ChromeExecutable ''
    }
}

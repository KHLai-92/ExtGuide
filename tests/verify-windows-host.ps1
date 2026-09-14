$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
$module = Get-Module -Name ExtGuide

& $module {
    $running = @(Get-ExtGuideRunningChromeCandidates)
    $registered = @(Get-ExtGuideRegisteredChromeCandidates)
    $valid = @($running + $registered | Select-Object -Unique | Where-Object { Test-ExtGuideChromeExecutable -Path $_ })

    $form = New-ExtGuideForm -Title 'ExtGuide verification'
    Set-ExtGuideGuidanceControls -Form $form -DisplayName 'ExtGuide Sample' -InstalledRoot 'C:\Users\Example\AppData\Local\ExtGuide\SampleExtension\extension' -ChromeExecutable '' -PolicyNotice ''
    $interactiveControls = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -or $_ -is [System.Windows.Forms.TextBox] })
    $missingAccessibleNames = @($interactiveControls | Where-Object { [string]::IsNullOrWhiteSpace($_.AccessibleName) })
    $tabOrder = @($interactiveControls | Sort-Object TabIndex | ForEach-Object TabIndex)
    $guidanceTopMostAfterInitialPresentation = $form.TopMost
    $guidanceAutoScaleMode = [string] $form.AutoScaleMode
    $form.Dispose()

    if ($missingAccessibleNames.Count -gt 0) { throw 'One or more interactive guidance controls has no accessible name.' }
    if (($tabOrder -join ',') -ne '0,1,2,3,4') { throw "Unexpected guidance tab order: $($tabOrder -join ',')" }
    if ($guidanceTopMostAfterInitialPresentation) { throw 'The guidance window must return to normal z-order after its initial foreground presentation.' }
    if ($guidanceAutoScaleMode -ne 'Dpi') { throw "Unexpected guidance scaling mode: $guidanceAutoScaleMode" }

    [pscustomobject]@{
        RunningCandidates = $running.Count
        RegisteredCandidates = $registered.Count
        ValidAuthenticChromeCandidates = $valid.Count
        GuidanceTopMostAfterInitialPresentation = $guidanceTopMostAfterInitialPresentation
        GuidanceAutoScaleMode = $guidanceAutoScaleMode
        AccessibleInteractiveControls = $interactiveControls.Count
        TabOrder = $tabOrder -join ','
    }
}

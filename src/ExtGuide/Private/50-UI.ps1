$script:ExtGuideUiSessions = @{}

function Initialize-ExtGuideWinForms {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
}

function New-ExtGuideForm {
    param([string] $Title)

    Initialize-ExtGuideWinForms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.ClientSize = New-Object System.Drawing.Size(620, 520)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.AutoScaleMode = 'Dpi'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 252)
    return $form
}

function New-ExtGuideLabel {
    param([string] $Text, [int] $X, [int] $Y, [int] $Width, [int] $Height, [float] $Size = 10, [bool] $Bold = $false)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.AutoEllipsis = $true
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    return $label
}

function New-ExtGuideHighlightedStep {
    param(
        [string] $Text,
        [string] $Highlight,
        [System.Drawing.Color] $HighlightColor,
        [int] $X,
        [int] $Y,
        [int] $Width,
        [int] $Height
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.AccessibleName = $Text
    $panel.AccessibleRole = [System.Windows.Forms.AccessibleRole]::StaticText

    $highlightIndex = $Text.IndexOf($Highlight, [System.StringComparison]::CurrentCulture)
    if ($highlightIndex -lt 0) {
        $panel.Controls.Add((New-ExtGuideLabel -Text $Text -X 0 -Y 0 -Width $Width -Height $Height -Size 10.5))
        return $panel
    }

    $segments = @(
        [pscustomobject]@{ Text = $Text.Substring(0, $highlightIndex); Color = [System.Drawing.Color]::Empty },
        [pscustomobject]@{ Text = $Highlight; Color = $HighlightColor },
        [pscustomobject]@{ Text = $Text.Substring($highlightIndex + $Highlight.Length); Color = [System.Drawing.Color]::Empty }
    )
    $left = 0
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment.Text)) { continue }
        $label = New-ExtGuideLabel -Text $segment.Text -X $left -Y 0 -Width $Width -Height $Height -Size 10.5
        $label.AutoEllipsis = $false
        $label.AutoSize = $true
        if (-not $segment.Color.IsEmpty) {
            $label.ForeColor = $segment.Color
            $label.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
        }
        $panel.Controls.Add($label)
        $left += $label.Width
    }
    return $panel
}

function New-ExtGuideButton {
    param([string] $Text, [int] $X, [int] $Y, [int] $Width, [int] $TabIndex)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 38)
    $button.TabIndex = $TabIndex
    $button.AccessibleName = $Text
    return $button
}

function Show-ExtGuideAdministratorPermissionDialog {
    param([System.Windows.Forms.IWin32Window] $Owner)

    $form = New-ExtGuideForm -Title (Get-ExtGuideText -Key 'AdministratorPermissionTitle')
    $form.ClientSize = New-Object System.Drawing.Size(620, 260)
    $heading = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'AdministratorPermissionTitle') -X 28 -Y 24 -Width 560 -Height 38 -Size 16 -Bold $true
    $explanation = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'AdministratorPermissionExplanation') -X 30 -Y 72 -Width 550 -Height 82
    $elevate = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'UseAdministratorPermission') -X 30 -Y 190 -Width 235 -TabIndex 0
    $change = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'ChooseAnotherLocation') -X 277 -Y 190 -Width 185 -TabIndex 1
    $cancel = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'Cancel') -X 474 -Y 190 -Width 110 -TabIndex 2
    $elevate.BackColor = [System.Drawing.Color]::FromArgb(36, 99, 235)
    $elevate.ForeColor = [System.Drawing.Color]::White
    $choice = @{ Value = 'Cancel' }
    $elevate.Add_Click({ $choice.Value = 'Elevate'; $form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $change.Add_Click({ $choice.Value = 'Change'; $form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $cancel.Add_Click({ $choice.Value = 'Cancel'; $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel })
    $form.AcceptButton = $elevate
    $form.CancelButton = $cancel
    $form.Controls.AddRange(@($heading, $explanation, $elevate, $change, $cancel))
    if ($null -ne $Owner) { $null = $form.ShowDialog($Owner) } else { $null = $form.ShowDialog() }
    $form.Dispose()
    return [string] $choice.Value
}

function Get-ExtGuideAssetImage {
    param([Parameter(Mandatory = $true)][string] $Name)

    $bytes = $null
    if ($null -ne $script:ExtGuideEmbeddedAssets -and $script:ExtGuideEmbeddedAssets.ContainsKey($Name)) {
        $bytes = [Convert]::FromBase64String($script:ExtGuideEmbeddedAssets[$Name])
    }
    else {
        $assetPath = Join-Path (Join-Path $script:ExtGuideModuleRoot 'Assets') $Name
        if (Test-Path -LiteralPath $assetPath -PathType Leaf) { $bytes = [System.IO.File]::ReadAllBytes($assetPath) }
    }
    if ($null -eq $bytes) { return $null }

    $stream = New-Object System.IO.MemoryStream(,$bytes)
    try {
        $source = [System.Drawing.Image]::FromStream($stream)
        try { return New-Object System.Drawing.Bitmap($source) }
        finally { $source.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-ExtGuideVisualGuideAssetName {
    param([string] $CultureName)

    if ([string]::IsNullOrWhiteSpace($CultureName)) { $CultureName = $script:ExtGuideCultureOverride }
    if ((Resolve-ExtGuideLanguage -CultureName $CultureName) -eq 'zh-TW') { return 'chrome-extensions-page.zh-TW.png' }
    return 'chrome-extensions-page.png'
}

function Show-ExtGuideDestinationWindow {
    param($Manifest, [string] $RecommendedDestination, [string] $RememberedDestination)

    $form = New-ExtGuideForm -Title (Get-ExtGuideText -Key 'InstallTitle' -Arguments @([string] $Manifest.displayName))
    $initialDestination = if ($RememberedDestination) { $RememberedDestination } else { $RecommendedDestination }
    $state = @{ Destination = $initialDestination; IsCustom = [bool] $RememberedDestination; UseElevation = $false; IsUpdate = $false }
    $heading = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'InstallTitle' -Arguments @([string] $Manifest.displayName)) -X 28 -Y 24 -Width 560 -Height 40 -Size 18 -Bold $true
    $explanation = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'InstallExplanation') -X 30 -Y 76 -Width 550 -Height 52
    $pathLabel = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'FinalExtensionLocation') -X 30 -Y 145 -Width 300 -Height 25 -Bold $true
    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(30, 176)
    $pathBox.Size = New-Object System.Drawing.Size(555, 28)
    $pathBox.ReadOnly = $true
    $pathBox.Text = $state.Destination
    $pathBox.TabIndex = 0
    $pathBox.AccessibleName = Get-ExtGuideText -Key 'FinalExtensionLocation'
    $changeButton = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'ChangeLocation') -X 30 -Y 225 -Width 170 -TabIndex 1
    $installButton = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'InstallExtension') -X 390 -Y 430 -Width 195 -TabIndex 2
    $cancelButton = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'Cancel') -X 278 -Y 430 -Width 100 -TabIndex 3
    $installButton.BackColor = [System.Drawing.Color]::FromArgb(36, 99, 235)
    $installButton.ForeColor = [System.Drawing.Color]::White
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $status = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'DestinationHint') -X 30 -Y 286 -Width 550 -Height 70

    $refreshOperation = {
        $candidateRoot = Join-Path $state.Destination ([string] $Manifest.extensionRoot)
        $state.IsUpdate = Test-Path -LiteralPath (Join-Path $candidateRoot 'manifest.json') -PathType Leaf
        if ($state.IsUpdate) {
            $form.Text = Get-ExtGuideText -Key 'UpdateTitle' -Arguments @([string] $Manifest.displayName)
            $heading.Text = Get-ExtGuideText -Key 'UpdateTitle' -Arguments @([string] $Manifest.displayName)
            $explanation.Text = Get-ExtGuideText -Key 'UpdateExplanation'
            $installButton.Text = Get-ExtGuideText -Key 'UpdateExtension'
            $installButton.AccessibleName = $installButton.Text
        }
        else {
            $form.Text = Get-ExtGuideText -Key 'InstallTitle' -Arguments @([string] $Manifest.displayName)
            $heading.Text = Get-ExtGuideText -Key 'InstallTitle' -Arguments @([string] $Manifest.displayName)
            $explanation.Text = Get-ExtGuideText -Key 'InstallExplanation'
            $installButton.Text = Get-ExtGuideText -Key 'InstallExtension'
            $installButton.AccessibleName = $installButton.Text
        }
    }
    $chooseFolder = {
        $chooser = New-Object System.Windows.Forms.FolderBrowserDialog
        $chooser.Description = Get-ExtGuideText -Key 'ChooseBaseFolder'
        if ($chooser.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $state.Destination = Join-Path $chooser.SelectedPath ([string] $Manifest.installFolderName)
            $state.IsCustom = $true
            $pathBox.Text = $state.Destination
            & $refreshOperation
        }
        $chooser.Dispose()
    }
    $changeHandler = { & $chooseFolder }
    $installHandler = {
        if (Test-ExtGuideDestinationWritable -Destination $state.Destination) {
            $state.UseElevation = $false
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            return
        }
        $decision = Show-ExtGuideAdministratorPermissionDialog -Owner $form
        if ($decision -eq 'Elevate') {
            $state.UseElevation = $true
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
        elseif ($decision -eq 'Change') {
            & $chooseFolder
        }
        else {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        }
    }
    $changeButton.Add_Click($changeHandler)
    $installButton.Add_Click($installHandler)
    & $refreshOperation
    $form.AcceptButton = $installButton
    $form.CancelButton = $cancelButton
    $form.Controls.AddRange(@($heading, $explanation, $pathLabel, $pathBox, $changeButton, $cancelButton, $installButton, $status))
    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return [pscustomobject]@{ Cancelled = $true; Destination = $null; IsCustom = $false }
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::None
    $changeButton.Enabled = $false
    $cancelButton.Enabled = $false
    $installButton.Enabled = $false
    $status.Text = Get-ExtGuideText -Key 'Installing'
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $sessionKey = [string] $Manifest.displayName
    $script:ExtGuideUiSessions[$sessionKey] = $form
    return [pscustomobject]@{ Cancelled = $false; Destination = $state.Destination; IsCustom = $state.IsCustom; UseElevation = $state.UseElevation; IsUpdate = $state.IsUpdate }
}

function Select-ExtGuideFallbackDestination {
    param($Manifest)

    Initialize-ExtGuideWinForms
    while ($true) {
        $chooser = New-Object System.Windows.Forms.FolderBrowserDialog
        $chooser.Description = Get-ExtGuideText -Key 'ChooseWritableBaseFolder'
        $dialogResult = $chooser.ShowDialog()
        $selectedPath = $chooser.SelectedPath
        $chooser.Dispose()
        if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) { return $null }

        $destination = Join-Path $selectedPath ([string] $Manifest.installFolderName)
        if (Test-ExtGuideDestinationWritable -Destination $destination) {
            return [pscustomobject]@{ Destination = $destination; UseElevation = $false }
        }
        $decision = Show-ExtGuideAdministratorPermissionDialog
        if ($decision -eq 'Elevate') {
            return [pscustomobject]@{ Destination = $destination; UseElevation = $true }
        }
        if ($decision -eq 'Cancel') { return $null }
    }
}

function Close-ExtGuideUiSession {
    param([string] $DisplayName)

    if (-not $script:ExtGuideUiSessions.ContainsKey($DisplayName)) { return }
    $form = $script:ExtGuideUiSessions[$DisplayName]
    if ($null -ne $form -and -not $form.IsDisposed) { $form.Close(); $form.Dispose() }
    $script:ExtGuideUiSessions.Remove($DisplayName)
}

function Set-ExtGuideGuidanceControls {
    param([System.Windows.Forms.Form] $Form, [string] $DisplayName, [string] $InstalledRoot, [string] $ChromeExecutable, [string] $PolicyNotice, [bool] $WasUpdate = $false)

    $Form.SuspendLayout()
    foreach ($control in @($Form.Controls)) {
        if ($control -is [System.Windows.Forms.PictureBox] -and $null -ne $control.Image) {
            $control.Image.Dispose()
            $control.Image = $null
        }
    }
    $Form.Controls.Clear()
    $Form.ClientSize = if ($WasUpdate) { New-Object System.Drawing.Size(620, 520) } else { New-Object System.Drawing.Size(1160, 520) }
    $Form.Text = Get-ExtGuideText -Key $(if ($WasUpdate) { 'UpdateFinishTitle' } else { 'FinishTitle' }) -Arguments @($DisplayName)
    $Form.TopMost = $false
    $heading = New-ExtGuideLabel -Text (Get-ExtGuideText -Key $(if ($WasUpdate) { 'UpdateFinishHeading' } else { 'FinishHeading' })) -X 28 -Y 20 -Width $(if ($WasUpdate) { 560 } else { 1100 }) -Height 42 -Size 18 -Bold $true
    $subheading = New-ExtGuideLabel -Text (Get-ExtGuideText -Key $(if ($WasUpdate) { 'UpdateFinishSubheading' } else { 'FinishSubheading' })) -X 30 -Y 68 -Width $(if ($WasUpdate) { 550 } else { 1090 }) -Height 42
    $steps = if ($WasUpdate) {
        @((Get-ExtGuideText -Key 'UpdateStep1'), (Get-ExtGuideText -Key 'UpdateStep2'), (Get-ExtGuideText -Key 'UpdateStep3'))
    }
    else {
        @((Get-ExtGuideText -Key 'Step1'), (Get-ExtGuideText -Key 'Step2'), (Get-ExtGuideText -Key 'Step3'), (Get-ExtGuideText -Key 'Step4'), (Get-ExtGuideText -Key 'Step5'))
    }
    $y = 120
    for ($stepIndex = 0; $stepIndex -lt $steps.Count; $stepIndex++) {
        $step = $steps[$stepIndex]
        if (-not $WasUpdate -and $stepIndex -eq 0) {
            $Form.Controls.Add((New-ExtGuideHighlightedStep -Text $step -Highlight (Get-ExtGuideText -Key 'GreenOutlineTerm') -HighlightColor ([System.Drawing.Color]::FromArgb(24, 130, 54)) -X 42 -Y $y -Width 530 -Height 34))
        }
        elseif (-not $WasUpdate -and $stepIndex -eq 1) {
            $Form.Controls.Add((New-ExtGuideHighlightedStep -Text $step -Highlight (Get-ExtGuideText -Key 'OrangeOutlineTerm') -HighlightColor ([System.Drawing.Color]::FromArgb(217, 90, 0)) -X 42 -Y $y -Width 530 -Height 34))
        }
        else {
            $Form.Controls.Add((New-ExtGuideLabel -Text $step -X 42 -Y $y -Width 530 -Height 34 -Size 10.5))
        }
        $y += 38
    }
    $guideImage = if ($WasUpdate) { $null } else { Get-ExtGuideAssetImage -Name (Get-ExtGuideVisualGuideAssetName) }
    $guidePicture = $null
    $guideCaption = $null
    if ($null -ne $guideImage) {
        $guidePicture = New-Object System.Windows.Forms.PictureBox
        $guidePicture.Location = New-Object System.Drawing.Point(650, 112)
        $guidePicture.Size = New-Object System.Drawing.Size(480, 347)
        $guidePicture.Image = $guideImage
        $guidePicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $guidePicture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $guidePicture.AccessibleName = Get-ExtGuideText -Key 'VisualGuideAccessibleName'
        $guidePicture.AccessibleDescription = Get-ExtGuideText -Key 'VisualGuideAttribution'
        $guideCaption = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'VisualGuideAttribution') -X 650 -Y 464 -Width 480 -Height 22 -Size 8.5
    }
    $pathLabel = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'PreparedExtensionPath') -X 30 -Y 320 -Width 300 -Height 24 -Bold $true
    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(30, 348)
    $pathBox.Size = New-Object System.Drawing.Size(555, 28)
    $pathBox.ReadOnly = $true
    $pathBox.Text = $InstalledRoot
    $pathBox.AccessibleName = Get-ExtGuideText -Key 'PreparedExtensionPath'
    $pathBox.TabIndex = 0
    $copy = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'CopyPath') -X 30 -Y 394 -Width 120 -TabIndex 1
    $reopen = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'ReopenExtensionsPage') -X 162 -Y 394 -Width 205 -TabIndex 2
    $openFolder = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'OpenFolder') -X 379 -Y 394 -Width 130 -TabIndex 3
    $done = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'Done') -X 520 -Y 394 -Width 65 -TabIndex 4
    $copyHandler = { [System.Windows.Forms.Clipboard]::SetText($InstalledRoot) }
    $reopenHandler = { if ($ChromeExecutable) { $null = Open-ExtGuideChromeExtensionsPage -Executable $ChromeExecutable } }
    $openFolderHandler = { if (Test-Path -LiteralPath $InstalledRoot) { Start-Process -FilePath 'explorer.exe' -ArgumentList $InstalledRoot } }
    $doneHandler = { $Form.Close() }
    $copy.Add_Click($copyHandler)
    $reopen.Add_Click($reopenHandler)
    $openFolder.Add_Click($openFolderHandler)
    $done.Add_Click($doneHandler)
    $Form.Controls.AddRange(@($heading, $subheading, $pathLabel, $pathBox, $copy, $reopen, $openFolder, $done))
    if ($null -ne $guidePicture) { $Form.Controls.Add($guidePicture) }
    if ($null -ne $guideCaption) { $Form.Controls.Add($guideCaption) }
    if ($PolicyNotice) {
        $notice = New-ExtGuideLabel -Text $PolicyNotice -X 30 -Y 452 -Width $(if ($WasUpdate) { 550 } else { 1100 }) -Height 55 -Size 8.5
        $notice.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
        $notice.AccessibleName = Get-ExtGuideText -Key 'ManagedPolicyNotice'
        $Form.Controls.Add($notice)
    }
    $Form.AcceptButton = $done
    $Form.ResumeLayout($true)
}

function Show-ExtGuideGuidanceWindow {
    param([string] $DisplayName, [string] $InstalledRoot, [string] $ChromeExecutable, [bool] $WasUpdate = $false)

    Initialize-ExtGuideWinForms
    $form = $script:ExtGuideUiSessions[$DisplayName]
    if ($null -eq $form -or $form.IsDisposed) { $form = New-ExtGuideForm -Title (Get-ExtGuideText -Key 'FinishTitle' -Arguments @($DisplayName)) }
    Set-ExtGuideGuidanceControls -Form $form -DisplayName $DisplayName -InstalledRoot $InstalledRoot -ChromeExecutable $ChromeExecutable -PolicyNotice (Get-ExtGuideManagedPolicyNotice) -WasUpdate $WasUpdate
    $form.TopMost = $true
    if (-not $form.Visible) { $form.Show() }
    $form.BringToFront()
    $null = $form.Activate()
    [System.Windows.Forms.Application]::DoEvents()
    $form.TopMost = $false
    while ($form.Visible) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 40
    }
    $script:ExtGuideUiSessions.Remove($DisplayName)
    return [pscustomobject]@{ State = 'GuidanceReady'; DisplayName = $DisplayName; InstalledRoot = $InstalledRoot; WasUpdate = $WasUpdate }
}

function Select-ExtGuideChromeExecutable {
    param([string[]] $Candidates)

    Initialize-ExtGuideWinForms
    if ($Candidates.Count -gt 0) {
        $form = New-ExtGuideForm -Title (Get-ExtGuideText -Key 'ChooseChromeTitle')
        $form.ClientSize = New-Object System.Drawing.Size(620, 310)
        $heading = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'ChooseChromeHeading') -X 28 -Y 22 -Width 560 -Height 38 -Size 16 -Bold $true
        $explanation = New-ExtGuideLabel -Text (Get-ExtGuideText -Key 'ValidatedChromeExplanation') -X 30 -Y 66 -Width 550 -Height 28
        $list = New-Object System.Windows.Forms.ListBox
        $list.Location = New-Object System.Drawing.Point(30, 104)
        $list.Size = New-Object System.Drawing.Size(555, 105)
        $list.TabIndex = 0
        $list.AccessibleName = Get-ExtGuideText -Key 'ValidatedChromeInstallations'
        foreach ($candidate in $Candidates) { $null = $list.Items.Add($candidate) }
        $list.SelectedIndex = 0
        $useButton = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'UseSelectedChrome') -X 390 -Y 244 -Width 195 -TabIndex 1
        $useButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $browseButton = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'ChooseAnotherFile') -X 30 -Y 244 -Width 190 -TabIndex 2
        $cancelButton = New-ExtGuideButton -Text (Get-ExtGuideText -Key 'Cancel') -X 278 -Y 244 -Width 100 -TabIndex 3
        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $selection = @{ Path = $null }
        $useHandler = { $selection.Path = [string] $list.SelectedItem }
        $browseHandler = {
            $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $fileDialog.Title = Get-ExtGuideText -Key 'SelectChromeTitle'
            $fileDialog.Filter = Get-ExtGuideText -Key 'ChromeFileFilter'
            if ($fileDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                $selection.Path = $fileDialog.FileName
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            }
            $fileDialog.Dispose()
        }
        $useButton.Add_Click($useHandler)
        $browseButton.Add_Click($browseHandler)
        $form.AcceptButton = $useButton
        $form.CancelButton = $cancelButton
        $form.Controls.AddRange(@($heading, $explanation, $list, $useButton, $browseButton, $cancelButton))
        $dialogResult = $form.ShowDialog()
        $form.Dispose()
        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) { return $selection.Path }
        return $null
    }

    $chooser = New-Object System.Windows.Forms.OpenFileDialog
    $chooser.Title = Get-ExtGuideText -Key 'SelectChromeTitle'
    $chooser.Filter = Get-ExtGuideText -Key 'ChromeFileFilter'
    $chooser.CheckFileExists = $true
    $result = if ($chooser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $chooser.FileName } else { $null }
    $chooser.Dispose()
    return $result
}

function Show-ExtGuideFailureWindow {
    param($Failure)
    Initialize-ExtGuideWinForms
    $display = Get-ExtGuideFailureDisplay -Failure $Failure
    $text = "$($display.Message)`r`n`r`n$(Get-ExtGuideText -Key 'WhatToDo' -Arguments @($display.Recovery))"
    $null = [System.Windows.Forms.MessageBox]::Show($text, (Get-ExtGuideText -Key 'ErrorTitle' -Arguments @($display.Category)), 'OK', 'Error')
    foreach ($session in @($script:ExtGuideUiSessions.Values)) {
        if ($null -ne $session -and -not $session.IsDisposed) { $session.Close(); $session.Dispose() }
    }
    $script:ExtGuideUiSessions.Clear()
}

function Export-ExtGuideGuidancePreview {
    param([Parameter(Mandatory = $true)][string] $Path)

    Initialize-ExtGuideWinForms
    $previewName = Get-ExtGuideText -Key 'PreviewDisplayName'
    $form = New-ExtGuideForm -Title (Get-ExtGuideText -Key 'FinishTitle' -Arguments @($previewName))
    Set-ExtGuideGuidanceControls -Form $form -DisplayName $previewName -InstalledRoot 'C:\Users\Example\AppData\Local\ExtGuide\SampleExtension\extension' -ChromeExecutable '' -PolicyNotice ''
    $form.ShowInTaskbar = $false
    $form.Opacity = 0
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $bitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $form.Close()
    $form.Dispose()
    return $Path
}

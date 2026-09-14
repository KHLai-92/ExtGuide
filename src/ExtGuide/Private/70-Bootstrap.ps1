function Set-ExtGuideHostAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Adapter)
    $script:ExtGuideHostAdapter = $Adapter
}

function Test-ExtGuideHostOperation {
    param([hashtable] $Adapter, [string] $Operation)
    return $Adapter.ContainsKey($Operation) -and $Adapter[$Operation] -is [scriptblock]
}

function Invoke-ExtGuideHostOperation {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Adapter,
        [Parameter(Mandatory = $true)][string] $Operation,
        [object[]] $Arguments = @()
    )
    if (-not (Test-ExtGuideHostOperation -Adapter $Adapter -Operation $Operation)) {
        throw "The Windows host adapter does not provide the '$Operation' operation."
    }
    return & $Adapter[$Operation] @Arguments
}

function Invoke-ExtGuideOptionalHostOperation {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Adapter,
        [Parameter(Mandatory = $true)][string] $Operation,
        [object[]] $Arguments = @(),
        $Default = $null
    )
    if (-not (Test-ExtGuideHostOperation -Adapter $Adapter -Operation $Operation)) { return $Default }
    return & $Adapter[$Operation] @Arguments
}

function Resolve-ExtGuideChrome {
    param([Parameter(Mandatory = $true)][hashtable] $Adapter)

    $running = @(Invoke-ExtGuideHostOperation -Adapter $Adapter -Operation 'GetRunningChromeCandidates')
    $remembered = Invoke-ExtGuideOptionalHostOperation -Adapter $Adapter -Operation 'GetRememberedChrome'
    $registered = @(Invoke-ExtGuideHostOperation -Adapter $Adapter -Operation 'GetRegisteredChromeCandidates')
    $ordered = @($running)
    if (-not [string]::IsNullOrWhiteSpace([string] $remembered)) { $ordered += [string] $remembered }
    $ordered += @($registered)

    $unique = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $valid = @()
    foreach ($candidate in $ordered) {
        if ([string]::IsNullOrWhiteSpace([string] $candidate)) { continue }
        try { $normalized = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables(([string] $candidate).Trim('"'))) }
        catch { continue }
        if (-not $unique.Add($normalized)) { continue }
        if (Invoke-ExtGuideHostOperation -Adapter $Adapter -Operation 'TestChromeSignature' -Arguments @($normalized)) { $valid += $normalized }
    }

    $selected = $null
    if ($valid.Count -eq 1) { $selected = $valid[0] }
    elseif ($valid.Count -gt 1) { $selected = Invoke-ExtGuideOptionalHostOperation -Adapter $Adapter -Operation 'ChooseChrome' -Arguments @(, $valid) -Default $valid[0] }
    else { $selected = Invoke-ExtGuideOptionalHostOperation -Adapter $Adapter -Operation 'ChooseChrome' -Arguments @(, @()) }

    if ([string]::IsNullOrWhiteSpace([string] $selected)) {
        Throw-ExtGuideError -Category 'ChromeDiscovery' -Message 'ExtGuide could not find Google Chrome.' -Recovery 'Install stable Google Chrome, or choose chrome.exe when prompted.'
    }
    $selected = [System.IO.Path]::GetFullPath([string] $selected)
    if (-not (Invoke-ExtGuideHostOperation -Adapter $Adapter -Operation 'TestChromeSignature' -Arguments @($selected))) {
        Throw-ExtGuideError -Category 'ExecutableValidation' -Message 'The selected application is not an authentic stable Google Chrome executable.' -Recovery 'Choose chrome.exe from an official Google Chrome installation.'
    }
    $null = Invoke-ExtGuideOptionalHostOperation -Adapter $Adapter -Operation 'RememberChrome' -Arguments @($selected)
    return $selected
}

function Invoke-ExtGuideBootstrap {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][uri] $ManifestUri)

    $adapter = $script:ExtGuideHostAdapter
    try {
        if ($ManifestUri.Scheme -ne 'https') {
            Throw-ExtGuideError -Category 'Configuration' -Message 'The installer manifest URL must use HTTPS.' -Recovery 'Use the HTTPS manifest URL published by the extension author.'
        }
        try { $manifestJson = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'FetchText' -Arguments @($ManifestUri) }
        catch {
            if ($null -ne $_.Exception.Data['ExtGuideCategory']) { throw }
            Throw-ExtGuideError -Category 'Network' -Message 'ExtGuide could not download the installer manifest.' -Recovery 'Check the internet connection and verify the manifest URL.' -InnerException $_.Exception
        }
        $manifest = ConvertFrom-ExtGuideManifest -Json $manifestJson

        $localApplicationData = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'GetLocalApplicationDataPath'
        $recommended = [System.IO.Path]::Combine($localApplicationData, [string] $manifest.publisher, [string] $manifest.installFolderName)
        $remembered = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'GetRememberedDestination' -Arguments @($manifest)
        if ($remembered) {
            $rememberedExists = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'DestinationExists' -Arguments @([string] $remembered) -Default $false
            $rememberedWritable = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'TestDestinationWritable' -Arguments @([string] $remembered) -Default $true
            if (-not $rememberedExists -or -not $rememberedWritable) { $remembered = $null }
        }
        $choice = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'ChooseDestination' -Arguments @($manifest, $recommended, $remembered) -Default ([pscustomobject]@{ Cancelled = $false; Destination = $recommended; IsCustom = $false })
        if ($choice.Cancelled) { return [pscustomobject]@{ Status = 'Cancelled'; Destination = $recommended } }
        $destination = [System.IO.Path]::GetFullPath([string] $choice.Destination)
        if (-not (Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'TestDestinationWritable' -Arguments @($destination) -Default $true)) {
            Throw-ExtGuideError -Category 'Destination' -Message 'The selected installation location is not writable.' -Recovery 'Choose another folder where your Windows account can create and replace files.'
        }

        $hasInlineDigest = $null -ne $manifest.PSObject.Properties['sha256'] -and -not [string]::IsNullOrWhiteSpace([string] $manifest.sha256)
        $expectedSha256 = if ($hasInlineDigest) { ([string] $manifest.sha256).ToLowerInvariant() } else {
            try { ConvertFrom-ExtGuideDigestText -Text (Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'FetchText' -Arguments @([uri] $manifest.sha256Url)) }
            catch {
                if ($null -ne $_.Exception.Data['ExtGuideCategory']) { throw }
                Throw-ExtGuideError -Category 'Network' -Message 'ExtGuide could not download the archive digest.' -Recovery 'Check the connection or ask the publisher to restore the digest asset.' -InnerException $_.Exception
            }
        }
        try { [byte[]] $archiveBytes = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'FetchBytes' -Arguments @([uri] $manifest.archiveUrl) }
        catch {
            if ($null -ne $_.Exception.Data['ExtGuideCategory']) { throw }
            Throw-ExtGuideError -Category 'Network' -Message 'ExtGuide could not download the extension archive.' -Recovery 'Check the connection and retry; the current installation was not changed.' -InnerException $_.Exception
        }
        if ((Get-ExtGuideSha256 -Bytes $archiveBytes) -ne $expectedSha256) {
            Throw-ExtGuideError -Category 'Integrity' -Message 'The downloaded archive does not match its declared SHA-256 digest.' -Recovery 'Do not use this archive. Retry once, then ask the publisher to verify the release digest.'
        }

        $installation = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'WriteExtension' -Arguments @($archiveBytes, $destination, $manifest.extensionRoot)
        $null = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'RememberDestination' -Arguments @($manifest, $destination)
        $chromeExecutable = Resolve-ExtGuideChrome -Adapter $adapter
        $installedRoot = $installation.ExtensionRoot
        try { $null = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'SetClipboard' -Arguments @($installedRoot) }
        catch { Throw-ExtGuideError -Category 'Launch' -Message 'ExtGuide could not copy the extension path.' -Recovery 'Copy the displayed extension path manually.' -InnerException $_.Exception }

        $extensionsUri = 'chrome://extensions/'
        try { $null = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'LaunchChrome' -Arguments @($chromeExecutable, $extensionsUri) }
        catch { Throw-ExtGuideError -Category 'Launch' -Message 'ExtGuide installed the extension but could not open Chrome.' -Recovery 'Open Google Chrome and navigate to chrome://extensions manually.' -InnerException $_.Exception }
        $guide = Invoke-ExtGuideHostOperation -Adapter $adapter -Operation 'ShowGuide' -Arguments @($manifest.displayName, $installedRoot, $chromeExecutable)

        return [pscustomobject]@{
            Status = $guide.State
            Destination = $destination
            InstalledRoot = $installedRoot
            InstalledContent = $installation.Content
            WasUpdate = [bool] $installation.WasUpdate
            ClipboardPath = $installedRoot
            ChromeExecutable = $chromeExecutable
            LaunchUri = $extensionsUri
            Guide = $guide
        }
    }
    catch {
        $failure = ConvertTo-ExtGuideFailure -ErrorRecord $_
        $null = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'LogFailure' -Arguments @($failure)
        $null = Invoke-ExtGuideOptionalHostOperation -Adapter $adapter -Operation 'ShowError' -Arguments @($failure)
        return $failure
    }
}

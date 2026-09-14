function Invoke-ExtGuideDownload {
    param([Parameter(Mandatory = $true)][uri] $Uri, [switch] $AsBytes)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $lastError = $null
    foreach ($attempt in 1..2) {
        $client = New-Object System.Net.WebClient
        try {
            $client.Headers['User-Agent'] = 'ExtGuide/0.1 (+https://github.com/)'
            if ($AsBytes) { return $client.DownloadData($Uri) }
            return $client.DownloadString($Uri)
        }
        catch {
            $lastError = $_.Exception
            if ($attempt -lt 2) { Start-Sleep -Milliseconds 250 }
        }
        finally { $client.Dispose() }
    }
    Throw-ExtGuideError -Category 'Network' -Message 'ExtGuide could not download a required release asset.' -Recovery 'Check the internet connection and ask the publisher to confirm that the release asset is available.' -InnerException $lastError
}

function Write-ExtGuideSafeLog {
    param([string] $Category)
    try {
        $directory = Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ExtGuide') 'logs'
        $null = New-Item -ItemType Directory -Path $directory -Force
        $line = ('{0:u} Category={1} Status=Failed' -f [DateTime]::UtcNow, $Category)
        Add-Content -LiteralPath (Join-Path $directory 'extguide.log') -Value $line -Encoding UTF8
    }
    catch { }
}

function New-ExtGuideWindowsHostAdapter {
    return @{
        FetchText = { param($Uri) Invoke-ExtGuideDownload -Uri $Uri }
        FetchBytes = { param($Uri) Invoke-ExtGuideDownload -Uri $Uri -AsBytes }
        GetLocalApplicationDataPath = { [Environment]::GetFolderPath('LocalApplicationData') }
        ChooseDestination = { param($Manifest, $Recommended, $Remembered) Show-ExtGuideDestinationWindow -Manifest $Manifest -RecommendedDestination $Recommended -RememberedDestination $Remembered }
        DestinationExists = { param($Destination) Test-Path -LiteralPath $Destination -PathType Container }
        TestDestinationWritable = { param($Destination) Test-ExtGuideDestinationWritable -Destination $Destination }
        GetRememberedDestination = { param($Manifest) Get-ExtGuideRememberedDestination -Manifest $Manifest }
        RememberDestination = { param($Manifest, $Destination) Set-ExtGuideRememberedDestination -Manifest $Manifest -Destination $Destination }
        WriteExtension = { param($ArchiveBytes, $Destination, $ExtensionRoot) Install-ExtGuideArchiveForWindows -ArchiveBytes $ArchiveBytes -Destination $Destination -ExtensionRoot $ExtensionRoot }
        GetRunningChromeCandidates = { Get-ExtGuideRunningChromeCandidates }
        GetRegisteredChromeCandidates = { Get-ExtGuideRegisteredChromeCandidates }
        GetRememberedChrome = { Get-ExtGuideRememberedChrome }
        TestChromeSignature = { param($Path) Test-ExtGuideChromeExecutable -Path $Path }
        ChooseChrome = { param($Candidates) Select-ExtGuideChromeExecutable -Candidates $Candidates }
        RememberChrome = { param($Path) Set-ExtGuideRememberedChrome -Path $Path }
        SetClipboard = { param($Text) Initialize-ExtGuideWinForms; [System.Windows.Forms.Clipboard]::SetText($Text) }
        LaunchChrome = { param($Executable, $Uri) Open-ExtGuideChromeExtensionsPage -Executable $Executable -Uri $Uri }
        ShowGuide = { param($DisplayName, $InstalledRoot, $ChromeExecutable) Show-ExtGuideGuidanceWindow -DisplayName $DisplayName -InstalledRoot $InstalledRoot -ChromeExecutable $ChromeExecutable }
        ShowError = { param($Failure) Show-ExtGuideFailureWindow -Failure $Failure }
        LogFailure = { param($Failure) Write-ExtGuideSafeLog -Category $Failure.Category }
    }
}

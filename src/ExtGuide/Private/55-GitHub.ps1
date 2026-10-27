function Resolve-ExtGuideGitHubCli {
    $command = Get-Command gh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($root in @($env:ProgramFiles, [Environment]::GetFolderPath('LocalApplicationData'))) {
        foreach ($relative in @('GitHub CLI\gh.exe', 'Programs\GitHub CLI\gh.exe')) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            $candidate = Join-Path $root $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    Throw-ExtGuideError -Category 'Authentication' -Message 'GitHub CLI is required for private release downloads.' -Recovery 'Install GitHub CLI from https://cli.github.com/ or run: winget install --id GitHub.cli --source winget. Reopen PowerShell and retry.'
}

function Invoke-ExtGuideGitHubCli {
    param([Parameter(Mandatory = $true)][string] $Path,
          [Parameter(Mandatory = $true)][string[]] $Arguments,
          [switch] $Interactive)

    # Arguments are fixed flags or validated/percent-encoded API paths, never
    # credentials. Do not invoke a shell or expose gh's stderr in safe logs.
    foreach ($argument in $Arguments) {
        if ($argument -notmatch '^[A-Za-z0-9_./:%?=+,-]+\z') {
            Throw-ExtGuideError -Category 'Configuration' -Message 'Invalid GitHub CLI argument.' -Recovery 'Use an unmodified ExtGuide release and a GitHub repository name.'
        }
    }
    if ($Interactive) {
        & $Path @Arguments | Out-Host
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Bytes = [byte[]]@() }
    }
    $process = New-Object System.Diagnostics.Process
    $memory = New-Object System.IO.MemoryStream
    try {
        $process.StartInfo.FileName = $Path
        $process.StartInfo.Arguments = $Arguments -join ' '
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        # Suppress inherited HTTP debug output; gh itself owns authentication.
        $process.StartInfo.EnvironmentVariables.Remove('GH_DEBUG')
        $null = $process.Start()
        $copy = $process.StandardOutput.BaseStream.CopyToAsync($memory)
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill(); $process.WaitForExit()
            Throw-ExtGuideError -Category 'Network' -Message 'The GitHub download timed out.' -Recovery 'Check the connection and retry; the existing installation was not changed.'
        }
        $null = $copy.GetAwaiter().GetResult()
        $null = $errors.GetAwaiter().GetResult()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Bytes = $memory.ToArray() }
    }
    finally { $process.Dispose(); $memory.Dispose() }
}

function New-ExtGuideGitHubSession {
    param([Parameter(Mandatory = $true)][string] $Repository, [switch] $NoLogin)

    if ($Repository -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}\z' -or
        ($Repository -split '/')[1] -in @('.', '..')) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The GitHub repository must be OWNER/REPOSITORY.' -Recovery 'Use the private repository name supplied by the extension publisher.'
    }
    $cli = Resolve-ExtGuideGitHubCli
    $status = Invoke-ExtGuideGitHubCli -Path $cli -Arguments @('auth', 'status', '--active', '--hostname', 'github.com')
    if ($status.ExitCode -ne 0 -and -not $NoLogin) {
        Write-Host (Get-ExtGuideText -Key 'GitHubSignIn')
        $login = Invoke-ExtGuideGitHubCli -Path $cli -Arguments @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web') -Interactive
        if ($login.ExitCode -eq 0) {
            $status = Invoke-ExtGuideGitHubCli -Path $cli -Arguments @('auth', 'status', '--active', '--hostname', 'github.com')
        }
    }
    if ($status.ExitCode -ne 0) {
        Throw-ExtGuideError -Category 'Authentication' -Message 'GitHub authentication is required.' -Recovery 'Run gh auth login --hostname github.com --web, sign in with an authorized account, and retry.'
    }
    return @{ Repository = $Repository; Cli = $cli; Releases = @{} }
}

function Resolve-ExtGuideGitHubAsset {
    param([Parameter(Mandatory = $true)][hashtable] $Session,
          [Parameter(Mandatory = $true)][uri] $Uri)

    $match = [regex]::Match($Uri.AbsolutePath, '^/([^/]+)/([^/]+)/releases/(?:latest/download|download/([^/]+))/([^/]+)$')
    if ($Uri.Scheme -ne 'https' -or $Uri.DnsSafeHost -ine 'github.com' -or $Uri.Port -ne 443 -or
        $Uri.UserInfo -or $Uri.Query -or $Uri.Fragment -or -not $match.Success) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'Private downloads must use GitHub release asset URLs.' -Recovery 'Use the HTTPS manifest URL for the selected GitHub repository.'
    }
    $repository = $match.Groups[1].Value + '/' + $match.Groups[2].Value
    if ($repository -ine $Session.Repository) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The release asset belongs to a different repository.' -Recovery 'Ask the publisher to keep the manifest, archive, and digest in the selected repository.'
    }
    $name = [uri]::UnescapeDataString($match.Groups[4].Value)
    if ($name -match '[/\\]' -or $name -in @('.', '..')) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'Invalid GitHub asset name.' -Recovery 'Ask the publisher to use a direct release asset URL.'
    }
    $tag = [uri]::UnescapeDataString($match.Groups[3].Value)
    $key = if ($tag) { 'tag:' + $tag } else { 'latest' }
    if (-not $Session.Releases.ContainsKey($key)) {
        $endpoint = 'repos/' + $Session.Repository + '/releases/'
        $endpoint += if ($tag) { 'tags/' + [uri]::EscapeDataString($tag) } else { 'latest' }
        $result = Invoke-ExtGuideGitHubCli -Path $Session.Cli -Arguments @('api', '--hostname', 'github.com', '--method', 'GET', '-H', 'Accept:application/vnd.github+json', $endpoint)
        if ($result.ExitCode -ne 0) {
            Throw-ExtGuideError -Category 'Authentication' -Message 'The signed-in GitHub account cannot read this release.' -Recovery 'Confirm repository read access and the release tag. Use gh auth switch --hostname github.com if the wrong account is active.'
        }
        try { $release = [Text.Encoding]::UTF8.GetString($result.Bytes) | ConvertFrom-Json -ErrorAction Stop }
        catch { Throw-ExtGuideError -Category 'Network' -Message 'GitHub returned invalid release metadata.' -Recovery 'Check the connection and retry.' }
        if ($null -eq $release.PSObject.Properties['assets'] -or $null -eq $release.PSObject.Properties['tag_name'] -or
            $release.draft -or ($tag -and $release.tag_name -cne $tag)) {
            Throw-ExtGuideError -Category 'Configuration' -Message 'The GitHub release is not a published matching release.' -Recovery 'Ask the publisher to publish the requested version.'
        }
        $Session.Releases[$key] = $release
        # Pin latest and its tag to one response for the entire install/update.
        $Session.Releases['tag:' + $release.tag_name] = $release
    }
    $release = $Session.Releases[$key]
    $assets = @($release.assets | Where-Object { $_.name -ceq $name -and $_.state -eq 'uploaded' })
    [long] $assetId = 0
    if ($assets.Count -ne 1 -or -not [long]::TryParse([string]$assets[0].id, [ref]$assetId) -or $assetId -le 0) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The requested GitHub release asset was not found.' -Recovery 'Ask the publisher to upload the manifest, ZIP, and checksum assets.'
    }
    return 'repos/' + $Session.Repository + '/releases/assets/' + $assetId
}

function Invoke-ExtGuideGitHubDownload {
    param([Parameter(Mandatory = $true)][hashtable] $Session,
          [Parameter(Mandatory = $true)][uri] $Uri, [switch] $AsBytes)

    $endpoint = Resolve-ExtGuideGitHubAsset -Session $Session -Uri $Uri
    $result = Invoke-ExtGuideGitHubCli -Path $Session.Cli -Arguments @('api', '--hostname', 'github.com', '--method', 'GET', '-H', 'Accept:application/octet-stream', $endpoint)
    if ($result.ExitCode -ne 0) {
        Throw-ExtGuideError -Category 'Authentication' -Message 'GitHub did not allow the release asset download.' -Recovery 'Confirm that your signed-in account can read the private repository, then retry. The existing installation was not changed.'
    }
    if ($AsBytes) { return ,([byte[]]$result.Bytes) }
    return [Text.Encoding]::UTF8.GetString($result.Bytes).TrimStart([char]0xfeff)
}

function Get-ExtGuideGitHubReleases {
    param([hashtable] $Session, [hashtable] $Adapter)

    # Page explicitly so public and authenticated discovery have the same behavior.
    $releases = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for ($page = 1; ; $page++) {
        $endpoint = 'repos/' + $Session.Repository + '/releases?per_page=100&page=' + $page
        if ($Session.Cli) {
            $result = Invoke-ExtGuideGitHubCli -Path $Session.Cli -Arguments @('api', '--hostname', 'github.com', '--method', 'GET', '-H', 'Accept:application/vnd.github+json', $endpoint)
            if ($result.ExitCode -ne 0) {
                Throw-ExtGuideError -Category 'Authentication' -Message 'The signed-in GitHub account cannot list releases.' -Recovery 'Confirm repository read access and retry with the correct GitHub account.'
            }
            $json = [Text.Encoding]::UTF8.GetString($result.Bytes)
        }
        else {
            $json = Invoke-ExtGuideHostOperation -Adapter $Adapter -Operation 'FetchText' -Arguments @([uri]('https://api.github.com/' + $endpoint))
        }
        try {
            if (-not ([string] $json).TrimStart().StartsWith('[')) { throw 'Expected an array.' }
            $decoded = $json | ConvertFrom-Json -ErrorAction Stop
            $batch = @($decoded)
        }
        catch {
            Throw-ExtGuideError -Category 'Network' -Message 'GitHub returned invalid release metadata.' -Recovery 'Check the connection and retry.'
        }
        foreach ($release in $batch) {
            if ($null -eq $release -or $null -eq $release.PSObject.Properties['tag_name'] -or
                $null -eq $release.PSObject.Properties['assets'] -or $null -eq $release.PSObject.Properties['draft'] -or
                $null -eq $release.PSObject.Properties['prerelease']) {
                Throw-ExtGuideError -Category 'Network' -Message 'GitHub returned incomplete release metadata.' -Recovery 'Check the connection and retry.'
            }
            if ($release.draft -or [string]::IsNullOrWhiteSpace([string] $release.tag_name)) { continue }
            $manifests = @($release.assets | Where-Object { $_.name -ceq 'installer-manifest.json' -and $_.state -eq 'uploaded' })
            if ($manifests.Count -ne 1 -or -not $seen.Add([string] $release.tag_name)) { continue }
            $Session.Releases['tag:' + $release.tag_name] = $release
            $releases.Add($release)
        }
        if ($batch.Count -lt 100) { break }
    }
    return $releases.ToArray()
}

function Select-ExtGuideRelease {
    param([hashtable] $Session, [hashtable] $Adapter, [string] $ReleaseTag)

    $releases = @(Get-ExtGuideGitHubReleases -Session $Session -Adapter $Adapter)
    if ($releases.Count -eq 0) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'No published releases contain installer-manifest.json.' -Recovery 'Ask the publisher to attach an installer manifest and extension ZIP to each release.'
    }
    if ($ReleaseTag) {
        $selectedTag = $ReleaseTag
    }
    else {
        # Prefer the first stable release in GitHub order; prereleases remain selectable.
        $default = @($releases | Where-Object { -not $_.prerelease } | Select-Object -First 1)
        $defaultTag = if ($default.Count) { [string] $default[0].tag_name } else { [string] $releases[0].tag_name }
        $selectedTag = Invoke-ExtGuideHostOperation -Adapter $Adapter -Operation 'ChooseRelease' -Arguments @($Session.Repository, $releases, $defaultTag)
        if ([string]::IsNullOrWhiteSpace([string] $selectedTag)) { return $null }
    }
    $selected = @($releases | Where-Object { $_.tag_name -ceq $selectedTag })
    if ($selected.Count -ne 1) {
        Throw-ExtGuideError -Category 'Configuration' -Message 'The selected release is not available for installation.' -Recovery 'Choose a published release with installer-manifest.json attached.'
    }
    $Session.SelectedTag = [string] $selected[0].tag_name
    return [uri]('https://github.com/' + $Session.Repository + '/releases/download/' + [uri]::EscapeDataString($Session.SelectedTag) + '/installer-manifest.json')
}

function Set-ExtGuideSelectedReleaseManifest {
    param($Manifest, [hashtable] $Session)

    # A historical manifest must never silently fetch a newer archive or digest.
    foreach ($property in @('archiveUrl', 'sha256Url')) {
        if ($null -eq $Manifest.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string] $Manifest.$property)) { continue }
        $uri = [uri] $Manifest.$property
        $match = [regex]::Match($uri.AbsolutePath, '^/([^/]+)/([^/]+)/releases/(?:latest/download|download/([^/]+))/([^/]+)$')
        if (-not $match.Success) {
            Throw-ExtGuideError -Category 'Configuration' -Message 'The selected release manifest must reference GitHub release assets.' -Recovery 'Ask the publisher to attach its ZIP and checksum to the same release as the manifest.'
        }
        $tag = [uri]::UnescapeDataString($match.Groups[3].Value)
        if ($tag -and $tag -cne $Session.SelectedTag) {
            Throw-ExtGuideError -Category 'Configuration' -Message 'The selected manifest references a different release.' -Recovery 'Ask the publisher to use URLs for this release tag in its installer manifest.'
        }
        # Validate the original host/repository/URL before replacing latest.
        $Session.Releases['latest'] = $Session.Releases['tag:' + $Session.SelectedTag]
        $null = Resolve-ExtGuideGitHubAsset -Session $Session -Uri $uri
        $Manifest.$property = 'https://github.com/' + $Session.Repository + '/releases/download/' + [uri]::EscapeDataString($Session.SelectedTag) + '/' + $match.Groups[4].Value
    }
}

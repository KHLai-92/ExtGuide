$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force

InModuleScope ExtGuide {
    Describe 'GitHub release selection' {
        BeforeEach {
            $script:releaseTest = @{ Calls = @(); Chosen = 'v1.0.0'; Written = $false; Pages = @{}; Denied = $false }
            $assets = @(
                @{ name = 'installer-manifest.json'; state = 'uploaded'; id = 11 },
                @{ name = 'extension.zip'; state = 'uploaded'; id = 12 },
                @{ name = 'extension.sha256'; state = 'uploaded'; id = 13 }
            )
            $script:releaseTest.Releases = @(
                [pscustomobject]@{ tag_name = 'v2.0.0-beta.1'; name = 'Beta'; draft = $false; prerelease = $true; assets = $assets },
                [pscustomobject]@{ tag_name = 'v1.0.0'; name = 'Stable'; draft = $false; prerelease = $false; assets = $assets },
                [pscustomobject]@{ tag_name = 'v0.9.0'; name = 'Older'; draft = $false; prerelease = $false; assets = $assets },
                [pscustomobject]@{ tag_name = 'draft'; draft = $true; prerelease = $false; assets = $assets },
                [pscustomobject]@{ tag_name = 'no-manifest'; draft = $false; prerelease = $false; assets = @() }
            )
            $script:releaseTest.Json = ConvertTo-Json -InputObject $script:releaseTest.Releases -Depth 6
            $script:releaseTest.Bytes = [byte[]](1, 2, 3)
            $sha = Get-ExtGuideSha256 -Bytes $script:releaseTest.Bytes
            $script:releaseTest.Manifest = @{
                schemaVersion = 1; displayName = 'Sample'; publisher = 'Example'; installFolderName = 'Sample';
                extensionRoot = 'extension'; sha256Url = 'https://github.com/example/private/releases/latest/download/extension.sha256';
                archiveUrl = 'https://github.com/example/private/releases/latest/download/extension.zip'
            } | ConvertTo-Json
            $script:releaseTest.Digest = $sha
            $script:releaseTest.Adapter = @{
                FetchText = { param($Uri)
                    $script:releaseTest.Calls += $Uri.AbsoluteUri
                    if ($Uri.DnsSafeHost -eq 'api.github.com') { return $script:releaseTest.Json }
                    if ($Uri.AbsolutePath.EndsWith('.sha256')) { return $script:releaseTest.Digest }
                    return $script:releaseTest.Manifest
                }
                FetchBytes = { param($Uri) $script:releaseTest.Calls += $Uri.AbsoluteUri; return ,$script:releaseTest.Bytes }
                ChooseRelease = { param($Repository, $Releases, $DefaultTag)
                    $script:releaseTest.Offered = @($Releases.tag_name)
                    $script:releaseTest.Default = $DefaultTag
                    return $script:releaseTest.Chosen
                }
                GetLocalApplicationDataPath = { 'C:\ExtGuideTest' }
                ChooseDestination = { param($Manifest, $Recommended, $Remembered)
                    # Stop before real installation unless a test asks for writing.
                    return [pscustomobject]@{ Cancelled = -not $script:releaseTest.Install; Destination = $Recommended; UseElevation = $false }
                }
                WriteExtension = { param($Bytes, $Destination, $Root, $Context)
                    $script:releaseTest.Written = $true
                    return [pscustomobject]@{ ExtensionRoot = Join-Path $Destination $Root; Content = @{}; WasUpdate = $false; PreviousVersion = ''; InstalledVersion = '1.0.0' }
                }
                GetRunningChromeCandidates = { 'C:\Chrome\chrome.exe' }
                GetRegisteredChromeCandidates = { @() }
                TestChromeSignature = { $true }
                SetClipboard = { param($Text) }
                LaunchChrome = { param($Executable, $Uri) }
                ShowGuide = { param($Name, $Root, $Chrome, $Update) [pscustomobject]@{ State = 'GuidanceReady' } }
                ShowError = { param($Failure) $script:releaseTest.Failure = $Failure }
                LogFailure = { param($Failure) }
            }
            $script:releaseTest.Install = $false
            $script:previousReleaseAdapter = $script:ExtGuideHostAdapter
            Set-ExtGuideHostAdapter -Adapter $script:releaseTest.Adapter
            Mock Resolve-ExtGuideGitHubCli { 'gh.exe' }
            Mock Invoke-ExtGuideGitHubCli {
                param($Path, $Arguments)
                $endpoint = $Arguments[-1]
                $script:releaseTest.Calls += $endpoint
                if ($Arguments[0] -eq 'auth') { return [pscustomobject]@{ ExitCode = 0; Bytes = [byte[]]@() } }
                if ($script:releaseTest.Denied) { return [pscustomobject]@{ ExitCode = 1; Bytes = [byte[]]@() } }
                $value = $script:releaseTest.Json
                if ($script:releaseTest.Pages.ContainsKey($endpoint)) { $value = $script:releaseTest.Pages[$endpoint] }
                if ($endpoint -match '/assets/11$') { $value = $script:releaseTest.Manifest }
                if ($endpoint -match '/assets/13$') { $value = $script:releaseTest.Digest }
                if ($endpoint -match '/assets/12$') { return [pscustomobject]@{ ExitCode = 0; Bytes = $script:releaseTest.Bytes } }
                return [pscustomobject]@{ ExitCode = 0; Bytes = [Text.Encoding]::UTF8.GetBytes($value) }
            }
        }

        AfterEach { $script:ExtGuideHostAdapter = $script:previousReleaseAdapter }

        It 'offers old stable and beta releases and defaults to stable even when beta is first' {
            $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -NoGitHubLogin
            $result.Status | Should Be 'Cancelled'
            ($script:releaseTest.Offered -join ',') | Should Be 'v2.0.0-beta.1,v1.0.0,v0.9.0'
            $script:releaseTest.Default | Should Be 'v1.0.0'
        }

        It 'uses authenticated asset downloads for a selected older version without fetching latest' {
            $script:releaseTest.Chosen = 'v0.9.0'
            $script:releaseTest.Install = $true
            $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -NoGitHubLogin
            $result.Status | Should Be 'GuidanceReady'
            $script:releaseTest.Written | Should Be $true
            ($script:releaseTest.Calls -join ',') | Should Match '/assets/11.*?/assets/13.*?/assets/12'
            ($script:releaseTest.Calls -join ',') | Should Not Match '/latest|/tags/'
        }

        It 'installs an explicitly selected beta through the same verified download flow' {
            $script:releaseTest.Install = $true
            $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -NoGitHubLogin -ReleaseTag 'v2.0.0-beta.1'
            $result.Status | Should Be 'GuidanceReady'
            $script:releaseTest.Written | Should Be $true
            $script:releaseTest.ContainsKey('Offered') | Should Be $false
        }

        It 'pins public latest aliases for manifest, ZIP, and checksum to the selected beta without GitHub CLI' {
            $script:releaseTest.Chosen = 'v2.0.0-beta.1'
            $script:releaseTest.Install = $true
            $result = Invoke-ExtGuideBootstrap -ManifestUri 'https://github.com/example/private/releases/latest/download/installer-manifest.json'
            $result.Status | Should Be 'GuidanceReady'
            ($script:releaseTest.Calls -join ',') | Should Match '/download/v2\.0\.0-beta\.1/installer-manifest.json.*?/download/v2\.0\.0-beta\.1/extension.sha256.*?/download/v2\.0\.0-beta\.1/extension.zip'
            Assert-MockCalled Invoke-ExtGuideGitHubCli -Times 0 -Exactly -Scope It
        }

        It 'does not fetch assets or write anything after the release dialog is cancelled' {
            $script:releaseTest.Chosen = $null
            $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -NoGitHubLogin
            $result.Status | Should Be 'Cancelled'
            ($script:releaseTest.Calls -join ',') | Should Not Match '/assets/'
            $script:releaseTest.Written | Should Be $false
        }

        It 'rejects an unavailable release tag without falling back to stable' {
            $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -ReleaseTag 'missing'
            $result.Status | Should Be 'Failed'
            $result.Category | Should Be 'Configuration'
            ($script:releaseTest.Calls -join ',') | Should Not Match '/assets/'
        }

        It 'stops safely if release listing is denied' {
            $script:releaseTest.Denied = $true
            $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -NoGitHubLogin
            $result.Category | Should Be 'Authentication'
            $script:releaseTest.Written | Should Be $false
        }

        It 'reads past the first 100 releases so an older beta remains selectable' {
            $first = @(1..100 | ForEach-Object {
                [pscustomobject]@{ tag_name = "v$_"; draft = $false; prerelease = $false; assets = $script:releaseTest.Releases[1].assets }
            })
            $script:releaseTest.Pages['repos/example/private/releases?per_page=100&page=1'] = ConvertTo-Json -InputObject $first -Depth 6
            $script:releaseTest.Pages['repos/example/private/releases?per_page=100&page=2'] = ConvertTo-Json -InputObject @($script:releaseTest.Releases[0]) -Depth 6
            $session = New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin
            $releases = @(Get-ExtGuideGitHubReleases -Session $session -Adapter $script:releaseTest.Adapter)
            $releases.Count | Should Be 101
            $releases[-1].tag_name | Should Be 'v2.0.0-beta.1'
        }

        It 'handles an empty release list and malformed metadata without installing' {
            foreach ($json in @('[]', '{}', 'not json', '[{}]')) {
                $script:releaseTest.Json = $json
                $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private'
                $result.Status | Should Be 'Failed'
                $script:releaseTest.Written | Should Be $false
            }
        }

        It 'rejects another release, repository, or host in a selected manifest' {
            foreach ($url in @(
                'https://github.com/example/private/releases/download/v9/extension.zip',
                'https://github.com/other/private/releases/latest/download/extension.zip',
                'https://attacker.test/example/private/releases/latest/download/extension.zip'
            )) {
                $manifest = $script:releaseTest.Manifest | ConvertFrom-Json
                $manifest.archiveUrl = $url
                $script:releaseTest.Manifest = $manifest | ConvertTo-Json
                $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private'
                $result.Status | Should Be 'Failed'
                $result.Category | Should Be 'Configuration'
                $script:releaseTest.Written | Should Be $false
            }
        }

        It 'renders an accessible dropdown with a labeled selectable beta in each maintained language' {
            foreach ($culture in @('en-US', 'zh-TW')) {
                Set-ExtGuideCultureOverride -CultureName $culture
                $form = New-ExtGuideReleaseWindow -Repository 'example/private' -Releases $script:releaseTest.Releases[0..2] -DefaultTag 'v1.0.0'
                try {
                    $list = $form.Controls['ReleaseList']
                    [string] $list.DropDownStyle | Should Be 'DropDownList'
                    $list.SelectedItem.Tag | Should Be 'v1.0.0'
                    $list.Items[0].Label | Should Match ([regex]::Escape((Get-ExtGuideText -Key 'Prerelease')))
                    $list.SelectedIndex = 0
                    $list.SelectedItem.Tag | Should Be 'v2.0.0-beta.1'
                    [string]::IsNullOrWhiteSpace($list.AccessibleName) | Should Be $false
                }
                finally { $form.Dispose(); Set-ExtGuideCultureOverride -CultureName $null }
            }
        }
    }
}

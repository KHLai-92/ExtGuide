$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force

InModuleScope ExtGuide {
    Describe 'Authenticated GitHub release downloads' {
        BeforeEach {
            $script:githubTest = @{
                Authenticated = $true; Denied = $false; LoginExit = 0; Calls = @();
                Binary = [byte[]](0..255); MetadataCalls = 0
            }
            Mock Resolve-ExtGuideGitHubCli { 'gh.exe' }
            Mock Invoke-ExtGuideGitHubCli {
                param($Path, $Arguments, [switch]$Interactive)
                $script:githubTest.Calls += ,@($Arguments)
                if ($Arguments[0] -eq 'auth') {
                    if ($Arguments[1] -eq 'login') {
                        if ($script:githubTest.LoginExit -eq 0) { $script:githubTest.Authenticated = $true }
                        return [pscustomobject]@{ ExitCode = $script:githubTest.LoginExit; Bytes = [byte[]]@() }
                    }
                    return [pscustomobject]@{ ExitCode = $(if ($script:githubTest.Authenticated) { 0 } else { 1 }); Bytes = [byte[]]@() }
                }
                if ($script:githubTest.Denied) {
                    return [pscustomobject]@{ ExitCode = 1; Bytes = [Text.Encoding]::UTF8.GetBytes('credential-sentinel-do-not-log') }
                }
                $endpoint = $Arguments[-1]
                if ($endpoint -match '/releases/assets/2$') {
                    return [pscustomobject]@{ ExitCode = 0; Bytes = $script:githubTest.Binary }
                }
                if ($endpoint -match '/releases/assets/1$') {
                    return [pscustomobject]@{ ExitCode = 0; Bytes = [Text.Encoding]::UTF8.GetBytes('{"schemaVersion":1}') }
                }
                $script:githubTest.MetadataCalls++
                $json = '{"draft":false,"tag_name":"v2.0.4","assets":[{"name":"installer-manifest.json","id":1,"state":"uploaded"},{"name":"playmium.zip","id":2,"state":"uploaded"}]}'
                return [pscustomobject]@{ ExitCode = 0; Bytes = [Text.Encoding]::UTF8.GetBytes($json) }
            }
        }

        It 'downloads text and every binary byte through the authenticated asset API' {
            $session = New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin
            $text = Invoke-ExtGuideGitHubDownload -Session $session -Uri 'https://github.com/example/private/releases/latest/download/installer-manifest.json'
            $bytes = Invoke-ExtGuideGitHubDownload -Session $session -Uri 'https://github.com/example/private/releases/download/v2.0.4/playmium.zip' -AsBytes
            $text | Should Be '{"schemaVersion":1}'
            ($bytes -is [byte[]]) | Should Be $true
            [Convert]::ToBase64String($bytes) | Should Be ([Convert]::ToBase64String([byte[]](0..255)))
            $script:githubTest.MetadataCalls | Should Be 1
            ($script:githubTest.Calls[-1] -join ' ') | Should Match 'Accept:application/octet-stream repos/example/private/releases/assets/2$'
            ($script:githubTest.Calls | ForEach-Object { $_ -join ' ' } | Out-String) | Should Not Match 'Authorization|Bearer|--with-token|auth token'
        }

        It 'never sends authenticated requests to another host or repository' {
            $session = New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin
            foreach ($url in @(
                'http://github.com/example/private/releases/latest/download/a.zip',
                'https://github.com.attacker.test/example/private/releases/latest/download/a.zip',
                'https://github.com/other/private/releases/latest/download/a.zip',
                'https://github.com/example/private/releases/latest/download/a.zip?token=secret',
                'https://github.com/example/private/releases/latest/download/a.zip#fragment',
                'https://user:password@github.com/example/private/releases/latest/download/a.zip',
                'https://github.com:444/example/private/releases/latest/download/a.zip',
                'https://github.com/example/private/releases/latest/download/dir%2Fa.zip'
            )) {
                { Resolve-ExtGuideGitHubAsset -Session $session -Uri $url } | Should Throw
            }
            $script:githubTest.MetadataCalls | Should Be 0
            $script:githubTest.Calls.Count | Should Be 1
        }

        It 'rejects malformed repository names before running GitHub CLI' {
            foreach ($name in @('owner/repo/extra', '../repo', 'owner/..', 'owner/repo --token secret', 'https://github.com/owner/repo', "owner/repo`n")) {
                { New-ExtGuideGitHubSession -Repository $name -NoLogin } | Should Throw
            }
            $script:githubTest.Calls.Count | Should Be 0
        }

        It 'offers GitHub web login only when the active account is not authenticated' {
            $script:githubTest.Authenticated = $false
            $session = New-ExtGuideGitHubSession -Repository 'example/private'
            $session.Repository | Should Be 'example/private'
            Assert-MockCalled Invoke-ExtGuideGitHubCli -Times 1 -Exactly -Scope It -ParameterFilter { $Interactive -and ($Arguments -join ' ') -eq 'auth login --hostname github.com --git-protocol https --web' }
        }

        It 'fails closed without opening a login when NoLogin is requested' {
            $script:githubTest.Authenticated = $false
            { New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin } | Should Throw
            Assert-MockCalled Invoke-ExtGuideGitHubCli -Times 0 -Exactly -Scope It -ParameterFilter { $Interactive }
        }

        It 'stops after a cancelled login' {
            $script:githubTest.Authenticated = $false
            $script:githubTest.LoginExit = 1
            { New-ExtGuideGitHubSession -Repository 'example/private' } | Should Throw
            $script:githubTest.MetadataCalls | Should Be 0
        }

        It 'requires repository access even when the account is authenticated and does not expose CLI output' {
            $session = New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin
            $script:githubTest.Denied = $true
            $failure = $null
            try { Invoke-ExtGuideGitHubDownload -Session $session -Uri 'https://github.com/example/private/releases/latest/download/installer-manifest.json' }
            catch { $failure = ConvertTo-ExtGuideFailure -ErrorRecord $_ }
            $failure.Category | Should Be 'Authentication'
            ($failure | Out-String) | Should Not Match 'credential-sentinel-do-not-log'
        }

        It 'rejects a missing asset instead of downloading a different file' {
            $session = New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin
            { Invoke-ExtGuideGitHubDownload -Session $session -Uri 'https://github.com/example/private/releases/latest/download/absent.zip' -AsBytes } | Should Throw
            Assert-MockCalled Invoke-ExtGuideGitHubCli -Times 0 -Exactly -Scope It -ParameterFilter { $Arguments -contains 'Accept:application/octet-stream' }
        }

        It 'fails safely if access is revoked after release metadata was resolved' {
            $session = New-ExtGuideGitHubSession -Repository 'example/private' -NoLogin
            $null = Resolve-ExtGuideGitHubAsset -Session $session -Uri 'https://github.com/example/private/releases/latest/download/playmium.zip'
            $script:githubTest.Denied = $true
            $failure = $null
            try { Invoke-ExtGuideGitHubDownload -Session $session -Uri 'https://github.com/example/private/releases/download/v2.0.4/playmium.zip' -AsBytes }
            catch { $failure = ConvertTo-ExtGuideFailure -ErrorRecord $_ }
            $failure.Category | Should Be 'Authentication'
            ($failure | Out-String) | Should Not Match 'credential-sentinel-do-not-log'
        }

        It 'does not change the existing installation when authentication fails in the bootstrap' {
            $script:githubTest.Authenticated = $false
            $previous = $script:ExtGuideHostAdapter
            try {
                Set-ExtGuideHostAdapter -Adapter @{
                    WriteExtension = { throw 'Existing installation must not be touched' }
                    ShowError = { param($Failure) }
                    LogFailure = { param($Failure) }
                }
                $result = Invoke-ExtGuideBootstrap -GitHubRepository 'example/private' -NoGitHubLogin
                $result.Status | Should Be 'Failed'
                $result.Category | Should Be 'Authentication'
            }
            finally { $script:ExtGuideHostAdapter = $previous }
        }
    }
}

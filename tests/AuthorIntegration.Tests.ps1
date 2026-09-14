$ErrorActionPreference = 'Stop'

Describe 'Extension author integration' {
    It 'publishes a version-pinned text-safe one-line installer' {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
        $command = @($readme -split '\r?\n' | Where-Object { $_ -like '*ExtGuide-v1.0.0.ps1*' })[0]

        $command | Should Not BeNullOrEmpty
        $command | Should Match ([regex]::Escape('[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12'))
        $command | Should Match ([regex]::Escape("DownloadString('https://github.com/KHLai-92/ExtGuide/releases/download/v1.0.0/ExtGuide-v1.0.0.ps1')"))
        $command | Should Match ([regex]::Escape("-ManifestUri 'https://github.com/YOUR-ORG/YOUR-EXTENSION/releases/latest/download/installer-manifest.json'"))
        $command | Should Not Match 'Invoke-WebRequest.+\.Content'
    }
}

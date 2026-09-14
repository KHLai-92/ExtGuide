function Get-ExtGuideSettingsPath {
    return Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ExtGuide') 'settings.json'
}

function Read-ExtGuideSettings {
    $path = Get-ExtGuideSettingsPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ destinations = @{}; chromePath = $null } }
    try {
        $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
        $destinations = @{}
        if ($null -ne $raw.destinations) {
            foreach ($property in $raw.destinations.PSObject.Properties) { $destinations[$property.Name] = [string] $property.Value }
        }
        return @{ destinations = $destinations; chromePath = [string] $raw.chromePath }
    }
    catch { return @{ destinations = @{}; chromePath = $null } }
}

function Write-ExtGuideSettings {
    param([Parameter(Mandatory = $true)][hashtable] $Settings)

    $path = Get-ExtGuideSettingsPath
    $directory = Split-Path -Parent $path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $temporary = $path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Get-ExtGuideSettingsKey { param($Manifest) return ([string] $Manifest.publisher + '|' + [string] $Manifest.installFolderName) }
function Get-ExtGuideRememberedDestination { param($Manifest) $settings = Read-ExtGuideSettings; return [string] $settings.destinations[(Get-ExtGuideSettingsKey -Manifest $Manifest)] }
function Set-ExtGuideRememberedDestination { param($Manifest, [string] $Destination) $settings = Read-ExtGuideSettings; $settings.destinations[(Get-ExtGuideSettingsKey -Manifest $Manifest)] = $Destination; Write-ExtGuideSettings -Settings $settings }
function Get-ExtGuideRememberedChrome { return [string] (Read-ExtGuideSettings).chromePath }
function Set-ExtGuideRememberedChrome { param([string] $Path) $settings = Read-ExtGuideSettings; $settings.chromePath = $Path; Write-ExtGuideSettings -Settings $settings }

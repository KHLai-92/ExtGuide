$script:ExtGuideCultureOverride = $null
$script:ExtGuideStringCache = @{}

function Set-ExtGuideCultureOverride {
    param([string] $CultureName)
    $script:ExtGuideCultureOverride = $CultureName
}

function Resolve-ExtGuideLanguage {
    param([string] $CultureName)

    if ([string]::IsNullOrWhiteSpace($CultureName)) { $CultureName = [System.Globalization.CultureInfo]::CurrentUICulture.Name }
    if ($CultureName -match '^zh-(TW|HK|MO|Hant)') { return 'zh-TW' }
    if ($CultureName -match '^zh-(CN|SG|Hans)') { return 'zh-TW' }
    if ($CultureName -match '^zh($|-)') { return 'zh-TW' }
    return 'en'
}

function Import-ExtGuideStrings {
    param([Parameter(Mandatory = $true)][string] $Language)

    if ($script:ExtGuideStringCache.ContainsKey($Language)) { return $script:ExtGuideStringCache[$Language] }
    $json = $null
    if ($null -ne $script:ExtGuideEmbeddedResources -and $script:ExtGuideEmbeddedResources.ContainsKey($Language)) {
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script:ExtGuideEmbeddedResources[$Language]))
    }
    else {
        $resourcePath = Join-Path (Join-Path $script:ExtGuideModuleRoot 'Resources') ("strings.$Language.json")
        if (Test-Path -LiteralPath $resourcePath) { $json = Get-Content -LiteralPath $resourcePath -Raw -Encoding UTF8 }
    }
    if ([string]::IsNullOrWhiteSpace($json) -and $Language -ne 'en') { return Import-ExtGuideStrings -Language 'en' }
    $object = $json | ConvertFrom-Json
    $strings = @{}
    foreach ($property in $object.PSObject.Properties) { $strings[$property.Name] = [string] $property.Value }
    $script:ExtGuideStringCache[$Language] = $strings
    return $strings
}

function Get-ExtGuideText {
    param(
        [Parameter(Mandatory = $true)][string] $Key,
        [object[]] $Arguments = @(),
        [string] $CultureName
    )

    if ([string]::IsNullOrWhiteSpace($CultureName)) { $CultureName = $script:ExtGuideCultureOverride }
    $language = Resolve-ExtGuideLanguage -CultureName $CultureName
    $strings = Import-ExtGuideStrings -Language $language
    if (-not $strings.ContainsKey($Key)) { $strings = Import-ExtGuideStrings -Language 'en' }
    if (-not $strings.ContainsKey($Key)) { return $Key }
    if ($Arguments.Count -gt 0) { return [string]::Format($strings[$Key], $Arguments) }
    return $strings[$Key]
}

function Get-ExtGuideFailureDisplay {
    param([Parameter(Mandatory = $true)] $Failure)

    $category = [string] $Failure.Category
    $supportedCategories = @('Configuration', 'Network', 'Integrity', 'Destination', 'Extraction', 'ChromeDiscovery', 'ExecutableValidation', 'Launch', 'Policy')
    if ($supportedCategories -notcontains $category) { $category = 'Configuration' }
    return [pscustomobject]@{
        Category = Get-ExtGuideText -Key ("FailureCategory{0}" -f $category)
        Message = Get-ExtGuideText -Key ("FailureMessage{0}" -f $category)
        Recovery = Get-ExtGuideText -Key ("FailureRecovery{0}" -f $category)
    }
}

$ErrorActionPreference = 'Stop'

Import-Module Pester -RequiredVersion 3.4.0 -Force
$result = Invoke-Pester -Script $PSScriptRoot -PassThru

if ($result.FailedCount -gt 0) {
    exit 1
}

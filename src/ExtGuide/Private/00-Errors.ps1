function New-ExtGuideException {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Configuration', 'Network', 'Integrity', 'Destination', 'Extraction', 'ChromeDiscovery', 'ExecutableValidation', 'Launch', 'Policy')]
        [string] $Category,
        [Parameter(Mandatory = $true)][string] $Message,
        [Parameter(Mandatory = $true)][string] $Recovery,
        [System.Exception] $InnerException
    )

    $exception = New-Object System.Exception($Message, $InnerException)
    $exception.Data['ExtGuideCategory'] = $Category
    $exception.Data['ExtGuideRecovery'] = $Recovery
    return $exception
}

function Throw-ExtGuideError {
    param(
        [Parameter(Mandatory = $true)][string] $Category,
        [Parameter(Mandatory = $true)][string] $Message,
        [Parameter(Mandatory = $true)][string] $Recovery,
        [System.Exception] $InnerException
    )

    throw (New-ExtGuideException -Category $Category -Message $Message -Recovery $Recovery -InnerException $InnerException)
}

function ConvertTo-ExtGuideFailure {
    param([Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord] $ErrorRecord)

    $category = [string] $ErrorRecord.Exception.Data['ExtGuideCategory']
    $recovery = [string] $ErrorRecord.Exception.Data['ExtGuideRecovery']
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Configuration' }
    if ([string]::IsNullOrWhiteSpace($recovery)) { $recovery = 'Review the installer manifest and try again.' }

    return [pscustomobject]@{
        Status = 'Failed'
        Category = $category
        Message = $ErrorRecord.Exception.Message
        Recovery = $recovery
    }
}

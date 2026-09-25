$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'src\ExtGuide\ExtGuide.psd1') -Force
$module = Get-Module -Name ExtGuide

function ConvertFrom-TestUtf8Base64 {
    param([string] $Value)
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

Describe 'ExtGuide localization' {
    It 'selects Traditional Chinese for Taiwan and Traditional Chinese cultures' {
        $texts = & $module {
            [pscustomobject]@{
                Taiwan = Get-ExtGuideText -Key 'FinishHeading' -CultureName 'zh-TW'
                HongKong = Get-ExtGuideText -Key 'Step2' -CultureName 'zh-HK'
                Hant = Get-ExtGuideText -Key 'CopyPath' -CultureName 'zh-Hant'
            }
        }

        $texts.Taiwan | Should Be (ConvertFrom-TestUtf8Base64 '5ZyoIENocm9tZSDkuK3lrozmiJDoqK3lrpo=')
        $texts.HongKong | Should Match (ConvertFrom-TestUtf8Base64 '6LyJ5YWl5pyq5bCB6KOd6aCF55uu')
        $texts.Hant | Should Be (ConvertFrom-TestUtf8Base64 '6KSH6KO96Lev5b6R')
    }

    It 'keeps Simplified Chinese archived and serves Traditional Chinese to Simplified Chinese cultures' {
        $archivedResource = Join-Path $repositoryRoot 'src\ExtGuide\Resources\strings.zh-CN.json'
        Test-Path -LiteralPath $archivedResource -PathType Leaf | Should Be $true

        $result = & $module {
            [pscustomobject]@{
                MainlandLanguage = Resolve-ExtGuideLanguage -CultureName 'zh-CN'
                SingaporeLanguage = Resolve-ExtGuideLanguage -CultureName 'zh-SG'
                HansLanguage = Resolve-ExtGuideLanguage -CultureName 'zh-Hans'
                Heading = Get-ExtGuideText -Key 'FinishHeading' -CultureName 'zh-CN'
                Caption = Get-ExtGuideText -Key 'VisualGuideCaption' -CultureName 'zh-CN'
                Image = Get-ExtGuideVisualGuideAssetName -CultureName 'zh-CN'
            }
        }

        $result.MainlandLanguage | Should Be 'zh-TW'
        $result.SingaporeLanguage | Should Be 'zh-TW'
        $result.HansLanguage | Should Be 'zh-TW'
        $result.Heading | Should Be (ConvertFrom-TestUtf8Base64 '5ZyoIENocm9tZSDkuK3lrozmiJDoqK3lrpo=')
        $result.Caption | Should Match (ConvertFrom-TestUtf8Base64 '5ZyW56S6')
        $result.Image | Should Be 'chrome-extensions-page.zh-TW.png'
    }

    It 'falls back to English for unsupported UI cultures' {
        $text = & $module { Get-ExtGuideText -Key 'FinishHeading' -CultureName 'fr-FR' }
        $text | Should Be 'Finish setup in Chrome'
    }

    It 'selects a visual guide whose language matches the maintained UI language' {
        $assets = & $module {
            [pscustomobject]@{
                English = Get-ExtGuideVisualGuideAssetName -CultureName 'en-US'
                TraditionalChinese = Get-ExtGuideVisualGuideAssetName -CultureName 'zh-TW'
                SimplifiedChineseFallback = Get-ExtGuideVisualGuideAssetName -CultureName 'zh-CN'
            }
        }

        $assets.English | Should Be 'chrome-extensions-page.png'
        $assets.TraditionalChinese | Should Be 'chrome-extensions-page.zh-TW.png'
        $assets.SimplifiedChineseFallback | Should Be 'chrome-extensions-page.zh-TW.png'
    }

    It 'renders localized accessible labels in the guidance window' {
        $result = & $module {
            Set-ExtGuideCultureOverride -CultureName 'zh-TW'
            $form = New-ExtGuideForm -Title 'preview'
            Set-ExtGuideGuidanceControls -Form $form -DisplayName 'Sample' -InstalledRoot 'C:\Sample\extension' -ChromeExecutable '' -PolicyNotice ''
            $buttonTexts = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object Text)
            $accessibleNames = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object AccessibleName)
            $pictures = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.PictureBox] })
            $labels = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] } | ForEach-Object Text)
            $pictureCount = $pictures.Count
            $pictureWidth = if ($pictureCount -gt 0) { $pictures[0].Image.Width } else { 0 }
            $pictureHeight = if ($pictureCount -gt 0) { $pictures[0].Image.Height } else { 0 }
            $pictureControlWidth = if ($pictureCount -gt 0) { $pictures[0].Width } else { 0 }
            $pictureControlHeight = if ($pictureCount -gt 0) { $pictures[0].Height } else { 0 }
            $pictureAccessibleName = if ($pictureCount -gt 0) { $pictures[0].AccessibleName } else { '' }
            $formClientWidth = $form.ClientSize.Width
            $topMost = $form.TopMost
            $form.Dispose()
            Set-ExtGuideCultureOverride -CultureName $null
            [pscustomobject]@{ Labels = $labels; Buttons = $buttonTexts; AccessibleNames = $accessibleNames; PictureCount = $pictureCount; PictureWidth = $pictureWidth; PictureHeight = $pictureHeight; PictureControlWidth = $pictureControlWidth; PictureControlHeight = $pictureControlHeight; PictureAccessibleName = $pictureAccessibleName; FormClientWidth = $formClientWidth; TopMost = $topMost }
        }

        ($result.Labels -contains (ConvertFrom-TestUtf8Base64 '5ZyoIENocm9tZSDkuK3lrozmiJDoqK3lrpo=')) | Should Be $true
        ($result.Buttons -contains (ConvertFrom-TestUtf8Base64 '6KSH6KO96Lev5b6R')) | Should Be $true
        ($result.Buttons -contains (ConvertFrom-TestUtf8Base64 '6YeN5paw6ZaL5ZWf5pO05YWF5Yqf6IO96aCB6Z2i')) | Should Be $true
        ($result.AccessibleNames -contains (ConvertFrom-TestUtf8Base64 '6ZaL5ZWf6LOH5paZ5aS+')) | Should Be $true
        $result.PictureCount | Should Be 1
        $result.PictureWidth | Should Be 521
        $result.PictureHeight | Should Be 376
        $result.PictureControlWidth | Should Be 480
        $result.PictureControlHeight | Should Be 347
        $result.FormClientWidth | Should Be 1160
        [string]::IsNullOrWhiteSpace($result.PictureAccessibleName) | Should Be $false
        $result.TopMost | Should Be $false
    }

    It 'renders update-specific reload guidance without the first-install image' {
        $result = & $module {
            Set-ExtGuideCultureOverride -CultureName 'zh-TW'
            $form = New-ExtGuideForm -Title 'preview'
            Set-ExtGuideGuidanceControls -Form $form -DisplayName 'Sample' -InstalledRoot 'C:\Sample\extension' -ChromeExecutable '' -PolicyNotice '' -WasUpdate $true
            $labels = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] } | ForEach-Object Text)
            $pictureCount = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.PictureBox] }).Count
            $width = $form.ClientSize.Width
            $form.Dispose()
            Set-ExtGuideCultureOverride -CultureName $null
            [pscustomobject]@{ Labels = $labels; PictureCount = $pictureCount; Width = $width }
        }

        ($result.Labels -join "`n") | Should Match (ConvertFrom-TestUtf8Base64 '6YeN5paw6LyJ5YWl')
        ($result.Labels -join "`n") | Should Not Match (ConvertFrom-TestUtf8Base64 '6LyJ5YWl5pyq5bCB6KOd6aCF55uu')
        $result.PictureCount | Should Be 0
        $result.Width | Should Be 620
    }

    It 'localizes every action in the administrator-permission dialogs' {
        $texts = & $module {
            [pscustomobject]@{
                UsePermission = Get-ExtGuideText -Key 'UseAdministratorPermission' -CultureName 'zh-TW'
                ChangeLocation = Get-ExtGuideText -Key 'ChooseAnotherLocation' -CultureName 'zh-TW'
            }
        }

        $texts.UsePermission | Should Be (ConvertFrom-TestUtf8Base64 '5L2/55So57O757Wx566h55CG5ZOh5qyK6ZmQ')
        $texts.ChangeLocation | Should Be (ConvertFrom-TestUtf8Base64 '6YG45pOH5YW25LuW5L2N572u')
    }

    It 'does not promise that every selected location avoids administrator permission' {
        $text = & $module { Get-ExtGuideText -Key 'InstallExplanation' -CultureName 'zh-TW' }

        $text | Should Match 'Windows'
        $text | Should Match (ConvertFrom-TestUtf8Base64 '57O757Wx566h55CG5ZOh5qyK6ZmQ')
        $text | Should Not Match (ConvertFrom-TestUtf8Base64 '5LiN6ZyA6KaB57O757Wx566h55CG5ZOh5qyK6ZmQ')
    }
}

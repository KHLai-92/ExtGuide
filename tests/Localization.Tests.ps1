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
                Attribution = Get-ExtGuideText -Key 'VisualGuideAttribution' -CultureName 'zh-CN'
                Image = Get-ExtGuideVisualGuideAssetName -CultureName 'zh-CN'
            }
        }

        $result.MainlandLanguage | Should Be 'zh-TW'
        $result.SingaporeLanguage | Should Be 'zh-TW'
        $result.HansLanguage | Should Be 'zh-TW'
        $result.Heading | Should Be (ConvertFrom-TestUtf8Base64 '5ZyoIENocm9tZSDkuK3lrozmiJDoqK3lrpo=')
        $result.Attribution | Should Match 'Chrome for Developers'
        $result.Image | Should Be 'chrome-extensions-page.zh-TW.png'
    }

    It 'falls back to English for unsupported UI cultures' {
        $text = & $module { Get-ExtGuideText -Key 'FinishHeading' -CultureName 'fr-FR' }
        $text | Should Be 'Finish setup in Chrome'
    }

    It 'shows failures entirely in the active UI language' {
        $display = & $module {
            Set-ExtGuideCultureOverride -CultureName 'zh-TW'
            try {
                Get-ExtGuideFailureDisplay -Failure ([pscustomobject]@{
                    Category = 'Destination'
                    Message = 'The extension root does not contain manifest.json.'
                    Recovery = 'Choose the correct existing installation or ask the publisher to rebuild the release archive.'
                })
            }
            finally { Set-ExtGuideCultureOverride -CultureName $null }
        }

        $display.Category | Should Be (ConvertFrom-TestUtf8Base64 '5a6J6KOd5L2N572u')
        $display.Message | Should Be (ConvertFrom-TestUtf8Base64 'RXh0R3VpZGUg54Sh5rOV5L2/55So5omA6YG455qE5a6J6KOd5L2N572u44CC')
        $display.Recovery | Should Be (ConvertFrom-TestUtf8Base64 '6KuL56K66KqN6LOH5paZ5aS+5LuN5a2Y5Zyo5LiU5Y+v5Lul6K6A5a+r77yb5b+F6KaB5pmC6YG45pOH5YW25LuW5L2N572u77yM5oiW5YWB6Kix57O757Wx566h55CG5ZOh5qyK6ZmQ44CC')
        ($display | Out-String) | Should Not Match 'manifest.json|Choose the correct'
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
            $stepSegmentLabels = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Panel] } | ForEach-Object { $_.Controls } | Where-Object { $_ -is [System.Windows.Forms.Label] })
            $labels = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] } | ForEach-Object Text) + @($stepSegmentLabels | ForEach-Object Text)
            $greenLabel = $stepSegmentLabels | Where-Object { $_.Text -eq (Get-ExtGuideText -Key 'GreenOutlineTerm') } | Select-Object -First 1
            $orangeLabel = $stepSegmentLabels | Where-Object { $_.Text -eq (Get-ExtGuideText -Key 'OrangeOutlineTerm') } | Select-Object -First 1
            $greenColor = if ($null -ne $greenLabel) { '{0},{1},{2}' -f $greenLabel.ForeColor.R, $greenLabel.ForeColor.G, $greenLabel.ForeColor.B } else { '' }
            $orangeColor = if ($null -ne $orangeLabel) { '{0},{1},{2}' -f $orangeLabel.ForeColor.R, $orangeLabel.ForeColor.G, $orangeLabel.ForeColor.B } else { '' }
            $pictureCount = $pictures.Count
            $pictureWidth = if ($pictureCount -gt 0) { $pictures[0].Image.Width } else { 0 }
            $pictureHeight = if ($pictureCount -gt 0) { $pictures[0].Image.Height } else { 0 }
            $pictureControlWidth = if ($pictureCount -gt 0) { $pictures[0].Width } else { 0 }
            $pictureControlHeight = if ($pictureCount -gt 0) { $pictures[0].Height } else { 0 }
            $pictureAccessibleName = if ($pictureCount -gt 0) { $pictures[0].AccessibleName } else { '' }
            $pictureAccessibleDescription = if ($pictureCount -gt 0) { $pictures[0].AccessibleDescription } else { '' }
            $formClientWidth = $form.ClientSize.Width
            $topMost = $form.TopMost
            $form.Dispose()
            Set-ExtGuideCultureOverride -CultureName $null
            [pscustomobject]@{ Labels = $labels; Buttons = $buttonTexts; AccessibleNames = $accessibleNames; GreenColor = $greenColor; OrangeColor = $orangeColor; PictureCount = $pictureCount; PictureWidth = $pictureWidth; PictureHeight = $pictureHeight; PictureControlWidth = $pictureControlWidth; PictureControlHeight = $pictureControlHeight; PictureAccessibleName = $pictureAccessibleName; PictureAccessibleDescription = $pictureAccessibleDescription; FormClientWidth = $formClientWidth; TopMost = $topMost }
        }

        ($result.Labels -contains (ConvertFrom-TestUtf8Base64 '5ZyoIENocm9tZSDkuK3lrozmiJDoqK3lrpo=')) | Should Be $true
        ($result.Buttons -contains (ConvertFrom-TestUtf8Base64 '6KSH6KO96Lev5b6R')) | Should Be $true
        ($result.Buttons -contains (ConvertFrom-TestUtf8Base64 '6YeN5paw6ZaL5ZWf5pO05YWF5Yqf6IO96aCB6Z2i')) | Should Be $true
        ($result.AccessibleNames -contains (ConvertFrom-TestUtf8Base64 '6ZaL5ZWf6LOH5paZ5aS+')) | Should Be $true
        ($result.Labels -join "`n") | Should Match (ConvertFrom-TestUtf8Base64 '57ag5qGG')
        ($result.Labels -join "`n") | Should Match (ConvertFrom-TestUtf8Base64 '5qmY5qGG')
        ($result.Labels -join "`n") | Should Match (ConvertFrom-TestUtf8Base64 '5L6G5rqQ77yaQ2hyb21lIGZvciBEZXZlbG9wZXJz')
        $result.GreenColor | Should Be '24,130,54'
        $result.OrangeColor | Should Be '217,90,0'
        $result.PictureCount | Should Be 1
        $result.PictureWidth | Should Be 521
        $result.PictureHeight | Should Be 376
        $result.PictureControlWidth | Should Be 480
        $result.PictureControlHeight | Should Be 347
        $result.FormClientWidth | Should Be 1160
        [string]::IsNullOrWhiteSpace($result.PictureAccessibleName) | Should Be $false
        $result.PictureAccessibleDescription | Should Match 'Chrome for Developers'
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

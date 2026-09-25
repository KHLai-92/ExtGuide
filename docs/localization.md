# Localization

ExtGuide reads the Windows UI culture through `.NET` `CurrentUICulture` and selects a bundled translation:

- `zh-TW`, `zh-HK`, `zh-MO`, and `zh-Hant` use Traditional Chinese.
- `zh-CN`, `zh-SG`, and `zh-Hans` also use Traditional Chinese. Simplified Chinese is no longer supported; its existing resource file is retained only as an inactive archive and receives no new or updated translations.
- Other Chinese culture names use Traditional Chinese; all non-Chinese cultures use English.

The source module stores translations as UTF-8 JSON resources. The release builder embeds those resources as UTF-8 Base64 in the self-contained PowerShell script, so the one-line installer still downloads only one version-pinned file.

ExtGuide does not send UI text or installation data to an online translation service. Windows 10/11 does not expose a universal text-translation API that meets the project's built-in PowerShell 5.1 and no-extra-runtime requirements. Microsoft Translator is an authenticated Azure service, while current Windows AI text APIs require newer Windows App SDK/Copilot+ capabilities and do not provide generally available live text translation.

Failure dialogs use localized category summaries and recovery guidance rather than exposing internal English exception messages. Detailed logs retain only the failure category and do not store installation paths.

To add a maintained language, copy the English resource, translate every value without changing its key, and extend `Resolve-ExtGuideLanguage`. Missing keys in an active language fall back to English. The archived Simplified Chinese resource is never selected at runtime.

## Visual guidance

The guidance window selects a visual whose labels match the active UI language. English uses an official Chrome Extensions page image. Traditional Chinese uses a localized derivative in which only the highlighted Chrome header controls are translated; the sample extension card below the orange outline remains unchanged. Simplified Chinese cultures receive the complete Traditional Chinese UI and Traditional Chinese visual, so text and image remain consistent without activating the archived Simplified Chinese resource. The numbered instructions identify the green and orange outlines directly, and those terms use matching text colors. A short source attribution is shown below the image. Screen-reader descriptions follow the same language policy. Every image is embedded in the self-contained release and does not make a network request at runtime.

The English image comes from the [Chrome for Developers Hello World extension tutorial](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world) and is used under the [Creative Commons Attribution 4.0 License](https://creativecommons.org/licenses/by/4.0/). The Traditional Chinese image is an attributed translation of that UI guidance. Both images contain Google's sample extension data and no ExtGuide user information.

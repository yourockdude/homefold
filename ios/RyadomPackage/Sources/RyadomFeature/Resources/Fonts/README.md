# Шрифты HomeFold

Дизайн использует семейства **SB Sans Display** и **SB Sans Text**. Файлы шрифтов в репозиторий не входят
(лицензия). Пока их нет, приложение использует системный SF Pro с теми же размерами, начертаниями,
межстрочными интервалами и трекингом.

Чтобы подключить шрифты, положите файлы `.otf`/`.ttf` в эту папку. Они регистрируются при запуске
(`RYFonts.register()`) и подхватываются по PostScript-именам:

| Токен (начертание) | Display | Text |
|---|---|---|
| Regular (N) | `SBSansDisplay-Regular` | `SBSansText-Regular` |
| Medium (M) | `SBSansDisplay-Medium` | `SBSansText-Medium` |
| Semibold (B/M в Headline) | `SBSansDisplay-SemiBold` | `SBSansText-SemiBold` |
| Bold | `SBSansDisplay-Bold` | `SBSansText-Bold` |

Другие имена добавьте в `RYFontFamily.postScriptNames` (`DesignSystem/Typography.swift`).

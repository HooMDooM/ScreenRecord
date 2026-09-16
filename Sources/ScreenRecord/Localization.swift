import Foundation

enum Language: String, CaseIterable {
    case ru, en

    var title: String { self == .ru ? "Русский" : "English" }
}

enum L {
    private static let table: [String: (ru: String, en: String)] = [
        "screen": ("Экран", "Screen"),
        "area": ("Диапазон", "Area"),
        "window": ("Окно", "Window"),
        "microphone": ("Микрофон", "Microphone"),
        "systemAudio": ("Системный звук", "System audio"),
        "mouseCursor": ("Курсор Мыши", "Mouse cursor"),
        "keyEvents": ("Событие Клавиатуры", "Keystrokes"),
        "noDevice": ("Нет устройства", "No device"),
        "off": ("Выключено", "Off"),
        "rec": ("REC", "REC"),
        "stop": ("СТОП", "STOP"),
        "pause": ("Пауза", "Pause"),
        "resume": ("Продолжить", "Resume"),
        "folder": ("Папка", "Folder"),
        "openFolder": ("Открыть папку записей", "Open recordings folder"),
        "screenshotArea": ("Скриншот области", "Screenshot area"),
        "screenshotWindow": ("Скриншот окна", "Screenshot window"),
        "screenshotScreen": ("Скриншот экрана", "Screenshot screen"),
        "recordArea": ("Записать область", "Record area"),
        "recordWindow": ("Записать окно", "Record window"),
        "recordScreen": ("Записать экран", "Record screen"),
        "chooseFolder": ("Выбрать папку сохранения…", "Choose output folder…"),
        "quit": ("Выйти", "Quit"),
        "show": ("Показать панель", "Show panel"),
        "startRecording": ("Начать запись", "Start recording"),
        "stopRecording": ("Остановить запись", "Stop recording"),
        "selectArea": ("Выделите область для записи", "Drag to select a recording area"),
        "selectWindow": ("Выберите окно для записи", "Click a window to record"),
        "selectAreaShot": ("Выделите область для скриншота", "Drag to select a screenshot area"),
        "selectWindowShot": ("Выберите окно для скриншота", "Click a window to capture"),
        "video": ("Видео", "Video"),
        "screenshotMode": ("Скриншот", "Screenshot"),
        "escToCancel": ("Esc — отмена, Enter — подтвердить", "Esc to cancel, Enter to confirm"),
        "confirmArea": ("Enter или двойной клик — подтвердить · маркеры меняют размер · потяните снаружи для новой области",
                        "Enter or double-click to confirm · handles resize · drag outside for a new area"),
        "noDelay": ("Без задержки", "No delay"),
        "delay": ("Задержка", "Countdown"),
        "seconds": ("сек", "s"),
        "original": ("Оригинал", "Original"),
        "permissionTitle": ("Нужен доступ к записи экрана", "Screen Recording permission required"),
        "permissionBody": (
            "Разрешите приложению запись экрана в Системных настройках → Конфиденциальность и безопасность → Запись экрана, затем перезапустите программу.",
            "Allow screen recording in System Settings → Privacy & Security → Screen Recording, then relaunch the app."
        ),
        "openSettings": ("Открыть настройки", "Open Settings"),
        "cancel": ("Отмена", "Cancel"),
        "accessibilityTitle": ("Нужен доступ к Универсальному доступу", "Accessibility permission required"),
        "accessibilityBody": (
            "Чтобы показывать нажатия клавиш в записи, разрешите доступ в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ.",
            "To display keystrokes in the recording, allow access in System Settings → Privacy & Security → Accessibility."
        ),
        "error": ("Ошибка", "Error"),
        "recordingFailed": (
            "Не удалось сохранить запись: она оказалась слишком короткой или произошла ошибка кодирования.",
            "The recording could not be saved: it was too short or an encoding error occurred."
        ),
        "noAreaSelected": ("Сначала выделите область для записи.", "Select a recording area first."),
        "ok": ("ОК", "OK"),
        "quality": ("Качество", "Quality"),
        "settings": ("Настройки", "Settings"),
        "tabGeneral": ("Основные", "General"),
        "tabVideo": ("Видео", "Video"),
        "tabScreenshot": ("Скриншот", "Screenshot"),
        "tabShortcuts": ("Клавиши", "Shortcuts"),
        "change": ("Изменить", "Change"),
        "revealVideo": ("Открывать Finder после записи", "Reveal recordings in Finder"),
        "revealShot": ("Открывать Finder после скриншота", "Reveal screenshots in Finder"),
        "language": ("Язык", "Language"),
        "launchAtLogin": ("Запускать при входе в систему", "Launch at login"),
        "resolutionTitle": ("Разрешение", "Resolution"),
        "fpsTitle": ("Частота кадров", "Frame rate"),
        "codec": ("Кодек", "Codec"),
        "micDevice": ("Устройство", "Input device"),
        "format": ("Формат файла", "File format"),
        "markupHint": (
            "После выделения области можно рисовать прямо на экране: ⌘C — копировать, ⌘S — сохранить, ⇧⌘S — сохранить в…, ⌘Z — отменить, Esc — отмена.",
            "After selecting a region you can draw right on screen: ⌘C copies, ⌘S saves, ⇧⌘S saves as…, ⌘Z undoes, Esc cancels."
        ),
        "hotkeyRecord": ("Запись видео", "Record video"),
        "hotkeyScreenshot": ("Скриншот области", "Screenshot area"),
        "pressKeys": ("Нажмите клавиши…", "Press keys…"),
        "shortcutHint": (
            "Нажмите на сочетание и введите новое. Нужен хотя бы один модификатор (⌘, ⌥ или ⌃). Esc — отмена ввода.",
            "Click a shortcut and type a new one. At least one modifier (⌘, ⌥ or ⌃) is required. Esc cancels."
        ),
        "back": ("Назад", "Back"),
        "displayN": ("Дисплей", "Display")
    ]

    static func t(_ key: String, _ lang: Language) -> String {
        guard let pair = table[key] else { return key }
        return lang == .ru ? pair.ru : pair.en
    }
}

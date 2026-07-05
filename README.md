# Agent Signals

Утилита строки меню macOS: показывает состояние всех агентских сессий
(Claude Code + Codex) по вкладкам iTerm. Замена пропускаемому звуку — визуальный
индикатор. Клик по сессии в меню фокусирует её вкладку iTerm.

Внутренняя цель Xcode и схема пока называются `AgentTrafficLight`, пользовательское имя
приложения — **Agent Signals**.

```
🔴2 🟡3 🟢1 ⚠️1      💤 = нет активных сессий
```

| Иконка | Состояние |
|--------|-----------|
| 🔴 | ждёт ввода / разрешения |
| 🟡 | агент работает |
| 🟢 | закончил — твой ход |
| ⚠️ | упал/прерван (процесс умер, не прислав `Stop`) |

UI приложения — на английском.

## Как устроено

Две независимые части, связанные только через папку `~/.claude/agent-traffic/`:

1. **Producer** — `hooks/agent-status.sh`. Подключён к хукам **Claude Code**
   (`~/.claude/settings.json`: `UserPromptSubmit`/`PostToolUse`→working,
   `PermissionRequest`→waiting, `Stop`→done, `SessionEnd`→удалить) и **Codex**
   (`~/.codex/hooks.json`: `UserPromptSubmit`→working, `Stop`→done; 2-й аргумент скрипта
   = `codex`). На каждое событие пишет `~/.claude/agent-traffic/<session_id>.json`
   с полями `session_id, state, pid, ts, agent, cwd, iterm` (атомарно: temp + `mv`).
   Ключ файла: `session_id` из payload, иначе `pid-<pid>` (уникальность без коллизий).
   `iterm` = `$ITERM_SESSION_ID` (для фокуса вкладки и дедупа).
   Codex-события без `$ITERM_SESSION_ID` считаются desktop/не-iTerm контекстом и
   не записываются, потому что индикатор измеряет именно вкладки iTerm.

2. **Consumer** — приложение (SwiftUI `MenuBarExtra`). Каждые 2 сек читает файлы,
   считает состояния и обновляет меню.

   **Строка меню** — счётчик-сумма всех активных сессий. **Выпадашка** — список **всех**
   активных сессий (🔴/⚠️/🟢/🟡, порядок: срочное сверху, 🟡 снизу): логотип агента
   (Claude/Codex) + статус + **имя вкладки iTerm** (по возможности, иначе имя проекта).
   Клик по строке фокусирует вкладку iTerm. В меню остаётся только пользовательский список
   сессий и **Quit**; системные действия очистки и диагностики не показываются.

### Живость и чистка (важно)

Живость определяется локальными сигналами из hook-файлов и `pid`; успешный снимок iTerm
дополнительно используется как консервативная сверка открытых вкладок:

- `filterVisibleTerminalRecords` — Codex без GUID удаляется как desktop/не-iTerm контекст;
  если iTerm успешно вернул список GUID, старые записи с отсутствующим GUID удаляются как
  закрытые вкладки. Новые записи после начала снимка не трогаются до следующего снимка.
- `dedupByTab` — одна строка на GUID вкладки (свежая по `ts`); проигравшие той же вкладки
  (вложенные codex-rescue и пр. дубли) удаляются с диска. После фильтрации победитель
  вкладки и не-Codex записи без GUID сохраняются.
- `aggregate` + `pidIsAlive` (`kill -0`): pid мёртв + `done`/`waiting` → файл удаляется;
  pid мёртв + `working` → ⚠️; `working` старше `staleAfter` (1 ч) → удаляется (защита от
  фантома при reuse PID).
- В коде есть диагностический снимок только для чтения и системная очистка показанных
  строк; они оставлены как внутренние возможности и не засоряют основное меню.

Запрос к iTerm через `osascript` используется для имён вкладок и сверки открытых GUID
(throttle ~10с, watchdog 5с, `character id 9/10` как разделитель — `tab` внутри `tell
"iTerm2"` перехватывается словарём iTerm!). При зависании/ошибке — фолбэк на имя проекта
и без чистки по GUID.

## Сборка

```bash
sh hooks/test_agent-status.sh
xcodebuild test -project AgentTrafficLight/AgentTrafficLight.xcodeproj -scheme AgentTrafficLight -destination 'platform=macOS' -only-testing:AgentTrafficLightTests
xcodebuild build -project AgentTrafficLight/AgentTrafficLight.xcodeproj -scheme AgentTrafficLight -configuration Release
```

App Sandbox выключен намеренно (`ENABLE_APP_SANDBOX=NO`) — нужен доступ к `~/.claude/`.
Основной путь распространения — Developer ID + notarized direct download, не Mac App Store.
`LSUIElement=YES` — только строка меню, без Dock. Шаблонный UITest `testLaunchPerformance`
флейкует (метрики запуска) — для верификации гонять `-only-testing:AgentTrafficLightTests`.

## Релиз вне App Store

Нужны Apple Developer Program, сертификат `Developer ID Application` в Keychain и профиль
notarytool:

```bash
xcrun notarytool store-credentials AgentSignalsNotary \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "88HMCU8P46" \
  --password "APP_SPECIFIC_PASSWORD"
```

Проверка готовности машины:

```bash
scripts/release.sh --preflight
```

`--preflight` проверяет Developer ID certificate и сохранённый профиль notarytool. Если
профиля нет, создай его командой выше.

Сборка, Developer ID export, notarization, stapling и финальный zip:

```bash
scripts/release.sh
```

Результат: `dist/AgentSignals.zip`. В сборке включён Hardened Runtime и entitlement
`com.apple.security.automation.apple-events`; при первом доступе к iTerm macOS попросит
разрешение Automation.

## Установка

Пользовательский релиз:

1. Распаковать `dist/AgentSignals.zip`.
2. Перенести `Agent Signals.app` в `/Applications`.
3. Открыть приложение.

Локальный development-build:

`AgentTrafficLight.app` → `/Applications/Agent Signals.app`.

Автозапуск: Системные настройки → Основные → Объекты входа → добавить
`/Applications/Agent Signals.app`.

Первый клик `Focus` / опрос имён вкладок запросит разрешение macOS на управление
iTerm (Конфиденциальность → Автоматизация) — это нужно один раз.

## Известные ограничения

- **Codex: только 🟡/🟢/⚠️, без 🔴.** Hook-система Codex поддерживает лишь
  `session_start`/`user_prompt_submit`/`stop` — события «ждёт разрешения» нет, а
  `SessionEnd` отсутствует (Codex-вкладки чистятся дедупом, по TTL 1 ч или системной
  очисткой).
  Codex Desktop не учитывается: у него нет `$ITERM_SESSION_ID`, и он не является
  вкладкой iTerm.
- **Имена вкладок — по возможности.** iTerm может переназначить GUID сессии (закрытие/
  восстановление окон), а `$ITERM_SESSION_ID` у запущенного процесса не обновляется →
  сохранённый GUID протухает → имя не находится → фолбэк на имя проекта. Освежается
  перезапуском агента в вкладке.
- **Очень долгий одиночный инструмент (>1 ч) без хуков** может пропасть из 🟡 (`working`
  старше `staleAfter`). Обычно `working` освежается `PostToolUse` на каждом инструменте.
- **🟢 накапливается** для законченных, но не закрытых вкладок — by design («твой ход»).

## Структура

```
hooks/agent-status.sh            producer-скрипт + тест
scripts/release.sh               Developer ID archive/export/notarization/stapling
exportOptions.plist              настройки Xcode export для Developer ID
docs/PROJECT_MEMORY.md           актуальная проектная память: контракты, ограничения, проверки
AgentTrafficLight/               Xcode-проект
  AgentTrafficLight/
    Aggregator.swift             чистая логика: счётчики, список, dedupByTab, диагностический отчёт
    StatusStore.swift            чтение файлов + таймер + фокус/имена вкладок iTerm
    AgentTrafficLightApp.swift   интерфейс MenuBarExtra (английские подписи)
  AgentTrafficLightTests/        XCTest для Aggregator
```

Plane: PTN-44.

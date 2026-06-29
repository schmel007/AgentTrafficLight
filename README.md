# AgentTrafficLight

Menu-bar утилита macOS: показывает в строке меню счётчик состояний всех агентских
сессий (Claude Code + Codex) по вкладкам iTerm. Замена пропускаемому звуку — визуальный
индикатор. Клик по сессии в меню фокусирует её вкладку iTerm.

```
🔴2 🟡1 🟢3 ⚠️1      💤 = нет активных сессий
```

| Иконка | Состояние |
|--------|-----------|
| 🟢 | агент работает |
| 🔴 | ждёт ввода / разрешения |
| 🟡 | закончил — твой ход |
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
   `iterm` = `$ITERM_SESSION_ID` для фокуса вкладки.

2. **Consumer** — приложение (SwiftUI `MenuBarExtra`). Каждые 2 сек читает файлы,
   считает состояния, проверяет живость `pid` (`kill -0`):
   - pid жив → счёт по состоянию;
   - pid мёртв + `working` (свежий `ts`) → ⚠️;
   - pid мёртв + `done`/`waiting` → штатно закрытая сессия, файл удаляется;
   - `working` с `ts` старше `staleAfter` (1 ч) → удаляется (защита от фантома при
     reuse PID).

   **Строка меню** — счётчик-сумма. **Выпадашка** — список только требующих внимания
   сессий (🔴/🟡/⚠️, без 🟢) в виде `🟡 [Claude] projectname`; клик фокусирует вкладку
   iTerm через `osascript`. Плюс «Clear ⚠️» (удалить файлы мёртвых сессий) и «Quit».

## Сборка

```bash
cd AgentTrafficLight
xcodebuild test  -scheme AgentTrafficLight -destination 'platform=macOS'   # юнит-тесты Aggregator
xcodebuild build -scheme AgentTrafficLight -configuration Release           # сборка .app
sh ../hooks/test_agent-status.sh                                            # тест producer
```

App Sandbox выключен намеренно (`ENABLE_APP_SANDBOX=NO`) — нужен доступ к `~/.claude/`.
Локальная утилита, подпись Apple Development, не для App Store. `LSUIElement=YES` —
только строка меню, без Dock.

## Автозапуск

`AgentTrafficLight.app` → `/Applications`, затем Системные настройки → Основные →
Объекты входа → добавить приложение.

**Первый клик «Focus»** запросит разрешение macOS на управление iTerm (Системные
настройки → Конфиденциальность → Автоматизация) — это нужно один раз.

## Известные ограничения

- **Codex: только 🟢/🟡/⚠️, без 🔴.** Hook-система Codex в текущей версии поддерживает
  лишь `session_start`/`user_prompt_submit`/`stop` — события «ждёт разрешения» нет, а
  `SessionEnd` отсутствует (Codex-сессии очищаются по TTL 1 ч или кнопкой «Clear ⚠️»).
- **Очень долгий одиночный инструмент (>1 ч) без хуков** может пропасть из 🟢: запись
  `working` старше `staleAfter` считается устаревшей. Плата за защиту от фантома; обычно
  `working` освежается `PostToolUse` на каждом инструменте.
- **🟡 накапливается** для законченных, но не закрытых вкладок — by design («твой ход»).

## Структура

```
hooks/agent-status.sh            producer-скрипт + тест
AgentTrafficLight/               Xcode-проект
  AgentTrafficLight/
    Aggregator.swift             чистая логика: счётчики + список внимания (юнит-тесты)
    StatusStore.swift            чтение файлов + таймер + фокус вкладки iTerm
    AgentTrafficLightApp.swift   MenuBarExtra UI (English)
  AgentTrafficLightTests/        XCTest для Aggregator
docs/superpowers/                спека и план
```

Plane: PTN-44.

# AgentTrafficLight

Менюбар-утилита macOS: показывает в строке меню счётчик состояний всех сессий
Claude Code (по вкладкам iTerm). Замена пропускаемому звуку — визуальный индикатор.

```
🔴2 🟡1 🟢3 ⚠️1      💤 = нет активных сессий
```

| Иконка | Состояние |
|--------|-----------|
| 🟢 | агент работает |
| 🔴 | ждёт ввода / разрешения |
| 🟡 | закончил — твой ход |
| ⚠️ | упал/прерван (процесс умер, не прислав `Stop`) |

## Как устроено

Две независимые части, связанные только через папку `~/.claude/agent-traffic/`:

1. **Producer** — `hooks/agent-status.sh`. Подключён к хукам Claude Code
   (`~/.claude/settings.json`): `UserPromptSubmit`→working, `PermissionRequest`→waiting,
   `Stop`→done, `SessionEnd`→удалить файл. На каждое событие пишет
   `~/.claude/agent-traffic/<session_id>.json` с полями `session_id, state, pid, ts`.
   Каждая вкладка = свой `session_id` → свой файл.

2. **Consumer** — приложение (SwiftUI `MenuBarExtra`). Каждые 2 сек читает файлы,
   считает состояния, проверяет живость `pid` (`kill -0`):
   - pid жив → счёт по состоянию;
   - pid мёртв + `working` → ⚠️ (файл остаётся);
   - pid мёртв + `done`/`waiting` → штатно закрытая сессия, файл удаляется.

   Кнопка «Очистить ⚠️» удаляет файлы всех мёртвых сессий.

## Сборка

```bash
cd AgentTrafficLight
xcodebuild test  -scheme AgentTrafficLight -destination 'platform=macOS'   # юнит-тесты Aggregator
xcodebuild build -scheme AgentTrafficLight -configuration Release           # сборка .app
```

App Sandbox выключен намеренно (`ENABLE_APP_SANDBOX=NO`) — приложению нужен доступ к
`~/.claude/`. Не предназначено для App Store; локальная утилита, подпись Apple Development.
`LSUIElement=YES` — приложение живёт только в строке меню, без иконки в Dock.

## Автозапуск

`AgentTrafficLight.app` → `/Applications`, затем Системные настройки → Основные →
Объекты входа → добавить приложение.

## Известные ограничения

- **Очень долгий одиночный инструмент (>1 ч) без хуков** может пропасть из 🟢: запись
  `working` старше `staleAfter` (1 ч) считается устаревшей и удаляется. Это плата за
  защиту от фантома (PID reuse): обычно `working` освежает `ts` на каждом инструменте
  (`PostToolUse`), так что порог достигается только при реально мёртвой сессии.
- **🟡 накапливается** для законченных, но не закрытых вкладок — это by design
  («твой ход»), не утечка.
- **`unknown.json`** — если `session_id` отсутствует и в stdin, и в env (на практике
  не встречается: Claude всегда отдаёт `session_id`).

## Структура

```
hooks/agent-status.sh            producer-скрипт + тест
AgentTrafficLight/               Xcode-проект
  AgentTrafficLight/
    Aggregator.swift             чистая логика подсчёта (юнит-тесты)
    StatusStore.swift            чтение файлов + таймер + ObservableObject
    AgentTrafficLightApp.swift   MenuBarExtra UI
  AgentTrafficLightTests/        XCTest для Aggregator
docs/superpowers/                спека и план
```

Plane: PTN-44.

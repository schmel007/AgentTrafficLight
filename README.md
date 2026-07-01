# AgentTrafficLight

Menu-bar утилита macOS: показывает в строке меню состояние всех агентских сессий
(Claude Code + Codex) по вкладкам iTerm. Замена пропускаемому звуку — визуальный
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
   `iterm` = `$ITERM_SESSION_ID` (для фокуса вкладки и дедупа).

2. **Consumer** — приложение (SwiftUI `MenuBarExtra`). Каждые 2 сек читает файлы,
   считает состояния и обновляет меню.

   **Строка меню** — счётчик-сумма всех активных сессий. **Выпадашка** — список **всех**
   активных сессий (🔴/🟡/🟢/⚠️, порядок: срочное сверху, 🟢 снизу): логотип агента
   (Claude/Codex) + статус + **имя вкладки iTerm** (best-effort, фолбэк — имя проекта).
   Клик по строке фокусирует вкладку iTerm. Кнопка **Clear** снимает все показанные
   строки (удаляет их файлы; активные пересоздадут на следующем хуке), **Quit** — выход.

### Живость и чистка (важно)

Живость определяется **надёжными** сигналами, НЕ запросом к iTerm (это принципиально —
запрос к iTerm ненадёжен: зависает, GUID вкладки протухает):

- `dedupByTab` — одна строка на GUID вкладки (свежая по `ts`); проигравшие той же вкладки
  (вложенные codex-rescue и пр. дубли) удаляются с диска. Победитель вкладки и записи без
  GUID сохраняются всегда → **опустошить живую вкладку невозможно**.
- `aggregate` + `pidIsAlive` (`kill -0`): pid мёртв + `done`/`waiting` → файл удаляется;
  pid мёртв + `working` → ⚠️; `working` старше `staleAfter` (1 ч) → удаляется (защита от
  фантома при reuse PID).

Запрос к iTerm через `osascript` используется **только для имён вкладок** (косметика,
throttle ~10с, watchdog 5с, `character id 9/10` как разделитель — `tab` внутри `tell
"iTerm2"` перехватывается словарём iTerm!). При зависании/ошибке — фолбэк на имя проекта.

## Сборка

```bash
cd AgentTrafficLight
xcodebuild test  -scheme AgentTrafficLight -destination 'platform=macOS' -only-testing:AgentTrafficLightTests
xcodebuild build -scheme AgentTrafficLight -configuration Release
sh ../hooks/test_agent-status.sh   # тест producer
```

App Sandbox выключен намеренно (`ENABLE_APP_SANDBOX=NO`) — нужен доступ к `~/.claude/`.
Локальная утилита, подпись Apple Development, не для App Store. `LSUIElement=YES` —
только строка меню, без Dock. Шаблонный UITest `testLaunchPerformance` флейкует (метрики
запуска) — для верификации гонять `-only-testing:AgentTrafficLightTests`.

## Автозапуск

`AgentTrafficLight.app` → `/Applications`, затем Системные настройки → Основные →
Объекты входа → добавить приложение.

**Первый клик «Focus»** / опрос имён вкладок запросит разрешение macOS на управление
iTerm (Конфиденциальность → Автоматизация) — это нужно один раз.

## Известные ограничения

- **Codex: только 🟢/🟡/⚠️, без 🔴.** Hook-система Codex поддерживает лишь
  `session_start`/`user_prompt_submit`/`stop` — события «ждёт разрешения» нет, а
  `SessionEnd` отсутствует (Codex-вкладки чистятся дедупом/по TTL 1 ч/кнопкой Clear).
- **Имена вкладок — best-effort.** iTerm может переназначить GUID сессии (закрытие/
  восстановление окон), а `$ITERM_SESSION_ID` у запущенного процесса не обновляется →
  сохранённый GUID протухает → имя не находится → фолбэк на имя проекта. Освежается
  перезапуском агента в вкладке.
- **Очень долгий одиночный инструмент (>1 ч) без хуков** может пропасть из 🟢 (`working`
  старше `staleAfter`). Обычно `working` освежается `PostToolUse` на каждом инструменте.
- **🟡 накапливается** для законченных, но не закрытых вкладок — by design («твой ход»).

## Структура

```
hooks/agent-status.sh            producer-скрипт + тест
AgentTrafficLight/               Xcode-проект
  AgentTrafficLight/
    Aggregator.swift             чистая логика: счётчики, список, dedupByTab (юнит-тесты)
    StatusStore.swift            чтение файлов + таймер + фокус/имена вкладок iTerm
    AgentTrafficLightApp.swift   MenuBarExtra UI (English)
  AgentTrafficLightTests/        XCTest для Aggregator
docs/superpowers/                спека и план
```

Plane: PTN-44.

# AI Companion v1.0(б) для Garry's Mod

> Полноценная AI-система компаньона с поддержкой LLM, TTS, боевой системы, транспорта и навигации.

[![Версия](https://img.shields.io/badge/версия-1.0--beta-blue)](https://github.com/Kirka444/AI-Companion-Garry-s-Mod)
[![Лицензия](https://img.shields.io/badge/лицензия-CC0--1.0-green)](https://creativecommons.org/publicdomain/zero/1.0/)
[![Garry's Mod](https://img.shields.io/badge/Garry's%20Mod-13-orange)](https://gmod.facepunch.com/)

---

## О проекте

**AI Companion** — это аддон для Garry's Mod, который добавляет в игру полноценного AI-компаньона. Бот может:
- Общаться через **LLM** (локальные и облачные модели)
- Говорить через **TTS** (синтез речи)
- Сражаться, следовать за игроком, водить транспорт
- Запоминать события и диалоги
- Работать в **одиночной игре** через NextBot (DrGBase)

Проект распространяется под лицензией **CC0 1.0 Universal** — вы можете свободно копировать, изменять и распространять код.

---

## Возможности

### Компаньон
- Создание, замена и удаление бота
- Настройка имени, модели, оружия
- Телепортация к игроку
- Автоматическое восстановление после смерти/транспорта
- Кастомные аватары в scoreboard

### LLM (языковые модели)
| Провайдер | Тип | Модели |
|-----------|-----|--------|
| **Local** | Локальный | LM Studio, Ollama (OpenAI-совместимые) |
| **OpenAI** | Облачный | gpt-4o-mini, gpt-4o |
| **DeepSeek** | Облачный | deepseek-chat |
| **Anthropic** | Облачный | claude-3-haiku, claude-3-sonnet |
| **Google** | Облачный | gemini-1.5-flash |
| **Grok** | Облачный | grok-2-1212 |

**Дополнительно:**
- История диалогов с настраиваемой глубиной
- Кастомные системные промпты для каждого игрока
- Контекст мира (карта, время, здоровье, NPC)
- Память бота (запоминание диалогов и событий)

### TTS (синтез речи)
| Провайдер | Тип | Особенности |
|-----------|-----|-------------|
| **ComfyUI** | Локальный | Кастомные workflow (OmniVoice и др.) |
| **ElevenLabs** | Облачный | Высокое качество |
| **Google Cloud TTS** | Облачный | WaveNet голоса |
| **Yandex SpeechKit** | Облачный | Русские голоса (MP3) |
| **VK Cloud Voice** | Облачный | Голоса VK (MP3) |

**Дополнительно:**
- Кэширование аудио
- Импорт workflow из ComfyUI (UI и API форматы)
- Автоинъекция текста в workflow
- Персональные настройки для каждого игрока

### Боевая система
- **5 режимов**: Stealth, Defender, Medic, Pacifist, Aggressive
- Очередь целей с приоритизацией
- Автоматический выбор оружия (ближний/дальний бой)
- Стрейф в бою
- Уклонение от гранат
- Медик-режим (лечение владельца и себя)
- RPG против бронированных целей
- Защита от дружественного огня

### Транспорт
- **HL2**: Jeep, Airboat, APC, Prisoner Pod
- **Glide**: машины, вертолёты, танки, катера
- Вертолёты: стрельба, ракеты, следование
- Танки: наведение, выстрел, движение
- Автопосадка при входе владельца
- Анти-застревание

### Навигация
- Полноценный NavMesh-пути
- Прямое движение (fallback)
- Лестницы, двери, прыжки, приседания
- 3-фазная система анти-застревания
- Телепортация при потере пути

### SOLO режим
- Отдельный NextBot на базе **DrGBase**
- Все режимы и транспорт
- Сохранение настроек в файл
- Работает только в одиночной игре

### AFK-система
- Определение неактивности игрока
- Случайные действия (сидеть, драться, танцевать)
- Спавн NPC для боя
- Возврат к игроку при активности

### Языки
16 языков: `ru`, `en`, `es`, `de`, `fr`, `zh`, `ja`, `ko`, `pt`, `it`, `pl`, `tr`, `uk`, `cs`, `sv`, `nl`

### Внешний вид
- Кастомные префиксы в чате
- Rainbow-префикс
- 23 предустановленных цвета
- Аватары в scoreboard

---

## Установка

### Через Steam Workshop
*[https://steamcommunity.com/sharedfiles/filedetails/?id=3784098380]*

### Вручную
1. Скачайте репозиторий
2. Поместите папку `ai_companion` в `garrysmod/addons/`
3. Перезапустите Garry's Mod

---

## Быстрый старт

### Мультиплеер
1. Откройте **Q меню → Утилиты → AI Companion**
2. Или введите в консоль: `ai_companion_menu`
3. Если меню не работает: `ai_companion_create`

### Одиночная игра
1. **Q меню → NPC → DrGBase → Solo Companion NPC**
2. Или в консоль: `ai_solo_spawn`

---

## Настройка

### Локальный LLM (LM Studio)

1. Включите **режим Разработчика**
2. Перейдите во вкладку **Сервер**
3. Откройте настройки сервера (шестерёнка)
4. Включите:
- **Обслуживание по локальной сети**
- **Включить CORS**
5. Загрузите модель (отключите режим «Думающий»)
6. Запустите сервер
7. Скопируйте:
- **IP** → поле `LLM IP (Локальный)`
- **Порт** (по умолчанию 1234) → поле `Порт LLM`
- **API Model Identifier** → поле `Модель LLM`
8. Переключите режим LLM на **Локальный**
9. Нажмите **Проверить подключение к серверам**

### Локальный TTS (ComfyUI)

1. Отредактируйте `.bat` файл ComfyUI, добавив:
```
--listen 0.0.0.0 --enable-cors-header
```
2. В ComfyUI: **Файл → Экспортировать (API)** → сохраните `.json` **без пробелов в имени**
3. Переместите файл в `garrysmod/data/`
4. В меню аддона:
- **Workflow → Загрузить Workflow** → укажите имя файла
- **Включить/Отключить Workflow**
- **Показать статус**
5. Вкладка **Основное**:
- `TTS IP` — ваш IP
- `Порт TTS` — `8188`
- Включите **TTS → Локально**
- Включите **TTS Персональный**
6. Нажмите **Проверить подключение к серверам**

Небольшая ремарка - установите AudioBatch [https://github.com/set-soft/ComfyUI-AudioBatch], установите ноду Audio Resampler между выходом аудио и вашим TTS (не забудьте поменять выход на "Сохранить в MP3"), поставьте значение в ноде Audio Resampler - 44100 hz -> тестируйте, должно работать в игре

### Облачные LLM/TTS

1. Вкладка **Основное** → переключите режим на **Облачный**
2. Введите:
- **LLM**: модель, API-ключ, эндпоинт (опционально)
- **TTS**: API-ключ, голос, язык, эндпоинт (опционально)

> **Внимание!** Не используйте API-ключи на серверах, которым не доверяете!

---

## Команды

### Чат-команды
| Команда | Описание |
|---------|----------|
| `!ai <вопрос>` | Приватный запрос к LLM |
| `!companion follow` | Следовать за игроком |
| `!companion stop` | Остановиться |
| `!companion point` | Указать направление |
| `!companion sit` | Сесть в транспорт |
| `!companion standup` | Выйти из транспорта |
| `!companion attack [цель]` | Атаковать цель |
| `!companion status` | Показать статус |
| `!companion help` | Справка |

### Консольные команды
| Команда | Описание |
|---------|----------|
| `ai_companion_menu` | Открыть меню |
| `ai_companion_create` | Создать бота |
| `ai_companion_remove` | Удалить бота |
| `ai_companion_replace` | Заменить бота |
| `ai_companion_teleport` | Телепортировать бота |
| `ai_companion_status` | Статус бота |
| `ai_solo_spawn` | Спавн SOLO NPC |
| `ai_solo_replace` | Замена SOLO NPC |
| `ai_solo_remove` | Удаление SOLO NPC |
| `ai_ping_servers` | Пинг LLM/TTS |
| `ai_test_llm` | Тест LLM |
| `ai_test_tts` | Тест TTS |
| `ai_reset_settings` | Сброс настроек |
| `ai_sync_global` | Синхронизация настроек |
| `ai_tts_workflow_load` | Загрузить workflow |
| `ai_tts_workflow_status` | Статус workflow |
| `ai_companion_afk_toggle` | Вкл/выкл AFK |

### Админ-команды
| Команда | Описание |
|---------|----------|
| `ai_companion_data_debug` | Отладка данных |
| `ai_companion_botmanager_debug` | Отладка менеджера |
| `ai_companion_logger_debug` | Отладка логгера |
| `ai_companion_config_debug` | Отладка конфига |
| `ai_state_save` | Сохранить настройки |
| `ai_state_load` | Загрузить настройки |

---

## Для разработчиков

### API сервисов

```lua
local locator = AICompanion.GetLocator()

-- Получить сервис
local llm = locator:get("llm")
local tts = locator:get("tts")
local botmanager = locator:get("botmanager")
local combat = locator:get("combat")
local vehicle = locator:get("vehicle")
local movement = locator:get("movement")

-- Использовать
llm:Ask(ply, "Привет!", false, function(response)
print("Ответ:", response)
end)
```

### Доступные сервисы

| Сервис | Методы |
|--------|--------|
| `utils` | `Log`, `IsValid`, `CreateCache`, `HTTPQueue`, `Hash` |
| `config` | `get`, `set`, `getDeep`, `GetLLMURL`, `GetTTSURL` |
| `state` | `getSetting`, `setSetting`, `getPlayerSetting` |
| `llm` | `Ask`, `GetHistory`, `AddHistory`, `ClearHistory` |
| `tts` | `Generate`, `GetProvider`, `InjectTextIntoWorkflow` |
| `botmanager` | `CreateBot`, `RemoveBot`, `GetBotByOwner`, `GetAllBots` |
| `spawn` | `CreateAICompanion`, `RemoveAICompanion` |
| `combat` | `HandleCombat`, `RequestTarget`, `IsHostileByDefault` |
| `vehicle` | `ControlVehicle`, `EnterDriverSeat`, `ForceExit` |
| `movement` | `MoveToTarget`, `ComeBackToPlayer`, `GetNavState` |
| `afk` | `IsEnabled`, `SetEnabled`, `ForceAFK`, `ExitAFK` |
| `llm_actions` | `ProcessResponse`, `SpawnEntity`, `ExecuteCommand` |
| `llm_remember` | `AddMessage`, `AddEvent`, `GetMemoryContext` |
| `menu` | `Open`, `Refresh`, `GetSettings`, `SendSetting` |



---

## Лицензия

**Creative Commons Zero v1.0 Universal (CC0 1.0)**

[![CC0](https://licensebuttons.net/p/zero/1.0/88x31.png)](https://creativecommons.org/publicdomain/zero/1.0/)

Вы можете свободно:
- Копировать
- Изменять
- Распространять
- Использовать в коммерческих целях

Аддон предоставляется «как есть», без каких-либо гарантий.

---

## Благодарности

- **AI Friend от RG Studio** — идея-прародитель
- **Gemini Nextbot (V2)** — вдохновение (удалено)
- **DrGBase** — [GitHub](https://github.com/Dragoteryx/drgbase)
- **Glide** — [Steam Workshop](https://steamcommunity.com/workshop/filedetails/?id=3389728250) | [GitHub](https://github.com/StyledStrike/gmod-glide)
- **gmpublisher** — [GitHub](https://github.com/WilliamVenner/gmpublisher)
- **Бетатестер** — типа_BOSS

---

## Ссылки

- **GitHub**: [Kirka444/AI-Companion-Garry-s-Mod](https://github.com/Kirka444/AI-Companion-Garry-s-Mod)
- **Steam Workshop**: *[https://steamcommunity.com/sharedfiles/filedetails/?id=3784098380]*
- **Лицензия**: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

---

## О коде

Основной код был сгенерирован с помощью генеративного ИИ, проверен и протестирован автором. Аддон активно оптимизируется и дорабатывается.

Если вы хотите внести свой вклад — создавайте Pull Request или Fork.

---

*Последнее обновление: 2026*

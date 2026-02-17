---
inclusion: always
---

# Правила для проекта TTraid ("Кормилец")

## Проект

- **Название:** TTraid ("Кормилец") — торговый робот для работы с T-Invest API (Тинькофф Инвестиции)
- **Язык:** Delphi 12 (Object Pascal), FMX (FireMonkey)
- **Платформа:** Windows (Win32/Win64)
- **API:** T-Invest REST API (JSON), базовый URL: `https://invest-public-api.tinkoff.ru/rest`
- **Справочник API:** #[[file:Docs/T-Invest-API-Reference.md]]

## Язык общения

- Ответы, комментарии, документация — **на русском**
- Имена переменных, функций, классов — **на английском**

## Модули ядра (Source/Core) — ПРИОРИТЕТНОЕ ИСПОЛЬЗОВАНИЕ

В проекте есть набор проверенных модулей в `Source/Core/`, которые **ОБЯЗАТЕЛЬНО** используются вместо стандартных механизмов Delphi:

### Потоки и многопоточность

| Вместо стандартного | Использовать из Core | Модуль |
|---------------------|---------------------|--------|
| `TThread` | `TMyThread` | `MyThread.pas` |
| `TTask` / `ITask` (System.Threading) | `TMyTask` / `TMyTaskAutoFree` и др. | `MyTask.pas` |
| `TCriticalSection` | `TMyCriticalSection` | `MyCriticalSection.pas` |
| `TMultiReadExclusiveWriteSynchronizer` | `TMyLightweightMREW` (внутри `TMyCriticalSection`) | `MyCriticalSection.pas` |
| `Boolean` для флагов между потоками | `TMyFlag` | `MyFlag.pas` |
| `TThreadList<T>` | `TMyThreadList<T>` | `MyThreadList.pas` |
| `TObjectList<T>` (потокобезопасный) | `TMyThreadObjectList<T>` | `MyThreadList.pas` |
| `TDictionary<K,V>` (потокобезопасный) | `TMyThreadDictionary<K,V>` | `MyThreadList.pas` |
| `TObjectDictionary<K,V>` (потокобезопасный) | `TMyThreadObjectDictionary<K,V>` | `MyThreadList.pas` |
| `TQueue<T>` (потокобезопасный) | `TMyThreadQueue<T>` | `MyThreadList.pas` |

### INI-файлы

| Вместо стандартного | Использовать из Core | Модуль |
|---------------------|---------------------|--------|
| `TIniFile` / `TMemIniFile` | `TMySaveIniFile` | `MyIniFile.pas` |

### Таймеры

| Вместо стандартного | Использовать из Core | Модуль |
|---------------------|---------------------|--------|
| `TTimer` (для фоновых задач) | `TTimerThread` + `TTimerTask` | `MyTask.pas` |

### HTTP-клиент

| Вместо стандартного | Использовать из Core | Модуль |
|---------------------|---------------------|--------|
| `TNetHTTPClient` напрямую | `TMyHttpClient` | `MyHttpClient.pas` |

### Правила использования Core-модулей

1. **TMyThread** — наследуй от него, а не от `TThread`. Первой строкой в `Execute` вызывай `inherited`. В цикле дёргай `ImAlive`. Завершение: `TMyThread.TerminateAndFree<T>(AThread)`.
2. **TMyTask** — используй вспомогательные функции (`TMyTaskAutoFree`, `TMyTaskNotAutoFree`, `TMyTaskSynchronizedAutoFree`, `TMyTaskSynchronizedNotAutoFree`) вместо прямого создания `TTask.Run`.
3. **TMyCriticalSection** — поддерживает `Enter/Leave`, `LockObj/UnLockObj`, `LockForRead/UnLockAfterRead`, `LockForWrite/UnLockAfterWrite`. Всегда передавай имя функции для диагностики deadlock.
4. **TMyFlag** — используй вместо `Boolean` для межпоточных флагов. Работай через свойство `IsSet` в ответственных местах.
5. **TMyThreadList<T>** — перед чтением: `LockForRead/UnlockAfterRead`, перед записью: `LockForWrite/UnlockAfterWrite`. Обязательно `try..finally`.
6. **TMySaveIniFile** — для быстрого чтения/записи передавай `SavePeriodSec = 0`, для продолжительной работы — `SavePeriodSec = 5`.
7. **TTimerThread + TTimerTask** — для периодических фоновых задач вместо `TTimer` (который работает только в главном потоке GUI).
8. **TMyHttpClient** — обёртка над `TNetHTTPClient`. Не создавай `TNetHTTPClient` напрямую! Используй `CreateHTTPClient` / `CreateHTTPSClient` для создания экземпляра, или классовые методы (`HttpsClientPost`, `HttpsClientGet`, `HttpsClientPatch` и HTTP-аналоги) для быстрых запросов без создания экземпляра. Настройка прокси — через `SetProxy` / `SetProxyAuth` на экземпляре, либо через глобальный callback `TMyHttpClient.OnConfigureClient`.

## Стиль кода

### ОБЯЗАТЕЛЬНО

- Соблюдай стиль окружающего кода (форматирование, именование, структура)
- `{$ENDIF WINDOWS}`, `{$ENDIF DEBUG}` — всегда указывай директиву, не просто `{$ENDIF}`
- `FreeAndNil(Obj)` вместо `Obj.Free`
- `Assigned(Obj)` перед использованием объекта
- `try..finally` для освобождения ресурсов
- `const`, `var` или `out` для всех параметров процедур и функций

### Форматирование строк в логах

- Пробелы вокруг `=` в диагностических сообщениях: `'ID = ' + ID.ToString` (не `'ID=' + ID.ToString`)
- Пробел после запятой в перечислениях: `', Caption = '` (не `',Caption='`)

## Архитектура

### Ключевые папки

| Папка | Содержимое |
|-------|------------|
| `Source/Core/` | Ядро: потоки, синхронизация, INI, таймеры, флаги |
| `Source/` | Основные формы и модули приложения |
| `Docs/` | Документация и справочники API |
| `InvestAPI/` | Официальная документация T-Invest API (proto-файлы, описания) |

### Точка входа

- `TTraid.dpr` — главный файл проекта
- `Source/UMainForm.pas` — главная форма приложения ("Кормилец")

## Подход к исправлению ошибок

- Ищи корневую причину, не лечи симптомы
- Изучи существующую архитектуру перед исправлением
- Используй существующие механизмы из `Source/Core/` (критические секции, флаги, паттерны)
- Проверь, нет ли готового решения в коде
- **При анализе ошибок указывай уверенность в предположениях по шкале 1-10**

## Приоритеты

1. **Запрос пользователя — наивысший приоритет**
2. Работающий код важнее идеальной архитектуры
3. Простота важнее универсальности

## ЗАПРЕЩЕНО

- Использовать скрипты (Python, PowerShell, Bash) для логики — только Delphi/Object Pascal
- Использовать стандартные `TThread`, `TCriticalSection`, `TTask.Run`, `TThreadList`, `Boolean` для межпоточных флагов — вместо них Core-модули (см. таблицу выше)
- Использовать `TTimer` для фоновых задач — вместо него `TTimerThread` + `TTimerTask`
- Использовать `TIniFile` / `TMemIniFile` напрямую — вместо них `TMySaveIniFile`
- Использовать `TNetHTTPClient` напрямую — вместо него `TMyHttpClient` из `MyHttpClient.pas`

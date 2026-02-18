# План реализации: Торговый робот MVP ("Кормилец")

## Обзор

Реализация торгового робота на Delphi 11+ (FMX) с модульной архитектурой. Каждый шаг строится на предыдущем, начиная с утилитных модулей и заканчивая интеграцией всех компонентов в главную форму.

## Задачи

- [x] 1. Создать модуль конвертации цен TQuotationHelper
  - [x] 1.1 Создать `Source/UQuotationHelper.pas` с типом `TQuotation` (record: Units: Int64, Nano: Int32) и классом `TQuotationHelper` с методами `FromDouble`, `ToDouble`, `ToJson`, `FromJson`
    - Формула: Units = Trunc(Value), Nano = Round(Frac(Value) * 1e9)
    - Обратно: Value = Units + Nano / 1e9
    - ToJson формирует строку `{"units":"<units>","nano":<nano>}`
    - FromJson парсит TJSONObject в TQuotation
    - _Requirements: 9.1, 9.2, 9.4, 6.6_
  - [ ]* 1.2 Написать property-тест round-trip конвертации Quotation
    - **Property 1: Round-trip конвертации Quotation**
    - Генерировать 100 случайных Double в диапазоне 0..999999 с дробной частью до 9 знаков
    - Проверить: ToDouble(FromDouble(x)) ≈ x (с точностью 1e-9)
    - **Validates: Requirements 9.1, 9.2, 9.3**
  - [ ]* 1.3 Написать unit-тесты для TQuotationHelper
    - Конкретные примеры из API-документации: 250.50, 0.07, 1120.20, 100.00
    - Edge cases: 0.0, отрицательные значения, очень большие числа
    - _Requirements: 9.1, 9.2, 9.4_

- [x] 2. Создать модуль логирования TLogManager
  - [x] 2.1 Создать `Source/ULogManager.pas` с типом `TLogEntry` (record: Timestamp, Level, Message) и классом `TLogManager`
    - Использовать TMyThreadList<TLogEntry> для потокобезопасного хранения
    - Методы: Log, LogInfo, LogError, GetEntries
    - TrimEntries: при превышении FMaxEntries удалять самые старые записи
    - Событие OnLogEntry для уведомления GUI о новых записях
    - _Requirements: 10.1, 10.2, 10.3, 10.4_
  - [ ]* 2.2 Написать property-тест инварианта размера лога
    - **Property 8: Инвариант размера лога**
    - Генерировать случайное количество записей (1..1000), добавлять в лог с MaxEntries=500
    - Проверить: GetEntries.Length <= 500
    - **Validates: Requirements 10.4**
  - [ ]* 2.3 Написать property-тест полноты записей лога
    - **Property 9: Полнота записей лога**
    - Генерировать 100 случайных записей через LogInfo/LogError
    - Проверить: каждая запись имеет непустые Timestamp, Level, Message
    - **Validates: Requirements 10.1, 10.2**

- [x] 3. Создать модуль настроек TSettingsManager
  - [x] 3.1 Создать `Source/USettingsManager.pas` с типом `TAppSettings` (record) и классом `TSettingsManager`
    - Использовать TMySaveIniFile с SavePeriodSec=5 для продолжительной работы
    - Секция [Connection] в INI-файле
    - Методы: Load, Save, GetSettings, SetSettings
    - Защита через TMyCriticalSection
    - _Requirements: 1.1, 1.2, 1.3, 5.4_
  - [ ]* 3.2 Написать property-тест round-trip сериализации настроек
    - **Property 3: Round-trip сериализации настроек**
    - Генерировать 100 случайных TAppSettings (случайные строки для токена/прокси, случайные порты, интервалы 30..120)
    - Проверить: Save → Load → GetSettings = исходные настройки
    - **Validates: Requirements 1.2, 1.3**

- [x] 4. Создать модуль управления ордерами TOrderManager
  - [x] 4.1 Создать `Source/UOrderManager.pas` с типами `TOrderDirection`, `TOrderType`, `TOrderStatus` (enum), `TOrderRecord` (record) и классом `TOrderManager`
    - Использовать TMyThreadList<TOrderRecord> для потокобезопасного хранения
    - TMySaveIniFile с SavePeriodSec=5 для orders.ini
    - Методы: AddOrder, UpdateOrder, DeleteOrder, GetOrder, GetAllOrders, UpdatePrice, UpdateStatus
    - Класс-методы: OrderToIniSection, IniSectionToOrder для сериализации
    - Маппинг статусов API → TOrderStatus (MapApiStatus)
    - _Requirements: 3.4, 3.5, 3.6, 6.3, 6.4, 6.5, 7.2, 12.1, 12.2_
  - [ ]* 4.2 Написать property-тест round-trip сериализации ордеров
    - **Property 2: Round-trip сериализации ордеров в INI**
    - Генерировать 100 случайных TOrderRecord (случайные InstrumentId, Direction, Quantity, OrderType, TargetPrice, Status)
    - Проверить: сериализация → десериализация = исходный объект
    - **Validates: Requirements 12.1, 12.2, 12.3**
  - [ ]* 4.3 Написать property-тест маппинга статусов API
    - **Property 4: Маппинг статусов API → локальных**
    - Перебрать все значения статусов API, проверить корректность маппинга
    - **Validates: Requirements 6.3, 6.4, 6.5, 7.2**
  - [ ]* 4.4 Написать property-тест удаления ордера
    - **Property 5: Удаление ордера уменьшает список**
    - Генерировать 100 случайных списков ордеров, удалять случайный ордер
    - Проверить: длина уменьшилась на 1, удалённый ордер отсутствует
    - **Validates: Requirements 3.4**
  - [ ]* 4.5 Написать property-тест обновления цен
    - **Property 6: Обновление цен по InstrumentId**
    - Генерировать 100 случайных наборов ордеров и обновлений цен
    - Проверить: ордера с совпадающим InstrumentId обновлены, остальные — нет
    - **Validates: Requirements 5.2**

- [x] 5. Checkpoint — убедиться, что все тесты проходят
  - Убедиться, что все тесты проходят, задать вопросы пользователю при необходимости.

- [x] 6. Создать модуль API-клиента TApiClient
  - [x] 6.1 Создать `Source/UApiClient.pas` с классом `TApiClient`
    - Использовать TMyHttpClient.HttpsClientPost для HTTPS-запросов
    - Настройка прокси через TMyHttpClient.OnConfigureClient callback
    - Заголовок Authorization: Bearer <token>
    - Методы: GetAccounts, GetLastPrices, PostOrder, CancelOrder, GetOrders
    - Генерация GUID через TGUID.NewGuid для idempotency-ключей
    - Формирование JSON-запросов с использованием System.JSON
    - Парсинг JSON-ответов
    - Интеграция с TLogManager для логирования запросов/ответов
    - _Requirements: 2.1, 5.1, 6.1, 6.2, 6.6, 7.1, 8.1_
  - [ ]* 6.2 Написать property-тест уникальности idempotency-ключей
    - **Property 7: Уникальность idempotency-ключей**
    - Генерировать 100 пар GUID, проверить что все различны и соответствуют формату GUID
    - **Validates: Requirements 6.2**
  - [ ]* 6.3 Написать unit-тесты для TApiClient
    - Формирование JSON-запроса PostOrder с корректными полями
    - Формирование JSON-запроса GetLastPrices с массивом instrumentId
    - Парсинг ответа GetAccounts
    - Обработка ошибки 40003 (невалидный токен)
    - _Requirements: 2.1, 2.3, 6.1_

- [x] 7. Создать форму настройки ордера TOrderForm
  - [x] 7.1 Создать `Source/UOrderForm.pas` и `Source/UOrderForm.fmx` — модальная форма для создания/редактирования ордера
    - Поля: инструмент (TEdit), направление (TComboBox: Покупка/Продажа), количество лотов (TSpinBox, min=1), тип ордера (TComboBox: Рыночный/Лимитный/По лучшей цене), целевая цена (TEdit, видимость зависит от типа)
    - Валидация: пустой инструмент, количество < 1, пустая цена для лимитных
    - Кнопки "Сохранить" / "Отмена"
    - Режим создания и редактирования (заполнение полей из TOrderRecord)
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

- [x] 8. Собрать главную форму TMainForm
  - [x] 8.1 Обновить `Source/UMainForm.pas` и `Source/UMainForm.fmx` — добавить панель настроек подключения
    - Поля: токен (TEdit с PasswordChar), прокси (хост, порт, логин, пароль), кнопка "Показать токен"
    - Кнопка "Проверить подключение" → вызов TApiClient.GetAccounts в фоновом потоке
    - Выпадающий список счетов (TComboBox)
    - Поле интервала опроса (TSpinBox, 30..120 сек)
    - Кнопка "Сохранить настройки"
    - _Requirements: 1.1, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 5.4_
  - [x] 8.2 Добавить таблицу ордеров и кнопки управления
    - TStringGrid с колонками: Статус, Инструмент, Направление, Кол-во, Целевая цена, Текущая цена, Тип
    - Кнопки: "Добавить", "Удалить", "Активировать" (выставить заявку), "Отменить" (отменить заявку)
    - Двойной клик по строке → открытие TOrderForm для редактирования
    - Подтверждение удаления через MessageDlg
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 6.1, 7.1_
  - [x] 8.3 Добавить панель лога и кнопки Старт/Стоп
    - TMemo для отображения лога (привязка к TLogManager.OnLogEntry через TThread.Synchronize)
    - Кнопки "Старт" / "Стоп" для управления планировщиком
    - Индикатор состояния (TLabel: "Запущен" / "Остановлен")
    - _Requirements: 10.3, 11.1, 11.2, 11.4_

- [x] 9. Интегрировать планировщик и фоновые задачи
  - [x] 9.1 Создать TTimerThread и TTimerTask для опроса цен и синхронизации заявок в TMainForm
    - PricePollTask: вызывает TApiClient.GetLastPrices → обновляет цены через TOrderManager.UpdatePrice → обновляет TStringGrid через TThread.Synchronize
    - OrderSyncTask: вызывает TApiClient.GetOrders → синхронизирует статусы через TOrderManager.UpdateStatus → обновляет TStringGrid через TThread.Synchronize
    - Кнопка "Старт" → FScheduler.Enabled := True
    - Кнопка "Стоп" → FScheduler.Enabled := False
    - Обработка FProgramClosing при закрытии приложения
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 8.1, 8.2, 8.3, 11.1, 11.2, 11.3, 11.5_
  - [x] 9.2 Реализовать выставление и отмену заявок из GUI
    - Кнопка "Активировать": запуск TMyTaskAutoFree → TApiClient.PostOrder → обновление статуса ордера
    - Кнопка "Отменить": запуск TMyTaskAutoFree → TApiClient.CancelOrder → обновление статуса ордера
    - Обновление GUI через TThread.Synchronize
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 7.1, 7.2, 7.3_

- [x] 10. Зарегистрировать все модули в TTraid.dpr
  - Добавить все новые модули (UQuotationHelper, ULogManager, USettingsManager, UOrderManager, UApiClient, UOrderForm) в секцию uses файла TTraid.dpr
  - _Requirements: все_

- [x] 11. Финальный checkpoint — убедиться, что всё работает
  - Убедиться, что все тесты проходят, задать вопросы пользователю при необходимости.

## Примечания

- Задачи, помеченные `*`, являются опциональными и могут быть пропущены для ускорения MVP
- Каждая задача ссылается на конкретные требования для трассируемости
- Checkpoints обеспечивают инкрементальную валидацию
- Property-тесты проверяют универсальные свойства корректности
- Unit-тесты проверяют конкретные примеры и edge cases

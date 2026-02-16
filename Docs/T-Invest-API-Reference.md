# T-Invest API — Справочник команд (JSON/REST)

> Базовый URL: `https://invest-public-api.tinkoff.ru/rest`
>
> Все запросы — `POST` с телом в формате JSON.
>
> Источник: [Официальная документация T-Invest API](https://tinkoff.github.io/investAPI/)

---

## 1. Аутентификация

Токен передаётся в заголовке **каждого** запроса:

```
Authorization: Bearer <ваш_токен>
```

### Виды токенов

| Тип | Описание |
|-----|----------|
| Readonly | Только чтение (портфель, котировки, история) |
| Full-access | Полный доступ, включая торговые операции |
| Sandbox | Работа с песочницей (эмуляция торгов) |

### Получение токена

1. Перейти: https://www.tinkoff.ru/invest/settings/
2. Отключить «Подтверждение сделок кодом»
3. Выпустить токен нужного типа
4. Скопировать и сохранить (показывается один раз)

Срок жизни токена — 3 месяца с даты последнего использования.

### Ошибка невалидного токена

```json
{
  "code": "40003",
  "message": "authentication token is missing or invalid"
}
```

---

## 2. Получение счетов пользователя

### GetAccounts

```
POST /tinkoff.public.invest.api.contract.v1.UsersService/GetAccounts
```

**Запрос:**

```json
{}
```

**Ответ:**

```json
{
  "accounts": [
    {
      "id": "2000000001",
      "type": "ACCOUNT_TYPE_TINKOFF",
      "name": "Брокерский счёт",
      "status": "ACCOUNT_STATUS_OPEN",
      "openedDate": "2020-01-15T00:00:00Z",
      "closedDate": null,
      "accessLevel": "ACCOUNT_ACCESS_LEVEL_FULL_ACCESS"
    }
  ]
}
```

| Значение type | Описание |
|---------------|----------|
| ACCOUNT_TYPE_TINKOFF | Брокерский счёт |
| ACCOUNT_TYPE_TINKOFF_IIS | ИИС |
| ACCOUNT_TYPE_INVEST_BOX | Инвесткопилка |

---

## 3. Торговые заявки (Orders)

### 3.1 Выставление заявки — PostOrder

```
POST /tinkoff.public.invest.api.contract.v1.OrdersService/PostOrder
```

#### 3.1.1 Рыночная заявка на покупку

Исполняется немедленно по лучшей доступной цене. Поле `price` игнорируется.

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "1",
  "direction": "ORDER_DIRECTION_BUY",
  "accountId": "2000000001",
  "orderType": "ORDER_TYPE_MARKET",
  "orderId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

#### 3.1.2 Рыночная заявка на продажу

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "2",
  "direction": "ORDER_DIRECTION_SELL",
  "accountId": "2000000001",
  "orderType": "ORDER_TYPE_MARKET",
  "orderId": "b2c3d4e5-f6a7-8901-bcde-f12345678901"
}
```

#### 3.1.3 Лимитная заявка на покупку

Исполняется, когда цена достигнет указанного уровня. Действует до конца торговой сессии.

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "5",
  "price": {
    "units": "250",
    "nano": 500000000
  },
  "direction": "ORDER_DIRECTION_BUY",
  "accountId": "2000000001",
  "orderType": "ORDER_TYPE_LIMIT",
  "orderId": "c3d4e5f6-a7b8-9012-cdef-123456789012"
}
```

> **Формат цены (Quotation):** `units` — целая часть, `nano` — дробная (9 знаков).
> Пример: цена 250.50 → `{"units": "250", "nano": 500000000}`

#### 3.1.4 Лимитная заявка на продажу

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "5",
  "price": {
    "units": "280",
    "nano": 0
  },
  "direction": "ORDER_DIRECTION_SELL",
  "accountId": "2000000001",
  "orderType": "ORDER_TYPE_LIMIT",
  "orderId": "d4e5f6a7-b8c9-0123-defa-234567890123"
}
```

#### 3.1.5 Заявка по лучшей цене (Best Price)

Исполняется по лучшей цене в стакане на момент выставления.

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "1",
  "direction": "ORDER_DIRECTION_BUY",
  "accountId": "2000000001",
  "orderType": "ORDER_TYPE_BESTPRICE",
  "orderId": "e5f6a7b8-c9d0-1234-efab-345678901234"
}
```

#### Ответ PostOrder (для всех типов)

```json
{
  "orderId": "12345678",
  "executionReportStatus": "EXECUTION_REPORT_STATUS_FILL",
  "lotsRequested": "1",
  "lotsExecuted": "1",
  "initialOrderPrice": {
    "currency": "rub",
    "units": "250",
    "nano": 500000000
  },
  "executedOrderPrice": {
    "currency": "rub",
    "units": "250",
    "nano": 300000000
  },
  "totalOrderAmount": {
    "currency": "rub",
    "units": "250",
    "nano": 800000000
  },
  "initialCommission": {
    "currency": "rub",
    "units": "0",
    "nano": 500000000
  },
  "direction": "ORDER_DIRECTION_BUY",
  "orderType": "ORDER_TYPE_MARKET",
  "instrumentUid": "abc123-def456"
}
```

| Статус | Описание |
|--------|----------|
| EXECUTION_REPORT_STATUS_FILL | Полностью исполнена |
| EXECUTION_REPORT_STATUS_REJECTED | Отклонена |
| EXECUTION_REPORT_STATUS_CANCELLED | Отменена |
| EXECUTION_REPORT_STATUS_NEW | Новая (ожидает исполнения) |
| EXECUTION_REPORT_STATUS_PARTIALLYFILL | Частично исполнена |

#### Важные замечания по заявкам

> **Идемпотентность:** Поле `orderId` в запросе — это ключ идемпотентности, который вы генерируете сами. Если отправить несколько запросов с одним `orderId`, на биржу уйдёт только одна заявка. Однако `orderId` в ответе — это уже биржевой идентификатор заявки (другое значение). Ваш исходный ключ возвращается в поле `orderRequestId` ответа. Для `GetOrderState` и `CancelOrder` используйте `orderId` из ответа (биржевой).

> **Лимит суммы:** Заявки стоимостью свыше 6 млн ₽ (или $100K / €100K) требуют SMS-подтверждения и не могут быть выставлены через API. Разбивайте крупные заявки на части.

> **Опционы:** На данный момент для опционов доступны только лимитные заявки (`ORDER_TYPE_LIMIT`). Рыночные и стоп-заявки для опционов пока не поддерживаются.

> **Облигации (НКД):** При покупке облигаций к стоимости сделки добавляется НКД × количество лотов. При продаже — вычитается. Размер НКД возвращается в поле `aciValue`.

---

### 3.2 Изменение заявки — ReplaceOrder

```
POST /tinkoff.public.invest.api.contract.v1.OrdersService/ReplaceOrder
```

```json
{
  "accountId": "2000000001",
  "orderId": "12345678",
  "idempotencyKey": "f6a7b8c9-d0e1-2345-fabc-456789012345",
  "quantity": "3",
  "price": {
    "units": "260",
    "nano": 0
  },
  "priceType": "PRICE_TYPE_CURRENCY"
}
```

| priceType | Описание |
|-----------|----------|
| PRICE_TYPE_POINT | Цена в пунктах (фьючерсы, облигации) |
| PRICE_TYPE_CURRENCY | Цена в валюте расчётов |

> **Механизм:** `ReplaceOrder` работает как отмена + создание новой заявки. Если отмена невозможна, вернётся ошибка `30059`. Если отмена прошла, но новая заявка не выставилась — вернётся ошибка `PostOrder`.

---

### 3.3 Отмена заявки — CancelOrder

```
POST /tinkoff.public.invest.api.contract.v1.OrdersService/CancelOrder
```

```json
{
  "accountId": "2000000001",
  "orderId": "12345678"
}
```

**Ответ:**

```json
{
  "time": "2025-02-16T10:30:00.123456Z"
}
```

---

### 3.4 Получение списка активных заявок — GetOrders

```
POST /tinkoff.public.invest.api.contract.v1.OrdersService/GetOrders
```

```json
{
  "accountId": "2000000001"
}
```

---

### 3.5 Статус заявки — GetOrderState

```
POST /tinkoff.public.invest.api.contract.v1.OrdersService/GetOrderState
```

```json
{
  "accountId": "2000000001",
  "orderId": "12345678"
}
```

> **Ограничение:** Метод может не возвращать информацию по заявкам старше ~1 суток. Для глубокой истории используйте сервис операций.

---

## 4. Стоп-заявки (Stop Orders)

> **Рекомендация от команды T-Invest API:** Реализуйте логику стоп-заявок на стороне торгового робота (отслеживание цены + выставление обычных заявок), а не через API стоп-ордеров. Это даёт больше контроля и надёжности.

### 4.1 Выставление стоп-заявки — PostStopOrder

```
POST /tinkoff.public.invest.api.contract.v1.StopOrdersService/PostStopOrder
```

#### 4.1.1 Take-Profit (до отмены)

Срабатывает при достижении целевой цены. Продаёт по рыночной цене.

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "1",
  "price": {
    "units": "0",
    "nano": 0
  },
  "stopPrice": {
    "units": "300",
    "nano": 0
  },
  "direction": "STOP_ORDER_DIRECTION_SELL",
  "accountId": "2000000001",
  "expirationtype": "STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_CANCEL",
  "stopOrderType": "STOP_ORDER_TYPE_TAKE_PROFIT"
}
```

> Если `price` = 0, при срабатывании стоп-цены будет выставлена рыночная заявка.
> Если `price` > 0, будет выставлена лимитная заявка по указанной цене.

#### 4.1.2 Take-Profit с лимитной ценой и датой экспирации

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "1",
  "price": {
    "units": "299",
    "nano": 500000000
  },
  "stopPrice": {
    "units": "300",
    "nano": 0
  },
  "direction": "STOP_ORDER_DIRECTION_SELL",
  "accountId": "2000000001",
  "expirationtype": "STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_DATE",
  "stopOrderType": "STOP_ORDER_TYPE_TAKE_PROFIT",
  "expireDate": "2025-03-01T12:00:00Z"
}
```

#### 4.1.3 Stop-Loss (до отмены)

Срабатывает при падении цены до указанного уровня. Продаёт по рынку.

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "1",
  "price": {
    "units": "0",
    "nano": 0
  },
  "stopPrice": {
    "units": "220",
    "nano": 0
  },
  "direction": "STOP_ORDER_DIRECTION_SELL",
  "accountId": "2000000001",
  "expirationtype": "STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_CANCEL",
  "stopOrderType": "STOP_ORDER_TYPE_STOP_LOSS"
}
```

#### 4.1.4 Stop-Loss на покупку (шорт-покрытие)

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "1",
  "price": {
    "units": "0",
    "nano": 0
  },
  "stopPrice": {
    "units": "280",
    "nano": 0
  },
  "direction": "STOP_ORDER_DIRECTION_BUY",
  "accountId": "2000000001",
  "expirationtype": "STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_CANCEL",
  "stopOrderType": "STOP_ORDER_TYPE_STOP_LOSS"
}
```

#### 4.1.5 Stop-Limit заявка

При достижении стоп-цены выставляется лимитная заявка по указанной цене.

```json
{
  "instrumentId": "BBG004730N88",
  "quantity": "2",
  "price": {
    "units": "218",
    "nano": 0
  },
  "stopPrice": {
    "units": "220",
    "nano": 0
  },
  "direction": "STOP_ORDER_DIRECTION_SELL",
  "accountId": "2000000001",
  "expirationtype": "STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_DATE",
  "stopOrderType": "STOP_ORDER_TYPE_STOP_LIMIT",
  "expireDate": "2025-03-15T23:59:59Z"
}
```

#### Ответ PostStopOrder

```json
{
  "stopOrderId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

---

### 4.2 Получение списка стоп-заявок — GetStopOrders

```
POST /tinkoff.public.invest.api.contract.v1.StopOrdersService/GetStopOrders
```

```json
{
  "accountId": "2000000001"
}
```

> **Важно:** Метод возвращает только стоп-заявки, которые ещё не были конвертированы в реальные биржевые поручения. Сработавшие стоп-заявки в списке не отображаются.

---

### 4.3 Отмена стоп-заявки — CancelStopOrder

```
POST /tinkoff.public.invest.api.contract.v1.StopOrdersService/CancelStopOrder
```

```json
{
  "accountId": "2000000001",
  "stopOrderId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Ответ:**

```json
{
  "time": "2025-02-16T10:35:00.654321Z"
}
```

---

## 5. Справочник Enum-значений

### OrderDirection (направление обычной заявки)

| Значение | Код | Описание |
|----------|-----|----------|
| ORDER_DIRECTION_BUY | 1 | Покупка |
| ORDER_DIRECTION_SELL | 2 | Продажа |

### OrderType (тип обычной заявки)

| Значение | Код | Описание |
|----------|-----|----------|
| ORDER_TYPE_LIMIT | 1 | Лимитная |
| ORDER_TYPE_MARKET | 2 | Рыночная |
| ORDER_TYPE_BESTPRICE | 3 | По лучшей цене |

### StopOrderDirection (направление стоп-заявки)

| Значение | Код | Описание |
|----------|-----|----------|
| STOP_ORDER_DIRECTION_BUY | 1 | Покупка |
| STOP_ORDER_DIRECTION_SELL | 2 | Продажа |

### StopOrderType (тип стоп-заявки)

| Значение | Код | Описание |
|----------|-----|----------|
| STOP_ORDER_TYPE_TAKE_PROFIT | 1 | Take-profit |
| STOP_ORDER_TYPE_STOP_LOSS | 2 | Stop-loss |
| STOP_ORDER_TYPE_STOP_LIMIT | 3 | Stop-limit |

### StopOrderExpirationType (срок действия стоп-заявки)

| Значение | Код | Описание |
|----------|-----|----------|
| STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_CANCEL | 1 | До отмены |
| STOP_ORDER_EXPIRATION_TYPE_GOOD_TILL_DATE | 2 | До указанной даты |

---

## 6. Формат цены (Quotation / MoneyValue)

Цены передаются в виде объекта с двумя полями:

```json
{
  "units": "123",
  "nano": 450000000
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| units | string/int64 | Целая часть |
| nano | int32 | Дробная часть (9 знаков, 10^9 = 1.0) |

Примеры:

| Цена | units | nano |
|------|-------|------|
| 250.50 | 250 | 500000000 |
| 0.07 | 0 | 70000000 |
| 1120.20 | 1120 | 200000000 |
| 100.00 | 100 | 0 |

`MoneyValue` дополнительно содержит поле `currency` (ISO-код валюты: `rub`, `usd`, `eur`, `cny` и т.д.).

---

## 7. Идентификация инструментов

| Поле | Описание | Пример |
|------|----------|--------|
| instrumentId | FIGI или instrument_uid | BBG004730N88 |
| figi | (deprecated) FIGI-идентификатор | BBG004730N88 |
| ticker | Тикер (используется для поиска, не для ордеров) | SBER |

> В торговых запросах используйте `instrumentId` с FIGI или UID инструмента.

---

## 8. Лимиты API

| Сервис | Лимит (запросов/мин) |
|--------|---------------------|
| PostOrder, CancelOrder, ReplaceOrder | 100 |
| GetOrders | 60 |
| PostStopOrder, CancelStopOrder, GetStopOrders | 50 |
| GetAccounts, GetInfo, GetUserTariff | 100 |
| GetCandles, GetLastPrices, GetOrderBook | 300 |

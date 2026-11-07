# MoneyTalks

iOS-приложение для учёта личных финансов: счета и наличные, импорт выписок белорусских банков,
категоризация, аналитика с графиками, мультивалютность (BYN, USD, EUR, RUB).

Архитектурный документ: https://claude.ai/artifact/L377kdMDNaY4iuQZ6QdQZ7

## Требования

- Xcode 16+ (проект использует synchronized folders, objectVersion 77)
- iOS 18+

## Структура

```
MoneyTalks.xcodeproj        тонкий app-таргет: только точка входа и ресурсы
MoneyTalks/                 MoneyTalksApp.swift, Assets, Localizable.xcstrings (RU + EN)
Packages/FinanceKit/        весь код приложения, модули SPM
  Domain                    Money, Currency, Account, FinanceTransaction, FinanceCategory, CategoryRule, MerchantNormalizer, протоколы репозиториев
  Persistence               GRDB (SQLite): миграции, записи, репозитории (категории, правила, операции)
  StatementImport           протокол StatementParser, реестр парсеров, CSV, суммы, дедупликация
  BankParsersBY             парсеры белорусских банков (ждут образцов выписок)
  Categorization            движок правил, «всегда так», встроенные правила (мерчанты Беларуси, MCC)
  ExchangeRates             курсы НБ РБ
  Analytics                 итоги и агрегаты
  DesignSystem              форматирование сумм, тема, общие компоненты
  Feature*                  экраны + view model (MVVM на @Observable)
  AppComposition            сборка зависимостей и корневой TabView
```

Зависимости идут только сверху вниз: фичи знают протоколы из `Domain`, но не GRDB и не конкретные банки.

## Сборка и тесты

```bash
# Тесты пакета (быстро, на macOS)
swift test --package-path Packages/FinanceKit

# Сборка приложения
xcodebuild build -project MoneyTalks.xcodeproj -scheme MoneyTalks \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

## Соглашения

- Суммы только через `Money` (Int64 в минимальных единицах), никаких `Double`.
- Расход — отрицательная сумма, доход — положительная.
- Удаление мягкое (`deletedAt`), ключи — UUID: задел под синхронизацию iCloud.
- Типы названы `FinanceTransaction` и `FinanceCategory`, чтобы не конфликтовать с `SwiftUI.Transaction` и `ObjectiveC.Category`.
- Парсер банка пишется только под реальный файл-образец. Образцы обезличиваются и кладутся в
  `Packages/FinanceKit/Tests/BankParsersBYTests/Fixtures/<bank>/` вместе с ожидаемым результатом.
- Строки интерфейса пишутся по-русски и переводятся на английский в `Localizable.xcstrings`.

defmodule Botyaga.Banking.Format do
  @moduledoc """
  Поведение за адаптер на банков формат (виж `Banking.Formats`).

  Всеки формат живее в собствен модул под `Banking.Formats.*` и парсва
  извлечението до еднакъв пакет: `%{format_name, account_iban,
  account_currency, txs}`.
  """

  @doc "Ключ на формата: за регистра и за `bank_accounts.statement_format`."
  @callback key() :: String.t()

  @doc "Име за показване в интерфейса."
  @callback name() :: String.t()

  @doc "Дали съдържанието прилича на този формат (за авто-разпознаване)."
  @callback matches?(String.t()) :: boolean()

  @doc "Парсва съдържанието до пакет с транзакции."
  @callback parse(String.t()) :: map()
end

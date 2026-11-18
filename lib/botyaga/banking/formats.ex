defmodule Botyaga.Banking.Formats do
  @moduledoc """
  Регистър на банковите формати: по един адаптер на формат в `formats/`.

  Редът на `@formats` е редът на авто-разпознаване — първият адаптер,
  чиито `matches?/1` върне true, парсва файла. Нов формат се добавя като
  нов модул с поведение `Banking.Format` и ред в `@formats`.
  """

  alias Botyaga.Banking.Formats.{Camt053, Csv, Mt940, Obb, Postbank, UniCredit}

  @formats [Postbank, UniCredit, Obb, Camt053, Mt940, Csv]

  @doc "Ключовете на форматите в ред на разпознаване."
  def keys, do: Enum.map(@formats, & &1.key())

  @doc "Списък за интерфейса: `[%{key, name}]`."
  def list, do: Enum.map(@formats, &%{key: &1.key(), name: &1.name()})

  @doc "Модул по ключ: `{:ok, модул}` или `:error`."
  def fetch(key) when is_binary(key) do
    case Enum.find(@formats, fn mod -> mod.key() == key end) do
      nil -> :error
      mod -> {:ok, mod}
    end
  end

  def fetch(_), do: :error

  @doc """
  Разпознава и парсва извлечение. `hint` е ключът от банковата сметка
  (`statement_format`); празен или непознат ключ = авто-разпознаване.
  Връща `nil`, когато форматът не е разпознат.
  """
  def detect(content, hint \\ "") do
    trimmed = content |> String.trim() |> String.trim_leading("﻿")

    case fetch(hint) do
      {:ok, mod} -> mod.parse(trimmed)
      :error -> auto_detect(trimmed)
    end
  end

  defp auto_detect(trimmed) do
    case Enum.find(@formats, fn mod -> mod.matches?(trimmed) end) do
      nil -> nil
      mod -> mod.parse(trimmed)
    end
  end
end

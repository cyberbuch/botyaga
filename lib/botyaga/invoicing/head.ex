defmodule Botyaga.Invoicing.Head do
  @moduledoc "Заглавие и редове на фактура: разбор, подразбиране и валидации."

  alias Botyaga.{Params}
  alias Botyaga.Invoicing.Money

  @string_fields ~w(number due_date tax_event_date accounting_month currency currency_rate
                     payment_method notes discount_percent discount_amount vat_exemption_reason
                     vat_article)

  def from_create(params) do
    with {:ok, direction} <- required(params, "direction"),
         {:ok, issue_date} <- required(params, "issue_date") do
      head = %{
        direction: String.trim(direction),
        document_type: default(string(params, "document_type"), "01"),
        number: String.trim(string(params, "number")),
        issue_date: String.trim(issue_date),
        due_date: string(params, "due_date"),
        tax_event_date: default(string(params, "tax_event_date"), String.trim(issue_date)),
        accounting_month: month_of(String.trim(issue_date), string(params, "accounting_month")),
        counterpart_id: Params.integer(params, "counterpart_id") || 0,
        currency: default(string(params, "currency"), "EUR"),
        currency_rate: default(string(params, "currency_rate"), "1"),
        payment_method: string(params, "payment_method"),
        notes: string(params, "notes"),
        discount_percent: default(string(params, "discount_percent"), "0"),
        discount_amount: default(string(params, "discount_amount"), "0"),
        vat_exemption_reason: string(params, "vat_exemption_reason"),
        original_invoice_id: Params.integer(params, "original_invoice_id") || 0,
        location_id: Params.integer(params, "location_id") || 0,
        bank_account_id: Params.integer(params, "bank_account_id") || 0,
        exclude_vat: flag(params, "exclude_vat"),
        is_oss: flag(params, "is_oss"),
        is_margin: flag(params, "is_margin"),
        margin_export: flag(params, "margin_export"),
        oss_country: string(params, "oss_country"),
        vat_article: string(params, "vat_article"),
        customs_statistical: opt_money(params, "customs_statistical"),
        customs_duty: opt_money(params, "customs_duty"),
        customs_vat: opt_money(params, "customs_vat")
      }

      with :ok <- check(head),
           {:ok, lines} <- lines(params, head.document_type) do
        {:ok, head, lines}
      end
    end
  end

  def overlay(head, params) do
    head =
      Enum.reduce(@string_fields, head, fn field, acc ->
        case Params.str(params, field) do
          {:present, value} -> Map.put(acc, String.to_existing_atom(field), value)
          _ -> acc
        end
      end)

    head =
      head
      |> put_int(params, "counterpart_id")
      |> put_int(params, "original_invoice_id")
      |> put_int(params, "location_id")
      |> put_int(params, "bank_account_id")
      |> put_flag(params, "exclude_vat")
      |> put_flag(params, "is_oss")
      |> put_flag(params, "is_margin")
      |> put_flag(params, "margin_export")
      |> put_string(params, "oss_country")

    head =
      Enum.reduce(~w(customs_statistical customs_duty customs_vat), head, fn field, acc ->
        if Map.has_key?(params, field) do
          Map.put(acc, String.to_existing_atom(field), opt_money(params, field))
        else
          acc
        end
      end)

    head = %{
      head
      | direction: String.trim(head.direction),
        number: String.trim(head.number),
        issue_date: String.trim(head.issue_date)
    }

    head = %{
      head
      | document_type:
          if(String.trim(head.document_type) == "",
            do: "01",
            else: String.trim(head.document_type)
          )
    }

    head = %{
      head
      | tax_event_date:
          if(String.trim(head.tax_event_date) == "",
            do: head.issue_date,
            else: head.tax_event_date
          )
    }

    head = %{head | accounting_month: month_of(head.issue_date, head.accounting_month)}

    with :ok <- check(head) do
      case Map.fetch(params, "lines") do
        {:ok, value} ->
          with {:ok, lines} <- parse_lines(value, head.document_type), do: {:ok, head, lines}

        :error ->
          {:ok, head, nil}
      end
    end
  end

  defp put_int(head, params, key) do
    case Params.integer(params, key) do
      nil -> head
      {:error, _} -> head
      value -> Map.put(head, String.to_existing_atom(key), value)
    end
  end

  defp put_string(head, params, key) do
    case Params.str(params, key) do
      {:present, v} -> Map.put(head, String.to_existing_atom(key), v)
      _ -> head
    end
  end

  defp put_flag(head, params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> Map.put(head, String.to_existing_atom(key), flag_value(value))
      :error -> head
    end
  end

  defp flag(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> flag_value(value)
      :error -> 0
    end
  end

  defp flag_value(v) when is_boolean(v), do: if(v, do: 1, else: 0)
  defp flag_value(v) when is_number(v), do: if(v != 0, do: 1, else: 0)

  defp flag_value(v) when is_binary(v),
    do: if(String.trim(v) in ["1", "true", "TRUE"], do: 1, else: 0)

  defp flag_value(_), do: 0

  def check(head) do
    cond do
      head.direction not in ["in", "out"] ->
        {:error, {422, "direction must be 'in' or 'out'"}}

      String.trim(head.issue_date) == "" ->
        {:error, {422, "issue_date е задължително"}}

      head.counterpart_id <= 0 and head.document_type != "07" ->
        {:error, {422, "counterpart_id е задължително"}}

      not Money.valid_for(head.direction, head.document_type) ->
        {:error, {422, "невалиден вид данъчен документ за тази посока (код по ППДДС)"}}

      Money.requires_original(head.document_type) and head.original_invoice_id <= 0 ->
        {:error, {422, "известието трябва да сочи към първоначална фактура"}}

      head.direction == "in" and head.document_type != "09" and String.trim(head.number) == "" ->
        {:error, {422, "номерът на входящия документ е задължителен"}}

      true ->
        check_money_fields(head)
    end
  end

  defp check_money_fields(head) do
    fields = [
      :discount_percent,
      :discount_amount,
      :currency_rate,
      :customs_statistical,
      :customs_duty,
      :customs_vat
    ]

    Enum.reduce_while(fields, :ok, fn field, _acc ->
      value = Map.get(head, field) || ""

      if String.trim(value) != "" and is_nil(Money.cents(value)) do
        {:halt, {:error, {422, "#{field} е невалидна сума"}}}
      else
        {:cont, :ok}
      end
    end)
  end

  def lines(params, doc_type) do
    case Map.fetch(params, "lines") do
      {:ok, value} -> parse_lines(value, doc_type)
      :error -> {:ok, []}
    end
  end

  defp parse_lines(value, _doc_type) when not is_list(value),
    do: {:error, {422, "lines трябва да е масив"}}

  defp parse_lines(value, doc_type) do
    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      if is_map(item) do
        case parse_line(item, doc_type) do
          {:ok, line} -> {:cont, {:ok, acc ++ [line]}}
          {:error, _} = error -> {:halt, error}
        end
      else
        {:halt, {:error, {422, "редът трябва да е обект"}}}
      end
    end)
  end

  defp parse_line(item, doc_type) do
    with {:ok, quantity} <- money_field(item, "quantity"),
         {:ok, unit_price} <- money_field(item, "unit_price"),
         {:ok, net} <- money_field(item, "net_amount"),
         {:ok, vat} <- money_field(item, "vat_amount"),
         {:ok, total} <- money_field(item, "total_amount") do
      {:ok,
       %{
         product_id: Params.integer(item, "product_id") || 0,
         code: string(item, "code"),
         description: string(item, "description"),
         quantity: quantity,
         unit: default(string(item, "unit"), "C62"),
         unit_price: unit_price,
         vat_rate: default(string(item, "vat_rate"), "20"),
         net_amount: Money.amount_for_doc(doc_type, net),
         vat_amount: Money.amount_for_doc(doc_type, vat),
         total_amount: Money.amount_for_doc(doc_type, total)
       }}
    end
  end

  defp money_field(item, key) do
    case Params.str(item, key) do
      {:present, value} ->
        if String.trim(value) == "" do
          {:error, {422, "#{key} е задължително"}}
        else
          if is_nil(Money.cents(value)),
            do: {:error, {422, "#{key} е невалидна сума"}},
            else: {:ok, value}
        end

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp opt_money(params, key) do
    raw = string(params, key)
    trimmed = String.trim(raw)

    if trimmed == "" do
      ""
    else
      case Money.cents(trimmed) do
        nil -> trimmed
        cents -> Money.money(cents)
      end
    end
  end

  def month_of(issue_date, given) do
    given = String.trim(given)

    cond do
      given != "" -> given
      String.length(issue_date) >= 7 -> String.slice(issue_date, 0, 7)
      true -> issue_date
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp string(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end

  defp default(value, fallback) do
    if String.trim(value) == "", do: fallback, else: value
  end
end

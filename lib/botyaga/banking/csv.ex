defmodule Botyaga.Banking.Csv do
  @moduledoc "Общи помощници за суми и дати при банкови извлечения."

  alias Botyaga.Dec

  def norm_money(raw) do
    t = raw |> to_string() |> String.trim() |> String.replace(" ", "")

    if t == "" do
      ""
    else
      t =
        if String.contains?(t, ",") and String.contains?(t, "."),
          do: String.replace(t, ",", ""),
          else: String.replace(t, ",", ".")

      case Dec.parse(t) do
        nil -> ""
        value -> Dec.money(value)
      end
    end
  end

  def flex_date(raw) do
    t = String.trim(raw || "")

    cond do
      String.length(t) >= 10 and
          String.match?(String.slice(t, 0, 10), ~r/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) ->
        String.slice(t, 0, 10)

      true ->
        sep =
          cond do
            String.contains?(t, "/") -> "/"
            String.contains?(t, ".") -> "."
            String.contains?(t, "-") -> "-"
            true -> nil
          end

        if sep do
          parts = String.split(t, sep)

          if length(parts) == 3 do
            {y, m, d} =
              cond do
                String.length(Enum.at(parts, 0)) == 4 ->
                  {Enum.at(parts, 0), Enum.at(parts, 1), Enum.at(parts, 2)}

                String.length(Enum.at(parts, 2)) == 4 ->
                  {Enum.at(parts, 2), Enum.at(parts, 1), Enum.at(parts, 0)}

                true ->
                  {nil, nil, nil}
              end

            if y && String.length(y) == 4 do
              day = d |> String.trim() |> String.slice(0, 2)

              "#{y}-#{m |> String.trim() |> String.pad_leading(2, "0")}-#{day |> String.pad_leading(2, "0")}"
            else
              ""
            end
          else
            ""
          end
        else
          ""
        end
    end
  end
end

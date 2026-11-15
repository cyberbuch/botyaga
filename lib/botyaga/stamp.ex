defmodule Botyaga.Stamp do
  @moduledoc "Формат на времевия отпечатък както в ytbuch: `%Y-%m-%dT%H:%M:%SZ`."

  def to_stamp(nil), do: ""

  def to_stamp(%DateTime{} = dt) do
    "#{p(dt.year)}-#{p(dt.month)}-#{p(dt.day)}T#{p(dt.hour)}:#{p(dt.minute)}:#{p(dt.second)}Z"
  end

  @doc "Текущ момент със секундна точност — `:utc_datetime` в Ecto не приема микросекунди."
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp p(n), do: n |> to_string() |> String.pad_leading(2, "0")
end

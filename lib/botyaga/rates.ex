defmodule Botyaga.Rates do
  @moduledoc "Курсове на ЕЦБ за 1 EUR. Импортът идва във фаза 9; тук е само търсенето."

  import Ecto.Query

  alias Botyaga.Repo
  alias Botyaga.Rates.Rate

  @doc "Курс за валута към 1 EUR към дата (най-близкият по-ранен при липса)."
  def rate(code, date) do
    code = String.upcase(code)

    if code == "EUR" do
      {:ok, {"1", date}}
    else
      case Repo.one(
             from(r in Rate,
               where: r.code == ^code and r.date <= ^date,
               order_by: [desc: r.date],
               select: {r.rate, r.date},
               limit: 1
             )
           ) do
        nil -> {:error, :no_rate}
        {rate, rate_date} -> {:ok, {rate, rate_date}}
      end
    end
  end

  @doc "Кръстосан курс: единици `to` за 1 `from`, през EUR, към дата."
  def cross_rate(from, to, date) do
    with {:ok, {from_rate, from_date}} <- rate(from, date),
         {:ok, {to_rate, _to_date}} <- rate(to, date) do
      from_v = Botyaga.Dec.parse(from_rate) || 0
      to_v = Botyaga.Dec.parse(to_rate) || 0

      if from_v == 0 do
        {:error, :no_rate}
      else
        cross = Botyaga.Dec.div(to_v, from_v)
        {:ok, {Botyaga.Dec.text(cross, 6), from_date}}
      end
    end
  end
end

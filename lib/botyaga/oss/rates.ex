defmodule Botyaga.Oss.Rates do
  @moduledoc """
  ДДС ставки по държави за OSS с аналитични сметки (453401 Германия, 453402 Гърция…).
  Всяка ставка има начална дата; за нова ставка се копира редът с нова дата —
  така се пази историческа база.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Oss.Rate

  def list(company_id) do
    Repo.all(
      from(r in Rate,
        where: r.company_id == ^company_id,
        order_by: [asc: r.country, desc: r.valid_from, asc: r.id]
      )
    )
    |> Enum.map(&json/1)
  end

  def create(company_id, params) do
    with {:ok, country} <- required(params, "country"),
         {:ok, rate} <- required(params, "rate") do
      account_id = account_for(company_id, params)

      {:ok, r} =
        Repo.insert(%Rate{
          company_id: company_id,
          country: String.upcase(country),
          account_id: account_id,
          rate: rate,
          rate_kind: pick(params, "rate_kind", "standard"),
          supply_kind: pick(params, "supply_kind", "goods"),
          valid_from: pick(params, "valid_from", "")
        })

      {:ok, json(r)}
    end
  end

  @doc "Копие на ред с нова начална дата (нова ставка, историята се пази)."
  def copy(company_id, id, params) do
    with {:ok, src} <- fetch(company_id, id) do
      create(company_id, %{
        "country" => src.country,
        "rate" => pick(params, "rate", src.rate),
        "rate_kind" => src.rate_kind,
        "supply_kind" => src.supply_kind,
        "account_id" => src.account_id,
        "valid_from" => pick(params, "valid_from", "")
      })
    end
  end

  def delete(company_id, id) do
    with {:ok, r} <- fetch(company_id, id) do
      Repo.delete!(r)
      {:ok, nil}
    end
  end

  @doc "Ставката/сметката за държава към дата (последната валидна)."
  def resolve(company_id, country, date, rate_kind \\ "standard", supply_kind \\ "goods") do
    q =
      from(r in Rate,
        where:
          r.company_id == ^company_id and r.country == ^country and r.rate_kind == ^rate_kind and
            r.supply_kind == ^supply_kind and r.valid_from <= ^date,
        order_by: [desc: r.valid_from, desc: r.id],
        limit: 1
      )

    Repo.one(q)
  end

  defp account_for(company_id, params) do
    case Params.integer(params, "account_id") do
      nil ->
        number = pick(params, "account_number", "")

        if number == "" do
          0
        else
          case Repo.get_by(Catalog.Account, company_id: company_id, number: number) do
            nil ->
              {:ok, a} =
                Repo.insert(%Catalog.Account{
                  company_id: company_id,
                  number: number,
                  name: "ДДС OSS #{number}"
                })

              a.id

            a ->
              a.id
          end
        end

      id ->
        id
    end
  end

  defp fetch(company_id, id) do
    case Repo.get_by(Rate, id: id, company_id: company_id) do
      nil -> {:error, {404, "ставката не е намерена"}}
      r -> {:ok, r}
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, v} when v != "" -> {:ok, v}
      _ -> {:error, {422, "#{key} е задължително"}}
    end
  end

  defp pick(params, key, default) do
    case Params.str(params, key) do
      {:present, v} -> v
      _ -> default
    end
  end

  defp json(r) do
    acct = Repo.get(Catalog.Account, r.account_id)

    %{
      id: r.id,
      country: r.country,
      account_id: r.account_id,
      account_number: (acct && acct.number) || "",
      rate: r.rate,
      rate_kind: r.rate_kind,
      supply_kind: r.supply_kind,
      valid_from: r.valid_from
    }
  end
end

defmodule Botyaga.Vat.Operations do
  @moduledoc """
  Междинна настройка „ДДС операции“ (като CONTROLISY): всяка фирма има списък с
  операции, които казват как документът се третира по ЗДДС — категория
  (доставчик/клиент), код за колоната в дневника, допълнителен код (VIES,
  чл.163а, марж, ОТУ, OSS), ставка, сметка на контрагента, ДДС сметка и протокол
  по чл.117. Нова фирма получава готовите операции; сметките се превеждат към
  сметкоплана ѝ.
  """

  import Ecto.Query

  alias Botyaga.{Params, Repo}
  alias Botyaga.Vat.Operation

  @purchase_codes %{
    0 => "не влиза",
    1 => "пълен ДК",
    2 => "частичен ДК",
    3 => "без ДДС",
    4 => "без ДК",
    5 => "посредник"
  }
  @sales_codes %{
    0 => "не влиза",
    1 => "20%",
    2 => "9%",
    3 => "0% гл.3",
    4 => "ВОД",
    5 => "чл.21 ал.2",
    6 => "чл.69 ал.2",
    7 => "дистанционни",
    8 => "освободени",
    9 => "посредник",
    10 => "чл.140/146/173"
  }

  def purchase_codes, do: @purchase_codes
  def sales_codes, do: @sales_codes

  def list(company_id) do
    Repo.all(
      from(o in Operation,
        where: o.company_id == ^company_id,
        order_by: [asc: o.category, asc: o.code, asc: o.id]
      )
    )
    |> Enum.map(&json/1)
  end

  def get(company_id, id), do: Repo.get_by(Operation, id: id, company_id: company_id)

  def create(company_id, params) do
    with {:ok, name} <- required(params, "name"),
         {:ok, category} <- category(params),
         :ok <- unique_name(company_id, category, name, 0) do
      attrs = attrs(company_id, params, name, category)
      %Operation{} |> Ecto.Changeset.change(attrs) |> Repo.insert() |> ok()
    end
  end

  def update(%Operation{} = op, params) do
    # Категорията, кодът, допълнителният код и ставката се заключват след записа;
    # редактират се името, сметките и протоколът (както при конкурента).
    name = pick(params, "name", op.name)

    with :ok <- unique_name(op.company_id, op.category, name, op.id) do
      changes = %{
        name: name,
        counterpart_account_id: int(params, "counterpart_account_id", op.counterpart_account_id),
        vat_account_id: int(params, "vat_account_id", op.vat_account_id),
        protocol: pick(params, "protocol", op.protocol)
      }

      op |> Ecto.Changeset.change(changes) |> Repo.update() |> ok()
    end
  end

  def delete(%Operation{} = op), do: Repo.delete(op) |> ok()

  @doc "Първата операция по (категория, код, допълнителен код [, ставка])."
  def resolve(company_id, category, code, additional, rate \\ nil) do
    q =
      from(o in Operation,
        where:
          o.company_id == ^company_id and o.category == ^category and o.code == ^code and
            o.additional == ^additional,
        order_by: [asc: o.id],
        limit: 1
      )

    q = if rate, do: where(q, [o], o.rate == ^rate), else: q
    Repo.one(q)
  end

  @doc "Операцията за фактура по категория, ставка и протокол (за сметките при осчетоводяване)."
  def for_invoice(company_id, inv, rate) do
    category = if inv.direction == "in", do: "purchase", else: "sales"
    proto? = inv.document_type == "09" or String.contains?(inv.vat_article || "", "117")
    code = code_for(category, rate, proto?)

    resolve(company_id, category, code, 0, rate) ||
      resolve(company_id, category, code, additional_for(inv), rate)
  end

  defp code_for("purchase", _rate, true), do: 1
  defp code_for("purchase", rate, _), do: if(rate in ["20", "9"], do: 1, else: 3)
  defp code_for("sales", "20", _), do: 1
  defp code_for("sales", "9", _), do: 2
  defp code_for("sales", _, _), do: 3

  defp additional_for(inv) do
    art = inv.vat_article || ""
    ex = inv.vat_exemption_reason || ""

    cond do
      String.contains?(art, "163а") -> 20
      String.contains?(ex, "163а") -> 20
      true -> 0
    end
  end

  @doc "Как операцията се третира: протокол, VIES/специален режим, колона."
  def treatment(%Operation{} = op) do
    %{
      protocol: op.protocol != "",
      vies: op.additional in [1, 2, 3],
      reverse: op.additional in [20, 21],
      margin: op.additional == 30,
      tour: op.additional in [31, 32],
      oss: op.additional == 33,
      code: op.code,
      additional: op.additional,
      rate: op.rate
    }
  end

  def treatment(nil), do: nil

  ## Готови операции за нова фирма

  def seed(company_id) do
    if Repo.aggregate(from(o in Operation, where: o.company_id == ^company_id), :count, :id) == 0 do
      # 0 = „по роля“ (default_accounts на фирмата); конкретна сметка се задава ръчно.
      Enum.each(defaults(), fn d ->
        {cp, vat} = {0, 0}
        _ = d

        %Operation{}
        |> Ecto.Changeset.change(%{
          company_id: company_id,
          name: d.name,
          category: d.category,
          code: d.code,
          additional: d.additional,
          rate: d.rate,
          counterpart_account_id: cp,
          vat_account_id: vat,
          protocol: d.protocol
        })
        |> Repo.insert!()
      end)
    end

    :ok
  end

  defp defaults do
    p = fn name, code, rate, add, proto ->
      %{
        category: "purchase",
        name: name,
        code: code,
        additional: add,
        rate: rate,
        protocol: proto
      }
    end

    s = fn name, code, rate, add, proto ->
      %{category: "sales", name: name, code: code, additional: add, rate: rate, protocol: proto}
    end

    [
      p.("Не влиза в дневник (покупки)", 0, "0", 0, ""),
      p.("Покупки 20% с пълен ДК", 1, "20", 0, ""),
      p.("Покупки 9% с пълен ДК", 1, "9", 0, ""),
      p.("Покупки 20% с частичен ДК", 2, "20", 0, ""),
      p.("Покупки 9% с частичен ДК", 2, "9", 0, ""),
      p.("Покупки без ДДС", 3, "0", 0, ""),
      p.("Покупки без право на ДК", 4, "0", 0, ""),
      p.("ВОП / получена услуга ЕС (протокол чл.117)", 1, "20", 0, "чл. 117"),
      p.("Получена услуга от трети страни (протокол чл.117)", 1, "20", 0, "чл. 117"),
      p.("Покупка като посредник в тристранна операция", 5, "0", 0, ""),
      p.("Получени доставки по чл.163а, част I", 1, "20", 20, ""),
      p.("Получени доставки по чл.163а, част II", 1, "20", 21, ""),
      p.("Покупка по режим на маржа", 3, "0", 30, ""),
      p.("Покупка на обща туристическа услуга", 3, "0", 31, ""),
      s.("Не влиза в дневник (продажби)", 0, "0", 0, ""),
      s.("Продажби 20%", 1, "20", 0, ""),
      s.("Продажби 9%", 2, "9", 0, ""),
      s.("Продажби 0% по глава трета", 3, "0", 0, ""),
      s.("ВОД", 4, "0", 1, ""),
      s.("Услуги по чл.21, ал.2", 5, "0", 3, ""),
      s.("Доставки по чл.69, ал.2", 6, "0", 0, ""),
      s.("Дистанционни продажби", 7, "0", 0, ""),
      s.("Освободени доставки", 8, "0", 0, ""),
      s.("Доставки от посредник в тристранна операция", 9, "0", 2, ""),
      s.("Доставки по чл.140, 146 и 173", 10, "0", 0, ""),
      s.("Доставки по чл.163а, част I", 1, "20", 20, ""),
      s.("Доставки по чл.163а, част II", 1, "20", 21, ""),
      s.("Продажба по режим на маржа", 1, "0", 30, ""),
      s.("Продажба на обща туристическа услуга", 1, "0", 31, "")
    ]
  end

  ## Вътрешни

  defp attrs(company_id, params, name, category) do
    %{
      company_id: company_id,
      name: name,
      category: category,
      code: int(params, "code", 0),
      additional: int(params, "additional", 0),
      rate: pick(params, "rate", "20"),
      counterpart_account_id: int(params, "counterpart_account_id", 0),
      vat_account_id: int(params, "vat_account_id", 0),
      protocol: pick(params, "protocol", ""),
      oss_country: pick(params, "oss_country", ""),
      oss_rate_kind: pick(params, "oss_rate_kind", ""),
      oss_supply_kind: pick(params, "oss_supply_kind", "")
    }
  end

  defp category(params) do
    case pick(params, "category", "") do
      c when c in ["purchase", "sales"] -> {:ok, c}
      _ -> {:error, {422, "category трябва да е purchase или sales"}}
    end
  end

  defp unique_name(company_id, category, name, exclude_id) do
    q =
      from(o in Operation,
        where:
          o.company_id == ^company_id and o.category == ^category and o.name == ^name and
            o.id != ^exclude_id
      )

    if Repo.exists?(q),
      do: {:error, {422, "вече има операция със същото име за тази категория"}},
      else: :ok
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

  defp int(params, key, default) do
    case Params.integer(params, key) do
      nil -> default
      v -> v
    end
  end

  defp ok({:ok, o}), do: {:ok, json(o)}
  defp ok({:error, cs}), do: {:error, {422, inspect(cs.errors)}}

  defp json(o) do
    %{
      id: o.id,
      name: o.name,
      category: o.category,
      code: o.code,
      additional: o.additional,
      rate: o.rate,
      counterpart_account_id: o.counterpart_account_id,
      vat_account_id: o.vat_account_id,
      protocol: o.protocol,
      oss_country: o.oss_country,
      oss_rate_kind: o.oss_rate_kind,
      oss_supply_kind: o.oss_supply_kind
    }
  end
end

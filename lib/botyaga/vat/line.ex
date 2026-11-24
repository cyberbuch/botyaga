defmodule Botyaga.Vat.Line do
  @moduledoc "Ред в ДДС дневника и клетките на декларацията. Сумите са стотинки."

  alias Botyaga.Invoicing.Money
  alias Botyaga.Vat.{Ex, Fmt}

  @amount_fields ~w(p_no p_fb p_fv p_pb p_pv p_adj p_vop s_tb s_tv s_b20 s_v20 s_vopb s_82
                     s_vopv s_pers s_b9 s_v9 s_ch3 s_vod s_art s_svc s_69 s_ex s_tri)a

  def empty(kind) do
    base = %{
      kind: kind,
      doc_type: "01",
      doc_no: "",
      doc_date: "",
      cp_vat: "",
      cp_name: "",
      goods: "",
      delivery: ""
    }

    Enum.reduce(@amount_fields, base, fn field, acc -> Map.put(acc, field, 0) end)
  end

  def from_totals(kind, base, vat) do
    ln = empty(kind)

    if kind == "sales" do
      rate = if vat == 0, do: "0", else: "20"
      add_sale(ln, base, vat, rate, "")
    else
      add_purch(ln, base, vat)
    end
  end

  def reset_amounts(ln) do
    reset =
      ~w(p_no p_fb p_fv s_tb s_tv s_b20 s_v20 s_vopb s_82 s_vopv s_b9 s_v9 s_ch3 s_vod s_art s_svc s_ex)a

    Enum.reduce(reset, ln, fn field, acc -> Map.put(acc, field, 0) end)
  end

  def add_vop_sale(ln, base, vat) do
    ln
    |> Map.update!(:s_tb, &(&1 + base))
    |> Map.update!(:s_tv, &(&1 + vat))
    |> Map.update!(:s_vopb, &(&1 + base))
    |> Map.update!(:s_vopv, &(&1 + vat))
  end

  def add_sale(ln, base, vat, rate, ex) do
    cond do
      rate == "9" ->
        ln
        |> Map.update!(:s_tb, &(&1 + base))
        |> Map.update!(:s_tv, &(&1 + vat))
        |> Map.update!(:s_b9, &(&1 + base))
        |> Map.update!(:s_v9, &(&1 + vat))

      rate == "0" ->
        ln = Map.update!(ln, :s_tb, &(&1 + base))
        bucket = zero_bucket(ex)
        Map.update!(ln, bucket, &(&1 + base))

      true ->
        ln
        |> Map.update!(:s_tb, &(&1 + base))
        |> Map.update!(:s_tv, &(&1 + vat))
        |> Map.update!(:s_b20, &(&1 + base))
        |> Map.update!(:s_v20, &(&1 + vat))
    end
  end

  def add_purch(ln, base, vat) do
    if vat == 0 do
      Map.update!(ln, :p_no, &(&1 + base))
    else
      ln |> Map.update!(:p_fb, &(&1 + base)) |> Map.update!(:p_fv, &(&1 + vat))
    end
  end

  def apply_credit(ln) do
    if Fmt.is_credit_doc(ln.doc_type) and ln.s_tb >= 0 and ln.p_fb >= 0 and ln.p_no >= 0 do
      Enum.reduce(@amount_fields, ln, fn field, acc -> Map.update!(acc, field, &(-&1)) end)
    else
      ln
    end
  end

  def to_json(ln, id, row) do
    {base, vat} =
      if ln.kind == "purchase" do
        {ln.p_no + ln.p_fb + ln.p_pb, ln.p_fv + ln.p_pv}
      else
        {ln.s_tb, ln.s_tv}
      end

    %{
      id: id,
      row: row,
      document_type: ln.doc_type,
      document_number: ln.doc_no,
      document_date: ln.doc_date,
      counterpart_name: ln.cp_name,
      counterpart_vat_number: ln.cp_vat,
      goods: ln.goods,
      delivery_code: ln.delivery,
      base_no_credit: Money.money(ln.p_no),
      base_full_credit: Money.money(ln.p_fb),
      vat_full_credit: Money.money(ln.p_fv),
      base_partial: Money.money(ln.p_pb),
      vat_partial: Money.money(ln.p_pv),
      annual_adj: Money.money(ln.p_adj),
      vop_base: Money.money(ln.p_vop),
      total_base: Money.money(ln.s_tb),
      total_vat: Money.money(ln.s_tv),
      base_20: Money.money(ln.s_b20),
      vat_20: Money.money(ln.s_v20),
      vop_sales_base: Money.money(ln.s_vopb),
      vop_sales_vat: Money.money(ln.s_vopv),
      base_9: Money.money(ln.s_b9),
      vat_9: Money.money(ln.s_v9),
      base_0: Money.money(ln.s_ch3),
      base_vod: Money.money(ln.s_vod),
      base_art: Money.money(ln.s_art),
      base_services: Money.money(ln.s_svc),
      base_69: Money.money(ln.s_69),
      base_exempt: Money.money(ln.s_ex),
      base_tri: Money.money(ln.s_tri),
      base_82: Money.money(ln.s_82),
      pers_amount: Money.money(ln.s_pers),
      base_amount: Money.money(base),
      vat_amount: Money.money(vat)
    }
  end

  defp zero_bucket(""), do: :s_ex

  defp zero_bucket(code) do
    case code do
      "VATEX-EU-IC" ->
        :s_vod

      "VATEX-EU-Z-173" ->
        :s_art

      "VATEX-EU-S-21" ->
        :s_svc

      _ ->
        case Ex.category(code) do
          "K" -> :s_vod
          c when c in ["G", "Z"] -> :s_ch3
          "O" -> :s_svc
          _ -> :s_ex
        end
    end
  end

  ## Клетки

  def cells do
    %{
      s01: 0,
      s20: 0,
      s11: 0,
      s21: 0,
      s12: 0,
      s22: 0,
      s23: 0,
      s13: 0,
      s24: 0,
      s14: 0,
      s15: 0,
      s16: 0,
      s17: 0,
      s18: 0,
      s19: 0,
      p30: 0,
      p31: 0,
      p41: 0,
      p32: 0,
      p42: 0,
      p43: 0,
      r40: 0,
      r50: 0,
      r60: 0,
      sales_n: 0,
      purch_n: 0,
      m33: "0.00",
      m70: 0,
      m71: 0,
      m80: 0,
      m81: 0,
      m82: 0
    }
  end

  def cells_add(cells, ln) do
    if ln.kind == "sales" do
      cells = Map.update!(cells, :sales_n, &(&1 + 1))

      if Fmt.sales_excluded(ln.doc_type) do
        cells
      else
        cells
        |> Map.update!(:s01, &(&1 + ln.s_tb))
        |> Map.update!(:s20, &(&1 + ln.s_tv))
        |> Map.update!(:s11, &(&1 + ln.s_b20))
        |> Map.update!(:s21, &(&1 + ln.s_v20))
        |> Map.update!(:s12, &(&1 + ln.s_vopb + ln.s_82))
        |> Map.update!(:s22, &(&1 + ln.s_vopv))
        |> Map.update!(:s23, &(&1 + ln.s_pers))
        |> Map.update!(:s13, &(&1 + ln.s_b9))
        |> Map.update!(:s24, &(&1 + ln.s_v9))
        |> Map.update!(:s14, &(&1 + ln.s_ch3))
        |> Map.update!(:s15, &(&1 + ln.s_vod))
        |> Map.update!(:s16, &(&1 + ln.s_art))
        |> Map.update!(:s17, &(&1 + ln.s_svc))
        |> Map.update!(:s18, &(&1 + ln.s_69 + ln.s_tri))
        |> Map.update!(:s19, &(&1 + ln.s_ex))
      end
    else
      cells = Map.update!(cells, :purch_n, &(&1 + 1))

      if Fmt.purch_excluded(ln.doc_type) do
        cells
      else
        cells
        |> Map.update!(:p30, &(&1 + ln.p_no + ln.p_vop))
        |> Map.update!(:p31, &(&1 + ln.p_fb))
        |> Map.update!(:p41, &(&1 + ln.p_fv))
        |> Map.update!(:p32, &(&1 + ln.p_pb))
        |> Map.update!(:p42, &(&1 + ln.p_pv))
        |> Map.update!(:p43, &(&1 + ln.p_adj))
      end
    end
  end

  def cells_finish(cells) do
    # spec: кл. 40 = кл. 41 + кл. 42 × кл. 33 + кл. 43 (частичен данъчен кредит).
    coef = (Money.cents(cells.m33) || 0) / 100
    r40 = cells.p41 + round(cells.p42 * coef) + cells.p43
    diff = cells.s20 - r40

    if diff < 0 do
      %{cells | r40: r40, r50: 0, r60: -diff}
    else
      %{cells | r40: r40, r50: diff, r60: 0}
    end
  end

  def cells_json(c) do
    %{
      "01-01": Money.money(c.s01),
      "01-20": Money.money(c.s20),
      "01-11": Money.money(c.s11),
      "01-21": Money.money(c.s21),
      "01-12": Money.money(c.s12),
      "01-22": Money.money(c.s22),
      "01-23": Money.money(c.s23),
      "01-13": Money.money(c.s13),
      "01-24": Money.money(c.s24),
      "01-14": Money.money(c.s14),
      "01-15": Money.money(c.s15),
      "01-16": Money.money(c.s16),
      "01-17": Money.money(c.s17),
      "01-18": Money.money(c.s18),
      "01-19": Money.money(c.s19),
      "01-30": Money.money(c.p30),
      "01-31": Money.money(c.p31),
      "01-41": Money.money(c.p41),
      "01-32": Money.money(c.p32),
      "01-42": Money.money(c.p42),
      "01-43": Money.money(c.p43),
      "01-33": c.m33,
      "01-40": Money.money(c.r40),
      "01-50": Money.money(c.r50),
      "01-60": Money.money(c.r60),
      "01-70": Money.money(c.m70),
      "01-71": Money.money(c.m71),
      "01-80": Money.money(c.m80),
      "01-81": Money.money(c.m81),
      "01-82": Money.money(c.m82)
    }
  end

  def pack_json(period, period_nap, name, vat, submitter, purchases, sales, cells) do
    %{
      period: period,
      period_nap: period_nap,
      company_name: name,
      company_vat: vat,
      submitter: submitter,
      sales_count: cells.sales_n,
      purchase_count: cells.purch_n,
      purchases: purchases,
      sales: sales,
      cells: cells_json(cells),
      due: Money.money(cells.r50),
      refund: Money.money(cells.r60),
      cell_01: Money.money(cells.s01),
      cell_11: Money.money(cells.s11),
      cell_31: Money.money(cells.s21),
      cell_41: Money.money(cells.p31),
      cell_71: Money.money(cells.p41),
      cell_81: Money.money(cells.r50),
      cell_82: Money.money(cells.r60)
    }
  end
end

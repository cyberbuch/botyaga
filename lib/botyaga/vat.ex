defmodule Botyaga.Vat do
  @moduledoc """
  ДДС дневници и файл за НАП. Източникът е дневникът на активната фирма;
  ставките идват от редовете на фактурата. Ръчен запис без фактура е 20% или без ДДС.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Companies, Invoicing, Repo}
  alias Botyaga.Invoicing.Money
  alias Botyaga.Journal.{Entry, Line}
  alias Botyaga.Vat.{Ex, Files, Fmt, Manual}
  alias Botyaga.Vat.Print, as: VatPrint
  alias Botyaga.Vat.Line, as: VatLine

  def registers(company_id, period_raw) do
    with {:ok, pack} <- pack(company_id, period_raw), do: {:ok, pack.body}
  end

  def export(company_id, period_raw, params) when is_map(params) do
    kind = to_string(params["type"] || "")

    with {:ok, pack} <- pack(company_id, period_raw) do
      case kind do
        "print" -> print_export(pack, params)
        _ -> nap_export(pack, kind)
      end
    end
  end

  defp nap_export(pack, kind) do
    {data, mime, filename} =
      case kind do
        "pokupki" ->
          {pack.pok, "text/plain; charset=windows-1251", "POKUPKI.TXT"}

        k when k in ["prodagbi", "prodajbi"] ->
          {pack.pro, "text/plain; charset=windows-1251", "PRODAGBI.TXT"}

        "vies" ->
          {pack.vies, "text/plain; charset=windows-1251", "VIES_#{pack.period_nap}.TXT"}

        "zip" ->
          {Files.zip3(pack.dek, pack.pok, pack.pro), "application/zip",
           "PPDDS_#{pack.period_nap}.zip"}

        _ ->
          {pack.dek, "text/plain; charset=windows-1251", "DEKLAR.TXT"}
      end

    {:ok, %{data: data, mime: mime, filename: filename}}
  end

  # Печат на дневника (за собственика/проверка): type=print&register=purchases|sales&format=pdf|xlsx|ods
  defp print_export(pack, params) do
    register = VatPrint.register_of(params["register"])
    format = to_string(params["format"] || "pdf") |> String.trim()
    bg = params["bg"] in ["1", 1, true]
    name = "#{VatPrint.slug(register)}-#{pack.period_nap}"

    case format do
      "pdf" ->
        with {:ok, bytes} <- VatPrint.pdf(pack.body, register) do
          {:ok, %{data: bytes, mime: "application/pdf", filename: "#{name}.pdf"}}
        end

      f when f in ["xlsx", "ods"] ->
        with {:ok, bytes, mime} <- VatPrint.sheet(pack.body, register, f, bg) do
          {:ok, %{data: bytes, mime: mime, filename: "#{name}.#{f}"}}
        end

      _ ->
        {:error, {400, "format трябва да е pdf, xlsx или ods"}}
    end
  end

  def manual_save(company_id, period_raw, params) do
    with {:ok, period} <- parse_period(period_raw),
         {:ok, c33} <- coef_field(params, "cell_33"),
         {:ok, c70} <- money_field(params, "cell_70"),
         {:ok, c71} <- money_field(params, "cell_71"),
         {:ok, c80} <- money_field(params, "cell_80"),
         {:ok, c81} <- money_field(params, "cell_81"),
         {:ok, c82} <- money_field(params, "cell_82") do
      attrs = %{
        cell_33: c33,
        cell_70: c70,
        cell_71: c71,
        cell_80: c80,
        cell_81: c81,
        cell_82: c82
      }

      case Repo.get_by(Manual, company_id: company_id, period: period.iso) do
        nil -> Repo.insert!(struct(%Manual{company_id: company_id, period: period.iso}, attrs))
        row -> Repo.update!(Ecto.Changeset.change(row, attrs))
      end

      with {:ok, pack} <- collect(company_id, period), do: {:ok, pack.body}
    end
  end

  def exemptions(search), do: Ex.items(search)

  defp pack(company_id, period_raw) do
    with {:ok, period} <- parse_period(period_raw), do: collect(company_id, period)
  end

  defp parse_period(raw) do
    case Fmt.parse_period(raw) do
      {:ok, period} -> {:ok, period}
      {:error, :empty} -> {:error, {400, "period е задължителен (YYYY-MM)"}}
      {:error, :format} -> {:error, {400, "period трябва да е YYYY-MM или YYYYMM"}}
    end
  end

  defp collect(company_id, period) do
    co = company_info(company_id)

    with :ok <- require_declarant(co) do
      entries =
        Repo.all(
          from(e in Entry, where: e.company_id == ^company_id and e.vat_period == ^period.iso)
        )
        |> Enum.sort_by(&{&1.entry_date, &1.id})

      {cells, purchases, sales, pok, pro, vies_map} =
        Enum.reduce(entries, {VatLine.cells(), [], [], <<>>, <<>>, %{}}, fn entry, acc ->
          case entry.vat_type do
            "both" ->
              acc
              |> register(company_id, co, period, entry, "purchase")
              |> register(company_id, co, period, entry, "sales")

            vt when vt in ["purchase", "sales"] ->
              register(acc, company_id, co, period, entry, vt)

            _ ->
              acc
          end
        end)

      cells = cells |> VatLine.cells_finish() |> load_manual(company_id, period.iso)

      parties =
        vies_map
        |> Enum.filter(fn {_vin, {k3, k4, k5}} -> k3 != 0 or k4 != 0 or k5 != 0 end)
        |> Enum.map(fn {vin, {k3, k4, k5}} -> %{vin: vin, k3: k3, k4: k4, k5: k5} end)
        |> Enum.sort_by(& &1.vin)

      mm = String.slice(period.nap, 4, 2)
      yyyy = String.slice(period.nap, 0, 4)

      vies =
        Files.vies_txt(
          %{
            vat: co.vat,
            name: co.name,
            street: co.street,
            decl_egn: co.decl_egn,
            decl_name: co.decl_name,
            decl_city: co.city,
            decl_post: co.post,
            decl_street: co.street,
            quality: co.quality
          },
          "#{mm}/#{yyyy}",
          parties
        )

      vies_rows =
        Enum.map(parties, fn p ->
          %{
            vat_number: p.vin,
            country: String.slice(p.vin, 0, 2),
            base_vod: Money.money(p.k3),
            base_tri: Money.money(p.k4),
            base_services: Money.money(p.k5),
            total: Money.money(p.k3 + p.k4 + p.k5)
          }
        end)

      dek = Files.deklar(co.vat, co.name, period.nap, co.submitter, cells)

      body =
        VatLine.pack_json(
          period.iso,
          period.nap,
          co.name,
          co.vat,
          co.submitter,
          purchases,
          sales,
          cells
        )
        |> Map.put(:vies, vies_rows)

      {:ok, %{body: body, pok: pok, pro: pro, dek: dek, vies: vies, period_nap: period.nap}}
    end
  end

  # Протоколът по чл. 117 е с `vat_type` "both" — същият запис влиза и в
  # дневника на покупките, и в този на продажбите.
  defp register(acc, company_id, co, period, entry, kind) do
    {cells, purchases, sales, pok, pro, vies_map} = acc
    ln = one_line(company_id, entry, kind)
    ln = fill_goods(ln, co, kind)
    branch = branch_of(co.branch)

    if kind == "purchase" do
      n = cells.purch_n + 1
      cells = VatLine.cells_add(cells, ln)
      row = ln |> VatLine.to_json(entry.id, n) |> Map.put(:branch, branch)

      {cells, purchases ++ [row], sales,
       pok <> Files.pok_line(co.vat, period.nap, co.branch, n, ln), pro, vies_map}
    else
      n = cells.sales_n + 1
      vies_map = accumulate_vies(vies_map, ln)
      cells = VatLine.cells_add(cells, ln)
      row = ln |> VatLine.to_json(entry.id, n) |> Map.put(:branch, branch)

      {cells, purchases, sales ++ [row], pok,
       pro <> Files.pro_line(co.vat, period.nap, co.branch, n, ln), vies_map}
    end
  end

  defp branch_of(raw) do
    t = String.trim(raw || "")
    if t == "", do: "0", else: t
  end

  # „Вид на стоката/услугата“ не трябва да е празно за НАП. При липса на
  # описание се ползва категорията по подразбиране на фирмата (покупки/продажби).
  defp fill_goods(ln, co, kind) do
    if String.trim(ln.goods || "") == "" do
      Map.put(ln, :goods, if(kind == "purchase", do: co.purchase_goods, else: co.sales_goods))
    else
      ln
    end
  end

  defp accumulate_vies(vies_map, ln) do
    case vies_vin(ln.cp_vat) do
      nil ->
        vies_map

      vin ->
        Map.update(vies_map, vin, {ln.s_vod, ln.s_tri, ln.s_svc}, fn {k3, k4, k5} ->
          {k3 + ln.s_vod, k4 + ln.s_tri, k5 + ln.s_svc}
        end)
    end
  end

  defp vies_vin(raw) do
    v = raw |> to_string() |> String.trim() |> String.upcase()
    len = String.length(v)

    cond do
      len < 3 or len > 15 -> nil
      not String.match?(String.slice(v, 0, 2), ~r/^[A-Za-z]{2}$/) -> nil
      String.starts_with?(v, "BG") -> nil
      true -> v
    end
  end

  # Без ЕГН и име на подаващия DEKLAR/VDR са невалидни — по-добре 422, отколкото празно поле.
  defp require_declarant(%{decl_egn: egn, decl_name: name}) do
    if String.trim(egn) != "" and String.trim(name) != "",
      do: :ok,
      else:
        {:error, {422, "подаващият ДДС данните трябва да има ЕГН и име (Настройки на фирмата)"}}
  end

  defp company_info(company_id) do
    company = Companies.get_company(company_id)

    {decl_egn, decl_name, quality} =
      Files.declarant(
        company.vat_submitter,
        company.accountant_egn,
        company.accountant_name,
        company.authorized_person_egn,
        company.authorized_person_name,
        company.manager_egn,
        company.manager_name
      )

    %{
      name: company.name,
      vat: Fmt.with_bg(company.vat_number),
      submitter:
        Files.submitter(
          company.vat_submitter,
          company.accountant_egn,
          company.accountant_name,
          company.authorized_person_egn,
          company.authorized_person_name,
          company.manager_egn,
          company.manager_name
        ),
      branch: company.vat_branch_number || "",
      purchase_goods: Companies.vat_goods_label(company.vat_purchase_goods),
      sales_goods: Companies.vat_goods_label(company.vat_sales_goods),
      street:
        street_of(company.street_name, company.building_number, company.additional_address_detail),
      city: company.city || "",
      post: company.post_code || "",
      decl_egn: decl_egn,
      decl_name: decl_name,
      quality: quality
    }
  end

  defp street_of(street, number, extra) do
    out = String.trim(street || "")
    n = String.trim(number || "")
    out = if n != "", do: if(out == "", do: n, else: out <> " № " <> n), else: out
    e = String.trim(extra || "")
    if e != "", do: if(out == "", do: e, else: out <> ", " <> e), else: out
  end

  defp one_line(company_id, entry, kind) do
    lines = Repo.all(from(l in Line, where: l.entry_id == ^entry.id))
    {total, vat} = sums(lines)

    ln =
      VatLine.from_totals(kind, total - vat, vat)
      |> Map.put(:doc_type, Fmt.doc_type(entry.document_type))
      |> Map.put(:doc_no, entry.document_number)
      |> Map.put(
        :doc_date,
        if(entry.document_date in [nil, ""], do: entry.entry_date, else: entry.document_date)
      )
      |> Map.put(:cp_name, entry.counterpart_name)
      |> Map.put(:goods, entry.description)

    ln =
      cond do
        entry.counterpart_id > 0 ->
          case Repo.get_by(Catalog.Counterpart, id: entry.counterpart_id, company_id: company_id) do
            nil -> ln
            cp -> Map.put(ln, :cp_vat, Fmt.cp_ident(cp.vat_number, cp.eik))
          end

        ln.doc_type == "07" ->
          Map.put(ln, :cp_vat, "999999999999999")

        true ->
          Map.put(ln, :cp_vat, "999999999999999")
      end

    ln = if entry.document_id > 0, do: overlay(company_id, ln, entry.document_id), else: ln
    VatLine.apply_credit(ln)
  end

  defp sums(lines) do
    Enum.reduce(lines, {0, 0}, fn line, {total, vat} ->
      total =
        if line.direction == "debit", do: total + (Money.cents(line.amount) || 0), else: total

      {total, vat + (Money.cents(line.vat_amount) || 0)}
    end)
  end

  defp overlay(company_id, ln, inv_id) do
    case Repo.get_by(Invoicing.Invoice, id: inv_id, company_id: company_id) do
      nil ->
        ln

      inv ->
        ln =
          if inv.issue_date not in [nil, ""], do: Map.put(ln, :doc_date, inv.issue_date), else: ln

        inv_net = Money.cents(inv.net_amount) || 0
        inv_vat = Money.cents(inv.vat_amount) || 0
        c_stat = Money.cents(inv.customs_statistical) || 0
        c_duty = Money.cents(inv.customs_duty) || 0
        c_vat = Money.cents(inv.customs_vat) || 0
        vat_art = inv.vat_article || ""

        cond do
          inv.document_type == "07" and (c_stat > 0 or c_duty > 0 or c_vat > 0) ->
            base = if c_stat + c_duty > 0, do: c_stat + c_duty, else: inv_net
            vat = if c_vat > 0, do: c_vat, else: inv_vat
            ln = VatLine.reset_amounts(ln)
            ln = if ln.cp_vat == "", do: Map.put(ln, :cp_vat, "999999999999999"), else: ln

            ln =
              if ln.goods == "",
                do: Map.put(ln, :goods, "Внос по митническа декларация"),
                else: ln

            VatLine.add_purch(ln, base, vat)

          true ->
            ln =
              if inv.document_type == "09" and String.trim(vat_art) != "" do
                Map.put(ln, :goods, "Протокол по #{String.trim(vat_art)} от ЗДДС")
              else
                ln
              end

            overlay_lines(ln, inv, inv_net, inv_vat)
        end
    end
  end

  # ВОП колони (02-12/22) са за самоначисляване по чл. 82; протокол по чл. 117
  # се описва като дебитно/кредитно известие — в обикновените колони (spec, Прил. 12).
  defp vop_protocol?(inv),
    do:
      inv.direction == "in" and inv.document_type == "09" and
        String.contains?(inv.vat_article || "", "82")

  defp overlay_lines(ln, inv, inv_net, inv_vat) do
    lines = Invoicing.lines_of(inv.id)
    ex = inv.vat_exemption_reason || ""

    if lines == [] do
      if inv.direction == "in" and inv.document_type == "09" do
        ln = VatLine.reset_amounts(ln)

        if ln.kind == "sales" and vop_protocol?(inv),
          do: VatLine.add_vop_sale(ln, inv_net, inv_vat),
          else: VatLine.add_purch(ln, inv_net, inv_vat)
      else
        ln
      end
    else
      ln = VatLine.reset_amounts(ln)

      lines
      |> Enum.with_index()
      |> Enum.reduce(ln, fn {line, index}, acc ->
        acc =
          if index == 0 and line.description not in [nil, ""] and
               (inv.document_type != "09" or String.trim(inv.vat_article || "") == "") do
            Map.put(acc, :goods, line.description)
          else
            acc
          end

        base = Money.cents(line.net_amount) || 0
        vat = Money.cents(line.vat_amount) || 0
        rate = Fmt.rate_kind(line.vat_rate)

        cond do
          acc.kind == "sales" and vop_protocol?(inv) ->
            VatLine.add_vop_sale(acc, base, vat)

          acc.kind == "sales" ->
            VatLine.add_sale(acc, base, vat, rate, ex)

          true ->
            VatLine.add_purch(acc, base, vat)
        end
      end)
    end
  end

  defp load_manual(cells, company_id, period) do
    case Repo.get_by(Manual, company_id: company_id, period: period) do
      nil ->
        cells

      row ->
        %{
          cells
          | m33: if(String.trim(row.cell_33 || "") == "", do: "0.00", else: row.cell_33),
            m70: Money.cents(row.cell_70) || 0,
            m71: Money.cents(row.cell_71) || 0,
            m80: Money.cents(row.cell_80) || 0,
            m81: Money.cents(row.cell_81) || 0,
            m82: Money.cents(row.cell_82) || 0
        }
    end
  end

  defp money_field(params, key) do
    raw = params |> Map.get(key, "") |> to_string() |> String.trim() |> String.replace(",", ".")

    if raw == "" do
      {:ok, "0.00"}
    else
      case Money.cents(raw) do
        nil -> {:error, {422, "#{key} трябва да е сума"}}
        cents -> {:ok, Money.money(cents)}
      end
    end
  end

  defp coef_field(params, key) do
    raw = params |> Map.get(key, "") |> to_string() |> String.trim() |> String.replace(",", ".")

    if raw == "" do
      {:ok, "0.00"}
    else
      case Float.parse(raw) do
        {v, ""} when v >= 0.0 and v <= 1.0 -> {:ok, :erlang.float_to_binary(v, decimals: 2)}
        _ -> {:error, {422, "#{key} трябва да е коефициент между 0 и 1"}}
      end
    end
  end
end

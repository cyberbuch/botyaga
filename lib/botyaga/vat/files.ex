defmodule Botyaga.Vat.Files do
  @moduledoc "DEKLAR.TXT, POKUPKI.TXT, PRODAGBI.TXT, VIES.TXT и ZIP без компресия."

  alias Botyaga.Invoicing.Money
  alias Botyaga.Vat.Fmt

  defp crlf, do: <<13, 10>>

  defp head(vat, period, branch) do
    trimmed = String.trim(branch || "")
    br = if trimmed == "", do: "0", else: trimmed
    Fmt.sym(Fmt.with_bg(vat), 15) <> Fmt.sym(period, 6) <> Fmt.num_str(br, 4)
  end

  defp push_amts(vals), do: Enum.map_join(vals, "", &Fmt.amt/1)

  def pok_line(vat, period, branch, row, ln) do
    head(vat, period, branch) <>
      Fmt.num_str(Integer.to_string(row), 15) <>
      Fmt.sym(ln.doc_type, 2) <>
      Fmt.sym(ln.doc_no, 20) <>
      Fmt.sym(Fmt.nap_date(ln.doc_date), 10) <>
      Fmt.sym(ln.cp_vat, 15) <>
      Fmt.sym(ln.cp_name, 50) <>
      Fmt.sym(ln.goods, 30) <>
      push_amts([ln.p_no, ln.p_fb, ln.p_fv, ln.p_pb, ln.p_pv, ln.p_adj, ln.p_vop]) <>
      Fmt.sym(ln.delivery, 2) <>
      crlf()
  end

  def pro_line(vat, period, branch, row, ln) do
    head(vat, period, branch) <>
      Fmt.num_str(Integer.to_string(row), 15) <>
      Fmt.sym(ln.doc_type, 2) <>
      Fmt.sym(ln.doc_no, 20) <>
      Fmt.sym(Fmt.nap_date(ln.doc_date), 10) <>
      Fmt.sym(ln.cp_vat, 15) <>
      Fmt.sym(ln.cp_name, 50) <>
      Fmt.sym(ln.goods, 30) <>
      push_amts([
        ln.s_tb,
        ln.s_tv,
        ln.s_b20,
        ln.s_v20,
        ln.s_vopb,
        ln.s_82,
        ln.s_vopv,
        ln.s_pers,
        ln.s_b9,
        ln.s_v9,
        ln.s_ch3,
        ln.s_vod,
        ln.s_art,
        ln.s_svc,
        ln.s_69,
        ln.s_ex,
        ln.s_tri
      ]) <>
      Fmt.sym(ln.delivery, 2) <>
      crlf()
  end

  defp person(egn, name) do
    e = String.trim(egn || "")
    n = String.trim(name || "")

    cond do
      e != "" and n != "" -> "#{e}/#{n}"
      n != "" -> n
      true -> e
    end
  end

  # Лицето, подаващо данните в НАП, се избира в настройките на фирмата. Ако
  # за него няма данни, се влиза на първото налично: счетоводител, пълномощник,
  # управител.
  def submitter(
        selector,
        accountant_egn,
        accountant_name,
        auth_egn,
        auth_name,
        manager_egn,
        manager_name
      ) do
    {_, egn, name} =
      pick(selector, [
        {:accountant, accountant_egn, accountant_name},
        {:authorized, auth_egn, auth_name},
        {:manager, manager_egn, manager_name}
      ])

    person(egn, name)
  end

  # Качеството е `A` за упълномощено лице (счетоводителят е пълномощник за ДДС)
  # и `R` за законен представител — управител.
  def declarant(
        selector,
        accountant_egn,
        accountant_name,
        auth_egn,
        auth_name,
        manager_egn,
        manager_name
      ) do
    {role, egn, name} =
      pick(selector, [
        {:accountant, accountant_egn, accountant_name},
        {:authorized, auth_egn, auth_name},
        {:manager, manager_egn, manager_name}
      ])

    {String.trim(egn || ""), String.trim(name || ""), if(role == :manager, do: "R", else: "A")}
  end

  defp pick(selector, people) do
    wanted = String.trim(to_string(selector || ""))

    chosen =
      Enum.find(people, fn {role, egn, name} ->
        Atom.to_string(role) == wanted and present?(egn, name)
      end)

    case chosen do
      nil -> Enum.find(people, fn {_, egn, name} -> present?(egn, name) end) || {:manager, "", ""}
      found -> found
    end
  end

  # spec 00-04 / VDR: и ЕГН, и име са задължителни за подаващия.
  defp present?(egn, name), do: String.trim(egn || "") != "" and String.trim(name || "") != ""

  def deklar(vat, name, period, submitter, c) do
    coef = if String.trim(c.m33) == "", do: "0.00", else: c.m33

    Fmt.sym(Fmt.with_bg(vat), 15) <>
      Fmt.sym(name, 50) <>
      Fmt.sym(period, 6) <>
      Fmt.sym(submitter, 50) <>
      Fmt.num_str(Integer.to_string(c.sales_n), 15) <>
      Fmt.num_str(Integer.to_string(c.purch_n), 15) <>
      push_amts([
        c.s01,
        c.s20,
        c.s11,
        c.s21,
        c.s12,
        c.s22,
        c.s23,
        c.s13,
        c.s24,
        c.s14,
        c.s15,
        c.s16,
        c.s17,
        c.s18,
        c.s19,
        c.p30,
        c.p31,
        c.p41,
        c.p32,
        c.p42,
        c.p43
      ]) <>
      Fmt.sym(coef, 4) <>
      push_amts([c.r40, c.r50, c.r60, c.m70, c.m71, c.m80, c.m81, c.m82]) <>
      crlf()
  end

  defp amt12(c), do: Fmt.num_str(Money.money(c), 12)

  def vies_txt(head, period_mm_yyyy, parties) do
    total = Enum.sum(Enum.map(parties, &(&1.k3 + &1.k4 + &1.k5)))
    vod = Enum.sum(Enum.map(parties, & &1.k3))

    header =
      "VHR" <>
        Fmt.sym(period_mm_yyyy, 7) <>
        Fmt.num_str(Integer.to_string(length(parties)), 5) <>
        crlf() <>
        "VDR" <>
        Fmt.sym(head.decl_egn, 15) <>
        Fmt.sym(head.decl_name, 150) <>
        Fmt.sym(head.decl_city, 50) <>
        Fmt.num_str(head.decl_post, 4) <>
        Fmt.sym(head.decl_street, 150) <>
        Fmt.sym(head.quality, 1) <>
        crlf() <>
        "VTR" <>
        Fmt.sym(Fmt.with_bg(head.vat), 15) <>
        Fmt.sym(head.name, 150) <>
        Fmt.sym(head.street, 200) <>
        crlf() <>
        "TTR" <> amt12(total) <> amt12(vod) <> crlf()

    rows =
      parties
      |> Enum.with_index(1)
      |> Enum.map_join("", fn {p, i} ->
        "VIR" <>
          Fmt.num_str(Integer.to_string(i), 5) <>
          Fmt.sym(p.vin, 15) <>
          amt12(p.k3) <> amt12(p.k4) <> amt12(p.k5) <> Fmt.sym("", 7) <> crlf()
      end)

    header <> rows
  end

  @doc "ZIP без компресия (store), три файла. CRC32 е стандартният IEEE."
  def zip3(deklar, pok, pro) do
    files = [{"DEKLAR.TXT", deklar}, {"POKUPKI.TXT", pok}, {"PRODAGBI.TXT", pro}]

    {out, central, _offset} =
      Enum.reduce(files, {<<>>, <<>>, 0}, fn {name, data}, {out, central, offset} ->
        name_b = name
        crc = :erlang.crc32(data)
        size = byte_size(data)

        local =
          <<0x04034B50::little-32, 20::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name_b)::little-16,
            0::little-16>> <>
            name_b <> data

        entry =
          <<0x02014B50::little-32, 20::little-16, 20::little-16, 0::little-16, 0::little-16,
            0::little-16, 0::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name_b)::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-32, offset::little-32>> <> name_b

        {out <> local, central <> entry, offset + byte_size(local)}
      end)

    cd_off = byte_size(out)
    cd_len = byte_size(central)

    out <>
      central <>
      <<0x06054B50::little-32, 0::little-16, 0::little-16, 3::little-16, 3::little-16,
        cd_len::little-32, cd_off::little-32, 0::little-16>>
  end
end

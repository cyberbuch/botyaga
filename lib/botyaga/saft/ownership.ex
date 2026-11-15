defmodule Botyaga.Saft.Ownership do
  @moduledoc "Ownership: действителни собственици и крайни майки. Порт на `saft_export.rs#ownership`."

  alias Botyaga.Saft.Xml

  def ownership(s) do
    acc = %{names: [], egns: [], latin: [], foreign: []}
    acc = Enum.reduce(owners_of(s), acc, &push_owner/2)

    owners_xml =
      Enum.map_join(acc.names, &Xml.text("BeneficialOwnerNameCyrillicBG", &1)) <>
        Enum.map_join(acc.egns, &Xml.text("BeneficialOwnerEGN", &1)) <>
        Enum.map_join(acc.latin, &Xml.text("BeneficialOwnerNameLatinForeign", &1)) <>
        Enum.map_join(acc.foreign, &Xml.text("BeneficialCountryForeign", &1)) <>
        Enum.map_join(acc.foreign, &Xml.text("BeneficialCountryForeignCode", &1))

    {bg_names, bg_uic, f_cyr, f_lat, f_cc} = parents_of(s)

    parents_xml =
      Enum.map_join(bg_names, &Xml.text("UltimateOwnerNameCyrillicBG", &1)) <>
        Enum.map_join(bg_uic, &Xml.text("UltimateOwnerUICBG", &1)) <>
        Enum.map_join(f_cyr, &Xml.text("UltimateOwnerNameCyrillicForeign", &1)) <>
        Enum.map_join(f_lat, &Xml.text("UltimateOwnerNameLatinForeign", &1)) <>
        Enum.map_join(f_cc, &Xml.text("CountryForeign", &1))

    Xml.open("Ownership") <>
      Xml.text("IsPartOfGroup", group_code(s.company.group)) <>
      owners_xml <>
      parents_xml <>
      Xml.close("Ownership")
  end

  defp owners_of(s), do: Enum.filter(s.owners, &Xml.same_co(&1.company_id, s.company_id))

  defp push_owner(o, acc) do
    cc = Xml.country(o.country)

    if String.trim(o.country || "") == "" or cc == "BG" do
      name = Xml.clip(join_name(o.first_bg, o.last_bg), 70)
      egn = Xml.clip(o.egn, 35)
      acc = if name != "", do: %{acc | names: acc.names ++ [name]}, else: acc
      if egn != "", do: %{acc | egns: acc.egns ++ [egn]}, else: acc
    else
      name = join_name(o.first_lat, o.last_lat)
      name = if name == "", do: join_name(o.first_bg, o.last_bg), else: name
      name = Xml.clip(name, 70)

      if name != "",
        do: %{acc | latin: acc.latin ++ [name], foreign: acc.foreign ++ [cc]},
        else: acc
    end
  end

  defp parents_of(s) do
    init = %{bg_names: [], bg_uic: [], f_cyr: [], f_lat: [], f_cc: [], bg_lat: ""}

    acc =
      s.parents
      |> Enum.filter(&Xml.same_co(&1.company_id, s.company_id))
      |> Enum.reduce(init, &push_parent/2)

    cond do
      acc.bg_names == [] and acc.f_cyr == [] ->
        name = Xml.shown_name(s.company.name, 70)
        {[name], [eik_or0(s.company.eik)], [name], [name], ["BG"]}

      acc.f_cyr == [] ->
        name = hd(acc.bg_names)
        latin = if acc.bg_lat == "", do: name, else: acc.bg_lat
        {acc.bg_names, acc.bg_uic, [name], [latin], ["BG"]}

      acc.bg_names == [] ->
        {[hd(acc.f_cyr)], ["0"], acc.f_cyr, acc.f_lat, acc.f_cc}

      true ->
        {acc.bg_names, acc.bg_uic, acc.f_cyr, acc.f_lat, acc.f_cc}
    end
  end

  defp push_parent(p, acc) do
    cc = Xml.country(p.country)
    name = Xml.clip(p.name_bg, 70)
    latin = or_clip(p.name_lat, 70, name)
    uic = or_clip(p.uic, 35, "0")

    if String.trim(p.country || "") == "" or cc == "BG" do
      if name == "" do
        acc
      else
        bg_lat = if acc.bg_lat == "", do: latin, else: acc.bg_lat
        %{acc | bg_names: acc.bg_names ++ [name], bg_uic: acc.bg_uic ++ [uic], bg_lat: bg_lat}
      end
    else
      %{
        acc
        | f_cyr: acc.f_cyr ++ [if(name == "", do: latin, else: name)],
          f_lat: acc.f_lat ++ [latin],
          f_cc: acc.f_cc ++ [cc]
      }
    end
  end

  defp join_name(first, last),
    do: "#{String.trim(first || "")} #{String.trim(last || "")}" |> String.trim()

  defp group_code(raw) do
    t = String.trim(raw || "")
    if t in ["1", "2", "3", "4", "5"], do: t, else: "1"
  end

  defp eik_or0(eik), do: or_clip(eik, 35, "0")

  defp or_clip(value, n, fallback) do
    c = Xml.clip(value, n)
    if c == "", do: fallback, else: c
  end
end

defmodule Botyaga.Catalog.Cn8 do
  @moduledoc """
  Комбинирана номенклатура КН8 (NC8_TARIC от SAF-T BG V1.0.1): търсене по код,
  описание и митнически синоними, плюс локални предложения за мерна единица и
  вид запас. AI класификацията (Mistral) идва във фаза 9.
  """

  @data_path "priv/catalog/cn8.json"
  @product_types ~w(10 20 30 40 50)

  def catalog do
    case :persistent_term.get(:botyaga_cn8, nil) do
      nil -> load()
      data -> data
    end
  end

  defp load do
    raw =
      @data_path
      |> then(&Application.app_dir(:botyaga, &1))
      |> File.read!()
      |> Jason.decode!()

    {entries, by_code} = build(raw)
    data = %{entries: entries, by_code: by_code}
    :persistent_term.put(:botyaga_cn8, data)
    data
  end

  defp build(raw) do
    {entries, by_code, _stack, _prev} =
      Enum.reduce(raw["items"] || [], {[], %{}, [], ""}, fn line,
                                                            {entries, by_code, stack, prev_hd} ->
        case String.split(line, "|", parts: 4) do
          [code, hd, lvl, desc] ->
            code = String.trim(code)
            hd = String.trim(hd)
            lvl = parse_level(lvl)
            desc = String.trim(desc)

            if code == "" do
              {entries, by_code, stack, prev_hd}
            else
              stack = if hd != prev_hd, do: [], else: stack
              stack = Enum.drop_while(stack, fn {level, _} -> level >= lvl end)
              clean = desc |> String.trim_leading("-") |> String.trim()

              {chapter, heading_name} =
                case Map.get(raw["headings"] || %{}, hd, ["", ""]) do
                  [ch, name] -> {ch, name}
                  {ch, name} -> {ch, name}
                  _ -> {"", ""}
                end

              chapter_name = Map.get(raw["chapters"] || %{}, chapter, "")
              full_name = build_full_name(clean, heading_name, stack)
              stack = stack ++ [{lvl, clean}]

              haystack =
                Enum.join(
                  [
                    code,
                    String.downcase(clean),
                    String.downcase(full_name),
                    hd,
                    String.downcase(heading_name),
                    String.downcase(chapter_name)
                  ],
                  " "
                )

              entry = %{
                code: code,
                name: desc,
                full_name: full_name,
                heading: hd,
                heading_name: heading_name,
                chapter: chapter,
                chapter_name: chapter_name,
                haystack: haystack
              }

              {[entry | entries], Map.put(by_code, code, length(entries)), stack, hd}
            end

          _ ->
            {entries, by_code, stack, prev_hd}
        end
      end)

    {Enum.reverse(entries), by_code}
  end

  defp parse_level(value) do
    case Integer.parse(String.trim(value)) do
      {level, _} -> level
      :error -> 5
    end
  end

  defp build_full_name(clean, heading_name, stack) do
    low = String.downcase(clean)

    generic =
      low == "други" or String.starts_with?(low, "други,") or String.starts_with?(low, "от ") or
        String.starts_with?(low, "със ") or String.starts_with?(low, "с ") or
        String.starts_with?(low, "без ") or
        String.starts_with?(low, "за ") or String.length(clean) < 18

    if not generic or heading_name == "" do
      clean
    else
      short_hd = heading_name |> String.split(";") |> hd() |> String.trim()

      case List.last(stack) do
        {_level, parent} when parent != "" and parent != clean ->
          "#{short_hd} — #{parent} — #{clean}"

        _ ->
          "#{short_hd} — #{clean}"
      end
    end
  end

  def name_of(code) do
    case Map.fetch(catalog().by_code, String.trim(code || "")) do
      {:ok, index} -> Enum.at(catalog().entries, index).full_name
      :error -> nil
    end
  end

  def entry_json(entry) do
    %{
      code: entry.code,
      name: entry.full_name,
      raw_name: entry.name,
      heading: entry.heading,
      heading_name: entry.heading_name,
      chapter: entry.chapter,
      chapter_name: entry.chapter_name
    }
  end

  def search_noms(query, limit, offset) do
    {total, entries} = rank_entries(query, false, offset + limit)
    items = entries |> Enum.drop(offset) |> Enum.take(limit) |> Enum.map(&entry_json/1)
    {total, items}
  end

  def rank_entries(query, is_service, limit) do
    cat = catalog()
    query = String.trim(query || "")

    cond do
      is_service and query == "" ->
        case Map.fetch(cat.by_code, "00000000") do
          {:ok, index} -> {1, [Enum.at(cat.entries, index)]}
          :error -> {0, []}
        end

      query == "" ->
        {length(cat.entries), Enum.take(cat.entries, limit)}

      true ->
        rank(cat, query, is_service, limit)
    end
  end

  defp rank(cat, query, is_service, limit) do
    query_low = String.downcase(query)
    {stems, boosted} = expand_query(query)

    scored =
      cat.entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        {score(entry, query_low, stems, boosted, is_service), index}
      end)
      |> Enum.filter(fn {score, _index} -> score > 0 end)
      |> Enum.sort_by(fn {score, index} -> {-score, index} end)

    total = length(scored)

    entries =
      scored
      |> Enum.take(limit)
      |> Enum.map(fn {_score, index} -> Enum.at(cat.entries, index) end)

    {total, entries}
  end

  defp score(entry, query_low, stems, boosted, is_service) do
    score =
      cond do
        entry.code == query_low -> 2000
        String.starts_with?(entry.code, query_low) or entry.heading == query_low -> 900
        true -> 0
      end

    score =
      Enum.reduce(boosted, score, fn code, acc ->
        cond do
          entry.code == code -> acc + 650
          entry.heading == code or String.starts_with?(entry.code, code) -> acc + 320
          true -> acc
        end
      end)

    score = if String.contains?(entry.haystack, query_low), do: score + 280, else: score
    full_low = String.downcase(entry.full_name)

    score =
      Enum.reduce(stems, score, fn stem, acc ->
        cond do
          String.length(stem) < 2 -> acc
          String.contains?(full_low, stem) -> acc + 95
          String.contains?(entry.haystack, stem) -> acc + 45
          true -> acc
        end
      end)

    score = if is_service and entry.code == "00000000", do: score + 1200, else: score

    if entry.name |> String.trim_leading("-") |> String.trim() |> String.downcase() == "други" do
      score - 8
    else
      score
    end
  end

  defp expand_query(raw) do
    low = String.downcase(raw)
    words = tokenize(low)

    {words, boosted} =
      Enum.reduce(Botyaga.Catalog.Cn8.Synonyms.list(), {words, []}, fn {triggers, expansion},
                                                                       {words, boosted} ->
        if Enum.any?(triggers, &String.contains?(low, &1)) do
          Enum.reduce(tokenize(expansion), {words, boosted}, fn token, {words, boosted} ->
            if String.match?(token, ~r/^\d{4}$|^\d{8}$/) do
              {words, boosted ++ [token]}
            else
              {words ++ [token], boosted}
            end
          end)
        else
          {words, boosted}
        end
      end)

    stems = words |> Enum.map(&stem/1) |> Enum.uniq()
    {stems, boosted}
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^[:alnum:]]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 2))
  end

  defp stem(word) do
    length = String.length(word)

    if length <= 4 do
      word
    else
      suffixes = ~w(ите ове ата ята ия ен на но ни та те и а о е я)

      Enum.find_value(suffixes, word, fn suffix ->
        suffix_length = String.length(suffix)

        if length > suffix_length + 3 and String.ends_with?(word, suffix) do
          String.slice(word, 0, length - suffix_length)
        end
      end)
    end
  end

  @unit_rules [
    {[" кг", " kg", "килограм"], "KGM"},
    {[" гр.", " грам", " g "], "GRM"},
    {[" тон", " т.", " tne"], "TNE"},
    {[" л.", " литър", " литра", " l ", " ltr", " мл", " ml"], "LTR"},
    {[" кв.м", " м2", " m2", "квадратен метър"], "MTK"},
    {[" куб.м", " м3", " m3", "кубичен метър"], "MTQ"},
    {[" метър", " метра", " л.м", " м."], "MTR"},
    {[" чифт", " двойка"], "PR"},
    {[" комплект", " к-т", " набор", " пакет"], "SET"},
    {[" кутия", " кашон"], "SET"},
    {[" квтч", " kwh", " mwh", "електроенергия"], "KWH"},
    {[" час", " часа", " ч."], "HUR"},
    {[" месец", " месечен", " абонамент"], "MON"},
    {[" ден", " дни", " нощувк"], "DAY"}
  ]

  def guess_saft_unit(text, is_service, current) do
    low = " #{String.downcase(text)} "

    case Enum.find_value(@unit_rules, fn {needles, code} ->
           if Enum.any?(needles, &String.contains?(low, &1)), do: code
         end) do
      nil ->
        cond do
          is_service ->
            if String.trim(current || "") in ["", "H87"], do: "C62", else: String.trim(current)

          String.trim(current || "") not in ["", "C62"] ->
            String.trim(current)

          true ->
            "H87"
        end

      code ->
        code
    end
  end

  def guess_product_type(text, is_service, current) do
    cond do
      is_service -> ""
      String.trim(current || "") in @product_types -> String.trim(current)
      true -> guess_type(String.downcase(text))
    end
  end

  defp guess_type(low) do
    materials = [
      "суровин",
      "материал",
      "цимент",
      "бетон",
      "боя",
      "лак",
      "лепило",
      "дъск",
      "профил",
      "ламарин",
      "тръб",
      "кабел",
      "винт",
      "болт",
      "хартия",
      "тонер",
      "гориво",
      "дизел",
      "бензин",
      "резервна част",
      "консуматив",
      "опаковк",
      "кашон",
      "фолио",
      "препарат"
    ]

    cond do
      Enum.any?(materials, &String.contains?(low, &1)) ->
        "10"

      String.contains?(low, "собствено производство") or String.contains?(low, "готова продукция") ->
        "20"

      String.contains?(low, "незавършено") ->
        "40"

      true ->
        "30"
    end
  end

  def guess_is_service(text, flag) do
    if flag do
      true
    else
      low = String.downcase(text)

      Enum.any?(
        ~w(услуг консултац абонамент наем поддръжк ремонт транспорт доставк куриер хостинг лиценз одит счетовод обучение комисион),
        &String.contains?(low, &1)
      )
    end
  end

  @doc "Локално предложение за КН8, мерна единица и вид запас. AI идва във фаза 9."
  def suggest(params) do
    name = String.trim(params["name"] || "")
    desc = String.trim(params["description"] || "")
    current_unit = String.trim(params["unit"] || "")
    current_type = String.trim(params["product_type"] || "")
    flag = params["is_service"] == true or params["is_service"] == 1
    combined = String.trim("#{name} #{desc}")

    if combined == "" do
      {:error, {422, "въведете име или описание на артикула"}}
    else
      is_service = guess_is_service(combined, flag)
      {_total, candidates} = rank_entries(combined, is_service, 35)
      candidates = with_fallback(candidates, is_service)
      chosen = hd(candidates)
      unit = guess_saft_unit(combined, is_service, current_unit)
      product_type = guess_product_type(combined, is_service, current_type)
      product_type = if is_service, do: "", else: product_type
      unit = if known_unit?(unit), do: unit, else: guess_saft_unit(combined, is_service, "")

      out =
        ([entry_json(chosen)] ++ Enum.map(Enum.take(candidates, 15), &entry_json/1))
        |> Enum.uniq_by(& &1.code)

      {:ok,
       %{
         cn8_code: chosen.code,
         cn8_name: chosen.full_name,
         unit: unit,
         product_type: product_type,
         is_service: is_service,
         source: "catalog",
         candidates: out
       }}
    end
  end

  defp with_fallback([], is_service) do
    code = if is_service, do: "00000000", else: "0"

    case Map.fetch(catalog().by_code, code) do
      {:ok, index} -> [Enum.at(catalog().entries, index)]
      :error -> []
    end
  end

  defp with_fallback(candidates, _is_service), do: candidates

  defp known_unit?(code) do
    (Botyaga.Catalog.catalog()["units"] || [])
    |> Enum.any?(fn line -> hd(String.split(line, "|")) == code end)
  end
end

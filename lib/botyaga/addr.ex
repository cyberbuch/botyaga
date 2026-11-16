defmodule Botyaga.Addr do
  @moduledoc """
  Разбиване на адрес към полетата на SAF-T. С Mistral ключ в настройките на
  фирмата пита Mistral; без ключ дели локално. Порт на `addr.rs`.
  """

  alias Botyaga.{Catalog, Companies, Mistral, Params}
  alias Botyaga.Saft.Xml

  def empty(country) do
    %{
      street_name: "",
      building_number: "",
      address_building: "",
      additional_address_detail: "",
      city: "",
      post_code: "",
      region: "",
      country: country,
      address_type: "",
      ok: false
    }
  end

  def parts_json(p, note) do
    %{
      street_name: p.street_name,
      building_number: p.building_number,
      address_building: p.address_building,
      additional_address_detail: p.additional_address_detail,
      city: p.city,
      post_code: p.post_code,
      region: p.region,
      country: p.country,
      address_type: p.address_type,
      parse_ok: p.ok,
      parse_note: note
    }
  end

  def mistral_key(company_id) when company_id <= 0, do: ""

  def mistral_key(company_id) do
    case Companies.get_company(company_id) do
      nil ->
        ""

      c ->
        case Jason.decode(c.settings || "") do
          {:ok, value} -> value |> Map.get("mistral_api_key", "") |> to_string() |> String.trim()
          _ -> ""
        end
    end
  end

  defp region_of_city(city) do
    want = city |> String.trim() |> String.downcase()

    if want == "" do
      ""
    else
      (Catalog.catalog()["regions"] || [])
      |> Enum.find_value("", fn line ->
        case String.split(line, "|", parts: 2) do
          [code, name] -> if String.downcase(String.trim(name)) == want, do: code
          _ -> nil
        end
      end)
    end
  end

  def split_local(raw, country_hint, city_hint, post_hint) do
    country = or_upcase(country_hint, "BG")
    text = String.trim(raw || "")

    if text == "" or text == "---" do
      empty(country)
    else
      lines =
        text
        |> String.replace("\r", "")
        |> String.split(["\n", ","])
        |> Enum.map(&collapse/1)
        |> Enum.reject(&(&1 == ""))
        |> drop_country()

      {post, city, kept} =
        extract_post_city(lines, String.trim(post_hint || ""), String.trim(city_hint || ""), [])

      street_line = List.first(kept) || ""
      words = street_line |> String.split(~r/\s+/, trim: true) |> drop_street_prefix()
      {words, extra, building} = split_extra_building(words)
      {words, number} = take_number(words)
      street = Enum.join(words, " ")
      city = if city == "", do: Enum.at(kept, 1, ""), else: city

      p = empty(country)
      street_name = clip(street, 70)
      city = clip(city, 35)

      %{
        p
        | street_name: street_name,
          building_number: clip(number, 18),
          address_building: clip(building, 35),
          additional_address_detail: clip(Enum.join(extra, " "), 70),
          city: city,
          post_code: clip(post, 18),
          region: region_of_city(city),
          address_type: if(street_name == "", do: "", else: "StreetAddress"),
          ok: street_name != "" or city != ""
      }
    end
  end

  defp collapse(s), do: s |> String.split(~r/\s+/, trim: true) |> Enum.join(" ")

  defp drop_country([]), do: []

  defp drop_country(lines) do
    last = List.last(lines)
    up = String.upcase(last)

    if up in ["BG", "BULGARIA"] or last == "България" or
         (String.length(up) == 2 and String.match?(up, ~r/^[A-Z]{2}$/)),
       do: Enum.drop(lines, -1),
       else: lines
  end

  defp extract_post_city([], post, city, kept), do: {post, city, Enum.reverse(kept)}

  defp extract_post_city([line | rest], post, city, kept) do
    words = String.split(line, ~r/\s+/, trim: true)

    if post == "" do
      case Enum.find_index(words, &(String.length(&1) == 4 and String.match?(&1, ~r/^[0-9]{4}$/))) do
        nil ->
          extract_post_city(rest, post, city, [line | kept])

        pos ->
          post = Enum.at(words, pos)
          after_words = Enum.drop(words, pos + 1) |> Enum.join(" ")
          city = if city == "" and after_words != "", do: after_words, else: city
          before = Enum.take(words, pos) |> Enum.join(" ")
          kept = if before != "", do: [before | kept], else: kept
          extract_post_city(rest, post, city, kept)
      end
    else
      extract_post_city(rest, post, city, [line | kept])
    end
  end

  defp drop_street_prefix([]), do: []

  defp drop_street_prefix([first | rest]) do
    l = first |> String.trim_trailing(".") |> String.downcase()
    if l in ["ул", "бул", "жк", "улица", "булевард"], do: rest, else: [first | rest]
  end

  defp split_extra_building(words) do
    {kept, extra, building} =
      Enum.reduce(words, {[], [], ""}, fn w, {kept, extra, building} ->
        l = String.downcase(w)

        cond do
          String.starts_with?(l, "ет") or String.starts_with?(l, "вх") or
            String.starts_with?(l, "ап") or String.starts_with?(l, "fl") ->
            {kept, extra ++ [w], building}

          String.starts_with?(l, "бл") or String.starts_with?(l, "блок") ->
            b = w |> String.trim_leading("бл.") |> String.trim_leading("блок") |> String.trim()
            b = if b == "", do: w, else: b
            {kept, extra, b}

          true ->
            {kept ++ [w], extra, building}
        end
      end)

    {kept, extra, building}
  end

  defp take_number([]), do: {[], ""}

  defp take_number(words) do
    last = List.last(words)

    if String.match?(last, ~r/^[0-9]/),
      do: {Enum.drop(words, -1), last},
      else: {words, ""}
  end

  defp from_mistral(value, country) do
    p = empty(country)
    c = value |> clip_field("country", 2) |> String.upcase()
    country = if String.length(c) == 2, do: c, else: country
    region = clip_field(value, "region", 12)
    kind = clip_field(value, "address_type", 32) |> String.downcase()

    address_type =
      case kind do
        "streetaddress" -> "StreetAddress"
        "postaladdress" -> "PostalAddress"
        "billingaddress" -> "BillingAddress"
        "shiptoaddress" -> "ShipToAddress"
        "shipfromaddress" -> "ShipFromAddress"
        _ -> if clip_field(value, "street_name", 70) == "", do: "", else: "StreetAddress"
      end

    street_name = clip_field(value, "street_name", 70)
    city = clip_field(value, "city", 35)

    %{
      p
      | street_name: street_name,
        building_number: clip_field(value, "building_number", 18),
        address_building: clip_field(value, "address_building", 35),
        additional_address_detail: clip_field(value, "additional_address_detail", 70),
        city: city,
        post_code: clip_field(value, "post_code", 18),
        country: country,
        region: Xml.region_code(region, country) || "",
        address_type: address_type,
        ok: street_name != "" or city != ""
    }
  end

  defp clip_field(value, key, max) do
    value |> Map.get(key, "") |> to_string() |> String.trim() |> clip(max)
  end

  defp clip(s, n), do: String.slice(s, 0, n)

  defp ask_mistral(key, raw, country, city, post) do
    regions = (Catalog.catalog()["regions"] || []) |> Enum.join("\n")

    prompt =
      "Split this address into JSON for Bulgarian SAF-T. Keys: street_name, building_number, " <>
        "address_building, additional_address_detail, city, post_code, region, country, address_type. " <>
        "street_name max 70. building_number max 18. region for Bulgaria is a code from the list, else empty. " <>
        "country is ISO alpha-2. address_type is StreetAddress, PostalAddress, BillingAddress, ShipToAddress or ShipFromAddress.\n" <>
        "Regions:\n#{regions}\nCountry code: #{country}\nKnown city: #{city}\nKnown post code: #{post}\nAddress:\n#{raw}"

    body = %{
      model: "mistral-small-2603",
      temperature: 0,
      max_tokens: 512,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You extract structured address fields. Return only JSON."},
        %{role: "user", content: prompt}
      ]
    }

    with {:ok, 200, text} <-
           Mistral.post_json("https://api.mistral.ai/v1/chat/completions", key, body, 30),
         {:ok, obj} <- Mistral.content_json(text) do
      from_mistral(obj, country)
    else
      _ -> nil
    end
  end

  def split(company_id, raw, country, city, post) do
    cc = or_upcase(country, "BG")
    key = mistral_key(company_id)

    if key == "" do
      parts = split_local(raw, cc, city, post)

      note =
        if parts.ok,
          do: "Адресът е разделен локално. Mistral ключ няма в настройките на фирмата.",
          else: "Няма Mistral ключ в настройките на фирмата — адресът не е разделен."

      {:ok, {parts, note}}
    else
      case ask_mistral(key, raw, cc, city, post) do
        %{ok: true} = parts ->
          {:ok, {parts, "Адресът е разделен за SAF-T."}}

        _ ->
          local = split_local(raw, cc, city, post)

          note =
            if local.ok,
              do: "Mistral не раздели адреса. Полетата са от локалното разбиване.",
              else: "VIES ок, но разделянето на адреса не успя."

          {:ok, {local, note}}
      end
    end
  end

  def parse(company_id, params) do
    with {:ok, address} <- required(params, "address") do
      country = params |> str("country") |> or_default("BG")
      city = str(params, "city")
      post = str(params, "post_code")

      with {:ok, {parts, note}} <-
             split(
               company_id,
               String.trim(address),
               String.trim(country),
               String.trim(city),
               String.trim(post)
             ) do
        {:ok, parts_json(parts, note)}
      end
    end
  end

  defp or_upcase(value, fallback) do
    c = value |> String.trim() |> String.upcase()
    if c == "", do: fallback, else: c
  end

  defp or_default(value, fallback), do: if(String.trim(value) == "", do: fallback, else: value)

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

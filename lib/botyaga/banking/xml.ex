defmodule Botyaga.Banking.Xml do
  @moduledoc "Общи XML помощници за банковите формати (виж Banking.Formats)."

  defp xml_unescape(s) do
    s
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  def xml_tag(block, name) do
    close = "</#{name}>"

    case :binary.match(block, close) do
      :nomatch ->
        ""

      {end_pos, _} ->
        head = binary_part(block, 0, end_pos)
        open = "<#{name}"

        case last_index(head, open) do
          nil ->
            ""

          pos ->
            after_open =
              binary_part(head, pos + byte_size(open), byte_size(head) - pos - byte_size(open))

            if String.starts_with?(after_open, " nil=\"true\"") or
                 String.starts_with?(after_open, "/") do
              ""
            else
              case :binary.match(after_open, ">") do
                :nomatch ->
                  ""

                {gt, _} ->
                  after_open
                  |> binary_part(gt + 1, byte_size(after_open) - gt - 1)
                  |> String.trim()
                  |> xml_unescape()
              end
            end
        end
    end
  end

  defp last_index(head, open) do
    case :binary.matches(head, open) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  def xml_attr(block, name, attr) do
    open = "<#{name}"

    case :binary.match(block, open) do
      :nomatch ->
        ""

      {pos, _} ->
        rest = binary_part(block, pos + byte_size(open), byte_size(block) - pos - byte_size(open))

        case :binary.match(rest, ">") do
          :nomatch ->
            ""

          {gt, _} ->
            tag_head = binary_part(rest, 0, gt)
            needle = "#{attr}=\""

            case :binary.match(tag_head, needle) do
              :nomatch ->
                ""

              {apos, _} ->
                val =
                  binary_part(
                    tag_head,
                    apos + byte_size(needle),
                    byte_size(tag_head) - apos - byte_size(needle)
                  )

                case :binary.match(val, "\"") do
                  :nomatch -> ""
                  {i, _} -> binary_part(val, 0, i)
                end
            end
        end
    end
  end

  def xml_blocks(xml, name) do
    open = "<#{name}"
    close = "</#{name}>"
    collect_blocks(xml, open, close, [])
  end

  defp collect_blocks(cur, open, close, acc) do
    case :binary.match(cur, open) do
      :nomatch ->
        Enum.reverse(acc)

      {s, _} ->
        rest = binary_part(cur, s + byte_size(open), byte_size(cur) - s - byte_size(open))

        ok =
          String.starts_with?(rest, ">") or String.starts_with?(rest, " ") or
            String.starts_with?(rest, "\t") or String.starts_with?(rest, "\r") or
            String.starts_with?(rest, "\n")

        if not ok do
          collect_blocks(rest, open, close, acc)
        else
          case :binary.match(rest, ">") do
            :nomatch ->
              Enum.reverse(acc)

            {gt, _} ->
              body = binary_part(rest, gt + 1, byte_size(rest) - gt - 1)

              case :binary.match(body, close) do
                :nomatch ->
                  Enum.reverse(acc)

                {e, _} ->
                  block = binary_part(body, 0, e)

                  remaining =
                    binary_part(
                      body,
                      e + byte_size(close),
                      byte_size(body) - e - byte_size(close)
                    )

                  collect_blocks(remaining, open, close, [block | acc])
              end
          end
        end
    end
  end

  def join_desc(parts) do
    parts |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" — ")
  end

  def first_block(xml, name), do: xml |> xml_blocks(name) |> List.first() || ""
end

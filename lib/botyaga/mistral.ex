defmodule Botyaga.Mistral do
  @moduledoc """
  HTTP клиент към Mistral (chat/OCR). Ключът идва от настройките на фирмата
  (`mistral_api_key`), не от env. Връща суровия текст на отговора.
  """

  def post_json(url, key, body, secs) do
    case Req.post(url,
           json: body,
           headers: [{"authorization", "Bearer #{key}"}],
           receive_timeout: secs * 1000,
           retry: false,
           decode_body: false
         ) do
      {:ok, %{status: status, body: text}} -> {:ok, status, text}
      {:error, reason} -> {:error, Exception.message(reason)}
    end
  end

  @doc "Изважда JSON обекта от съдържанието на chat отговор (първи { до последен })."
  def content_json(text) do
    with {:ok, doc} <- Jason.decode(text),
         content when is_binary(content) <-
           get_in(doc, ["choices", Access.at(0), "message", "content"]),
         {start, _} <- :binary.match(content, "{"),
         {end_pos, _} <- last_match(content, "}") do
      Jason.decode(binary_part(content, start, end_pos - start + 1))
    else
      _ -> :error
    end
  end

  defp last_match(content, needle) do
    case :binary.matches(content, needle) do
      [] -> :nomatch
      matches -> List.last(matches)
    end
  end
end

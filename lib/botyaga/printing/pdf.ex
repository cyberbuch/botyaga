defmodule Botyaga.Printing.Pdf do
  @moduledoc """
  HTML → PDF през Chromium sidecar (Gotenberg). Адресът е `BOTYAGA_PRINT_URL`;
  без него PDF печатът връща 503. DOCX/ODT не зависят от sidecar-а. Шрифтът DejaVu
  се инсталира в образа на sidecar-а (`deploy/print/Dockerfile`).
  """

  def convert(html) do
    url = Application.get_env(:botyaga, :print_url) || ""

    if url == "" do
      {:error,
       {503, "PDF печатът не е конфигуриран — стартирайте print sidecar-а (BOTYAGA_PRINT_URL)"}}
    else
      request(url, html)
    end
  end

  defp request(url, html) do
    Req.post(url <> "/forms/chromium/convert/html",
      form_multipart: [files: {"index.html", html, "text/html"}],
      retry: false,
      receive_timeout: 30_000
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {502, "print sidecar върна #{status}"}}

      {:error, reason} ->
        {:error, {502, "print sidecar: #{Exception.message(reason)}"}}
    end
  end
end

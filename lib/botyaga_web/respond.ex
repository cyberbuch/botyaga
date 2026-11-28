defmodule BotyagaWeb.Respond do
  @moduledoc "Отговори: JSON с `detail` при грешка и статус по контракт."

  import Plug.Conn
  import Phoenix.Controller

  def ok(conn, data, status \\ 200) do
    conn |> put_status(status) |> json(data)
  end

  def no_content(conn), do: send_resp(conn, 204, "")

  @doc "Файл за изтегляне (PDF/DOCX/ODT/XLSX/ODS/XML)."
  def attachment(conn, bytes, mime, filename) do
    filename = to_string(filename)

    # Кавичките и контролни знаци се махат; за не-ASCII имена се добавя RFC 5987 filename*.
    quoted = filename |> String.replace("\"", "'") |> String.replace(["\r", "\n"], "")
    ascii = String.replace(quoted, ~r/[^\x20-\x7E]/, "_")

    header =
      if ascii == quoted do
        "attachment; filename=\"#{quoted}\""
      else
        "attachment; filename=\"#{ascii}\"; filename*=UTF-8''#{URI.encode(quoted)}"
      end

    conn
    |> put_resp_header("content-type", mime)
    |> put_resp_header("content-disposition", header)
    |> send_resp(200, bytes)
  end

  def error(conn, {status, detail}) when is_binary(detail) do
    conn |> put_status(status) |> json(%{detail: detail})
  end

  def error(conn, {:error, {status, detail}}), do: error(conn, {status, detail})

  # защитна клауза: неочакван {:error, atom} не трябва да дава 500
  def error(conn, {:error, _other}), do: error(conn, {422, "невалидна заявка"})

  def error(conn, status, detail) when is_binary(detail), do: error(conn, {status, detail})
end

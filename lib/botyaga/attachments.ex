defmodule Botyaga.Attachments do
  @moduledoc """
  Прикачени файлове към документ. Както CONTROLISY: файлът се пази към документа;
  при изтриване на документа файловете се трият заедно с него. Два файла с едно
  и също име не може да има.
  """

  import Ecto.Query

  alias Botyaga.{Attachment, Repo, Stamp}

  @max 20 * 1024 * 1024

  def list(company_id, doc_type, doc_id) do
    Repo.all(
      from(a in Attachment,
        where: a.company_id == ^company_id and a.doc_type == ^doc_type and a.doc_id == ^doc_id,
        order_by: [asc: a.id]
      )
    )
    |> Enum.map(&meta/1)
  end

  def create(company_id, doc_type, doc_id, %Plug.Upload{} = up) do
    cond do
      up.filename == "" ->
        {:error, {422, "липсва файл"}}

      File.stat!(up.path).size > @max ->
        {:error, {422, "файлът е над 20 MB"}}

      true ->
        data = File.read!(up.path)

        if Enum.any?(list(company_id, doc_type, doc_id), &(&1.filename == up.filename)) do
          {:error, {422, "вече има файл с това име"}}
        else
          {:ok, a} =
            Repo.insert(%Attachment{
              company_id: company_id,
              doc_type: doc_type,
              doc_id: doc_id,
              filename: up.filename,
              content_type: up.content_type || "application/octet-stream",
              size: byte_size(data),
              data: data,
              created_at: Stamp.now()
            })

          {:ok, meta(a)}
        end
    end
  end

  def create(_company_id, _doc_type, _doc_id, _),
    do: {:error, {422, "очаква се файл (multipart)"}}

  def get(company_id, id) do
    case Repo.get_by(Attachment, id: id, company_id: company_id) do
      nil -> {:error, {404, "файлът не е намерен"}}
      a -> {:ok, a}
    end
  end

  def delete(company_id, id) do
    with {:ok, a} <- get(company_id, id) do
      Repo.delete!(a)
      {:ok, nil}
    end
  end

  def delete_for(company_id, doc_type, doc_id) do
    Repo.delete_all(
      from(a in Attachment,
        where: a.company_id == ^company_id and a.doc_type == ^doc_type and a.doc_id == ^doc_id
      )
    )
  end

  defp meta(a) do
    %{
      id: a.id,
      filename: a.filename,
      content_type: a.content_type,
      size: a.size,
      doc_type: a.doc_type,
      doc_id: a.doc_id
    }
  end
end

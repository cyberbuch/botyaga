defmodule Botyaga.AttachmentsTest do
  use Botyaga.DataCase, async: false

  alias Botyaga.{Accounts, Attachments, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("att@baga.example", "АТ", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "АТ ООД", "eik" => "207999000"}, user)
    {:ok, company: company}
  end

  defp upload(name, content) do
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, content)
    %Plug.Upload{path: path, filename: name, content_type: "application/pdf"}
  end

  test "качване, списък, забрана за дублирано име, триене", %{company: company} do
    {:ok, a} = Attachments.create(company.id, "kit", 1, upload("proto.pdf", "PDF"))
    assert a.filename == "proto.pdf"
    assert a.size == 3

    assert length(Attachments.list(company.id, "kit", 1)) == 1

    # дублирано име се отказва
    assert {:error, {422, _}} =
             Attachments.create(company.id, "kit", 1, upload("proto.pdf", "PDF2"))

    {:ok, _} = Attachments.delete(company.id, a.id)
    assert Attachments.list(company.id, "kit", 1) == []
  end

  test "файловете се трият заедно с документа", %{company: company} do
    {:ok, _} = Attachments.create(company.id, "kit", 7, upload("a.pdf", "x"))
    {:ok, _} = Attachments.create(company.id, "kit", 7, upload("b.pdf", "y"))
    assert length(Attachments.list(company.id, "kit", 7)) == 2

    Attachments.delete_for(company.id, "kit", 7)
    assert Attachments.list(company.id, "kit", 7) == []
  end
end

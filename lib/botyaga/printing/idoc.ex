defmodule Botyaga.Printing.Idoc do
  @moduledoc "Печат на приемо-предавателен протокол. Порт на `idoc_print.rs`."

  alias Botyaga.{Companies, Printing, Repo}
  alias Botyaga.Companies.Location
  alias Botyaga.Printing.Load
  alias Botyaga.Stock.InternalDocs

  def build(company_id, id, format) do
    with {:ok, fmt} <- Printing.check_format(format),
         {:ok, doc} <- InternalDocs.show(company_id, id) do
      firm = Companies.get_company(company_id)
      company_name = (firm && firm.name) || ""
      from_name = place(company_id, doc.from_location_id)
      to_name = place(company_id, doc.to_location_id)

      with {:ok, bytes} <- Printing.render(blocks(doc, company_name, from_name, to_name), fmt) do
        filename = "protokol-#{Printing.safe_name(doc.number)}.#{fmt}"
        {:ok, %{bytes: bytes, filename: filename, format: fmt}}
      end
    end
  end

  def blocks(doc, company, from_name, to_name) do
    out = []
    out = if company != "", do: out ++ [{:head, company}], else: out
    out = out ++ [{:head, "ПРИЕМО-ПРЕДАВАТЕЛЕН ПРОТОКОЛ"}]
    out = out ++ [{:line, "№ #{Load.field(doc, :number)} · дата #{Load.field(doc, :doc_date)}"}]
    out = out ++ [{:line, "От обект: #{from_name}"}, {:line, "Към обект: #{to_name}"}]

    header = ["№", "Вид", "Наименование", "К-во", "Себестойност", "Сума"]

    rows =
      doc
      |> Map.get(:lines, [])
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        label = if Load.field(line, :line_kind) == "fixed_asset", do: "ДМА", else: "Артикул"

        [
          Integer.to_string(i + 1),
          label,
          Load.field(line, :description),
          Load.field(line, :quantity),
          Load.field(line, :unit_cost),
          Load.field(line, :amount)
        ]
      end)

    out = out ++ [{:table, [header | rows]}]
    notes = Load.field(doc, :notes)
    out = if notes != "", do: out ++ [{:line, "Забележка: #{notes}"}], else: out

    out ++
      [
        {:line, "Предал: #{Load.field(doc, :handed_by)} _______________"},
        {:line, "Приел: #{Load.field(doc, :received_by)} _______________"}
      ]
  end

  defp place(_company_id, id) when id <= 0, do: ""

  defp place(company_id, id) do
    case Repo.get_by(Location, id: id, company_id: company_id) do
      nil -> ""
      loc -> loc.name || ""
    end
  end
end

defmodule Botyaga.Saft.Moves do
  @moduledoc """
  Стокови движения и наличност за SAF-T при поискване. Няма дневник на стокови
  движения: бройките идват от документите. Порт на `saft_mode.rs` (движенията).
  """

  alias Botyaga.Dec
  alias Botyaga.Saft.{Mode, Xml}

  def movements_xml_range(s, from, to) do
    moves = collect_moves(s, from, to)

    {body, lines, received, issued} =
      Enum.reduce(moves, {"", 0, 0, 0}, fn m, {body, lines, rec, iss} ->
        {lines, rec, iss} =
          Enum.reduce(m.lines, {lines, rec, iss}, fn l, {lines, rec, iss} ->
            q = Dec.or0(l.qty)
            {rec, iss} = if m.mtype in ["10", "20"], do: {rec + q, iss}, else: {rec, iss + q}
            {lines + 1, rec, iss}
          end)

        {body <> move_xml(s, m), lines, rec, iss}
      end)

    Xml.open("MovementOfGoods") <>
      Xml.text("NumberOfMovementLines", Integer.to_string(lines)) <>
      Xml.text("TotalQuantityReceived", Dec.text(received, 4)) <>
      Xml.text("TotalQuantityIssued", Dec.text(issued, 4)) <>
      body <>
      Xml.close("MovementOfGoods")
  end

  defp collect_moves(s, from, to) do
    prod =
      s.products
      |> Enum.filter(&Xml.same_co(&1.company_id, s.company_id))
      |> Map.new(&{&1.id, &1})

    invoice_moves(s, prod, from, to) ++
      production_moves(s, prod, from, to) ++
      material_moves(s, prod, from, to) ++
      idoc_moves(s, prod, from, to)
  end

  defp invoice_moves(s, prod, from, to) do
    Enum.flat_map(s.invoices, fn inv ->
      with true <- Xml.same_co(inv.company_id, s.company_id) and inv.journal_entry_id > 0,
           true <- inv.document_type != "proforma" and String.length(inv.issue_date) >= 10,
           true <- keep?(from, to, inv.issue_date),
           lines when is_list(lines) <- Map.get(s.inv_lines, inv.id) do
        out = inv.direction == "out"

        mlines =
          lines
          |> Enum.with_index()
          |> Enum.flat_map(fn {l, i} ->
            move_line(prod, l.product_id, l.quantity, l.net, &acc_of(s, &1), fn p ->
              %{
                no: i + 1,
                txn: inv.journal_entry_id,
                customer: if(out, do: eik_of(s, inv.counterpart_id), else: "0"),
                supplier: if(out, do: "0", else: eik_of(s, inv.counterpart_id)),
                uom: Mode.unit_code(p.unit),
                subtype: if(out, do: "Продажба", else: "Покупка")
              }
            end)
          end)

        if mlines == [],
          do: [],
          else: [
            %{
              reference: Xml.clip(inv.number, 35),
              date: day(inv.issue_date),
              mtype: if(out, do: "30", else: "10"),
              doc_type: Xml.clip(inv.document_type, 35),
              doc_number: Xml.clip(inv.number, 35),
              lines: mlines
            }
          ]
      else
        _ -> []
      end
    end)
  end

  defp production_moves(s, prod, from, to) do
    Enum.flat_map(s.prod_orders, fn o ->
      if not Xml.same_co(o.company_id, s.company_id) or o.status != "completed" or
           String.length(o.date) < 10 or not keep?(from, to, o.date) do
        []
      else
        txn = if o.journal_id > 0, do: o.journal_id, else: o.id
        out_move = production_output(s, prod, o, txn)

        mlines =
          s.prod_lines
          |> Map.get(o.id, [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {l, i} ->
            move_line(prod, l.product_id, l.quantity, l.amount, &acc_of(s, &1), fn _p ->
              %{
                no: i + 1,
                txn: txn,
                customer: "0",
                supplier: "0",
                uom: Mode.unit_code(l.unit),
                subtype: "Материал за производство"
              }
            end)
          end)

        used =
          if mlines == [],
            do: [],
            else: [
              %{
                reference: Xml.clip(o.number, 35),
                date: day(o.date),
                mtype: "70",
                doc_type: "ПР",
                doc_number: Xml.clip(o.number, 35),
                lines: mlines
              }
            ]

        out_move ++ used
      end
    end)
  end

  defp production_output(s, prod, o, txn) do
    with true <- o.output_product_id > 0,
         p when not is_nil(p) <- Map.get(prod, o.output_product_id),
         acc when acc != "" <- acc_of(s, p.inv_acc),
         q <- Xml.or_text(o.quantity, "0"),
         true <- p.inventory and Dec.or0(q) > 0 do
      [
        %{
          reference: Xml.clip(o.number, 35),
          date: day(o.date),
          mtype: "20",
          doc_type: "ПР",
          doc_number: Xml.clip(o.number, 35),
          lines: [
            %{
              no: 1,
              account: acc,
              txn: txn,
              customer: "0",
              supplier: "0",
              product: Xml.clip(p.code, 70),
              qty: q,
              uom: Mode.unit_code(p.unit),
              value: o.cost,
              subtype: "Производство"
            }
          ]
        }
      ]
    else
      _ -> []
    end
  end

  defp material_moves(s, prod, from, to) do
    Enum.flat_map(s.mat_issues, fn d ->
      if not Xml.same_co(d.company_id, s.company_id) or d.status != "confirmed" or
           String.length(d.date) < 10 or not keep?(from, to, d.date) do
        []
      else
        txn = if d.journal_id > 0, do: d.journal_id, else: d.id

        {mlines, _} =
          s.mat_lines
          |> Map.get(d.id, [])
          |> Enum.reduce({[], 0}, fn l, {acc, count} ->
            case Map.get(prod, l.product_id) do
              nil ->
                {acc, count}

              p ->
                a = acc_of(s, l.inventory_account_id)
                account = if a == "", do: acc_of(s, p.inv_acc), else: a
                q = Xml.or_text(l.quantity, "0")

                if not p.inventory or account == "" or Dec.or0(q) <= 0 do
                  {acc, count}
                else
                  no = if l.line_no > 0, do: l.line_no, else: count + 1

                  line = %{
                    no: no,
                    account: account,
                    txn: txn,
                    customer: "0",
                    supplier: "0",
                    product: Xml.clip(p.code, 70),
                    qty: q,
                    uom: Mode.unit_code(p.unit),
                    value: l.amount,
                    subtype: "Изписване за производство"
                  }

                  {acc ++ [line], count + 1}
                end
            end
          end)

        if mlines == [],
          do: [],
          else: [
            %{
              reference: Xml.clip(d.number, 35),
              date: day(d.date),
              mtype: "70",
              doc_type: "МИ",
              doc_number: Xml.clip(d.number, 35),
              lines: mlines
            }
          ]
      end
    end)
  end

  defp idoc_moves(s, prod, from, to) do
    Enum.flat_map(s.idocs, fn d ->
      if not Xml.same_co(d.company_id, s.company_id) or d.status != "confirmed" or
           String.length(d.date) < 10 or not keep?(from, to, d.date) do
        []
      else
        mlines =
          s.idoc_lines
          |> Map.get(d.id, [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {l, i} ->
            move_line(prod, l.product_id, l.quantity, l.amount, &acc_of(s, &1), fn p ->
              %{
                no: i + 1,
                txn: d.id,
                customer: "0",
                supplier: "0",
                uom: Mode.unit_code(p.unit),
                subtype: "Вътрешен трансфер"
              }
            end)
          end)

        if mlines == [],
          do: [],
          else: [
            %{
              reference: Xml.clip(d.number, 35),
              date: day(d.date),
              mtype: "80",
              doc_type: "ВП",
              doc_number: Xml.clip(d.number, 35),
              lines: mlines
            }
          ]
      end
    end)
  end

  # Общ ред за движение: артикулът трябва да е наличен, със сметка и положително к-во.
  defp move_line(prod, product_id, quantity, value, acc_fun, extra_fun) do
    with p when not is_nil(p) <- Map.get(prod, product_id),
         true <- p.inventory,
         acc when acc != "" <- acc_fun.(p.inv_acc),
         q <- Xml.or_text(quantity, "0"),
         true <- Dec.or0(q) > 0 do
      [
        Map.merge(
          %{account: acc, product: Xml.clip(p.code, 70), qty: q, value: value},
          extra_fun.(p)
        )
      ]
    else
      _ -> []
    end
  end

  defp acc_of(s, id) when id > 0, do: Map.get(s.nra, id, "")
  defp acc_of(_s, _id), do: ""

  defp eik_of(_s, cp) when cp <= 0, do: "0"

  defp eik_of(s, cp) do
    case Enum.find(s.parties, &(&1.id == cp and Xml.same_co(&1.company_id, s.company_id))) do
      nil ->
        "0"

      p ->
        eik = Xml.clip(p.eik, 35)
        if eik == "", do: "0", else: eik
    end
  end

  defp day(d), do: String.slice(d || "", 0, 10)

  defp keep?(from, to, d) do
    dd = day(d)
    (from == "" or dd >= from) and (to == "" or dd <= to)
  end

  defp move_xml(s, m) do
    soft = or_clip(s.company.soft_name, 70, "botyaga")

    lines =
      Enum.map_join(m.lines, fn l ->
        Xml.open("StockMovementLine") <>
          Xml.text("LineNumber", Integer.to_string(l.no)) <>
          Xml.text("AccountID", l.account) <>
          Xml.text("TransactionID", Integer.to_string(l.txn)) <>
          Xml.text("CustomerID", l.customer) <>
          Xml.text("SupplierID", l.supplier) <>
          Xml.text("ProductCode", Xml.clip(l.product, 70)) <>
          Xml.text("Quantity", l.qty) <>
          Xml.text("UnitOfMeasure", l.uom) <>
          Xml.text("UOMToUOMPhysicalStockConversionFactor", "1") <>
          Xml.text("BookValue", Dec.money(l.value)) <>
          Xml.text("MovementSubType", Xml.clip(l.subtype, 35)) <>
          Xml.close("StockMovementLine")
      end)

    Xml.open("StockMovement") <>
      Xml.text("MovementReference", Xml.clip(m.reference, 35)) <>
      Xml.text("MovementDate", m.date) <>
      Xml.text("MovementType", m.mtype) <>
      Xml.text("SourceID", soft) <>
      Xml.text("SystemID", Xml.clip(m.reference, 35)) <>
      Xml.open("DocumentReference") <>
      Xml.text("DocumentType", Xml.clip(m.doc_type, 35)) <>
      Xml.text("DocumentNumber", Xml.clip(m.doc_number, 35)) <>
      Xml.close("DocumentReference") <>
      lines <>
      Xml.close("StockMovement")
  end

  def ondemand_xml(s), do: ondemand_impl(s, nil, nil, "", "")

  def ondemand_xml_ranged(s, open, close, from, to), do: ondemand_impl(s, open, close, from, to)

  defp ondemand_impl(s, open, close, from, to) do
    owner = or_clip(s.company.eik, 35, "0")
    products = Mode.firm_products(s)

    {open_qty, open_val} =
      Enum.reduce(s.openings, {%{}, %{}}, fn o, {q, v} ->
        if o.product_id > 0,
          do:
            {Map.put(q, o.product_id, Xml.or_text(o.qty, "0")), Map.put(v, o.product_id, o.debit)},
          else: {q, v}
      end)

    stock =
      Enum.map_join(products, fn p ->
        if not p.inventory do
          ""
        else
          code = or_clip(p.code, 70, "0")
          u = Mode.unit_code(p.unit)

          {oq, ov} =
            stock_side(open, p.id, Map.get(open_qty, p.id, "0"), Map.get(open_val, p.id, 0))

          {cq, cv} = stock_side(close, p.id, Xml.or_text(p.qty, "0"), p.value)

          Xml.open("PhysicalStockEntry") <>
            Xml.text("WarehouseID", "1") <>
            Xml.text("ProductCode", code) <>
            Xml.text("ProductType", Xml.product_type(p.product_type)) <>
            Xml.text("StockAccountCommodityCode", Xml.cn8_code(p.cn8_code, false)) <>
            Xml.text("OwnerID", owner) <>
            Xml.text("UOMPhysicalStock", u) <>
            Xml.text("UOMToUOMBaseConversionFactor", "1") <>
            Xml.text("UnitPriceBegin", Dec.money(p.cost)) <>
            Xml.text("UnitPriceEnd", Dec.money(p.cost)) <>
            Xml.text("OpeningStockQuantity", oq) <>
            Xml.text("OpeningStockValue", Dec.money(ov)) <>
            Xml.text("ClosingStockQuantity", cq) <>
            Xml.text("ClosingStockValue", Dec.money(cv)) <>
            Xml.close("PhysicalStockEntry")
        end
      end)

    Xml.open("MasterFilesOnDemand") <>
      Mode.moves() <>
      Mode.uom_products(s) <>
      Xml.open("PhysicalStock") <>
      stock <>
      Xml.close("PhysicalStock") <>
      Xml.close("MasterFilesOnDemand") <>
      Xml.open("SourceDocumentsOnDemand") <>
      movements_xml_range(s, from, to) <>
      Xml.close("SourceDocumentsOnDemand")
  end

  defp stock_side(nil, _id, q, v), do: {q, v}
  defp stock_side(map, id, _q, _v), do: Map.get(map, id, {"0", 0})

  defp or_clip(value, n, fallback) do
    c = Xml.clip(value, n)
    if c == "", do: fallback, else: c
  end
end

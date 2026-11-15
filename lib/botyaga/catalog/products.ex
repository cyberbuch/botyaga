defmodule Botyaga.Catalog.Products do
  @moduledoc """
  Стоки и услуги на фирма. Услугата нулира склада; вид `10` попълва
  302/706/601; кодът се генерира числово, ако не е подаден.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Catalog.{Accounts, Cn8, Product}

  @product_types ~w(10 20 30 40 50)
  @auto_write_off_message "за автоматично изписване са нужни сметка на материалите и сметка за изписване"

  def list(company_id) do
    Repo.all(from(p in Product, where: p.company_id == ^company_id, order_by: [asc: p.id]))
  end

  def get(company_id, id) do
    case Repo.get_by(Product, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "стоката не е намерена"}}
      product -> {:ok, product}
    end
  end

  def create(company_id, params) do
    product = %Product{company_id: company_id}

    with {:ok, product} <- apply_params(product, params),
         {:ok, product} <- with_code(product),
         :ok <- check_code(company_id, product.code, 0),
         {:ok, product} <- account_defaults(product),
         :ok <- ensure_accounts(product),
         {:ok, product} <- finish(product) do
      product = %{product | stock_quantity: "0", stock_value: "0"}
      {:ok, Repo.insert!(product)}
    end
  end

  def update(company_id, id, params) do
    with {:ok, current} <- get(company_id, id),
         {:ok, product} <- apply_params(current, params),
         :ok <- check_code(company_id, product.code, Params.id(id)),
         {:ok, product} <- account_defaults(product),
         :ok <- ensure_accounts(product),
         {:ok, product} <- finish(product) do
      product = %{
        product
        | stock_quantity: current.stock_quantity,
          stock_value: current.stock_value
      }

      {:ok, Repo.update!(Ecto.Changeset.change(current, Map.take(product, fields())))}
    end
  end

  def delete(company_id, id) do
    with {:ok, product} <- get(company_id, id) do
      Repo.delete!(product)
      {:ok, nil}
    end
  end

  defp fields do
    [
      :name,
      :code,
      :description,
      :unit,
      :price,
      :cost_price,
      :vat_rate,
      :is_service,
      :is_inventory,
      :inventory_account_id,
      :revenue_account_id,
      :stock_quantity,
      :stock_value,
      :is_active,
      :product_type,
      :cn8_code,
      :cn8_name,
      :expense_account_id,
      :auto_write_off
    ]
  end

  defp apply_params(product, params) do
    strings =
      ~w(name code description unit price cost_price vat_rate product_type cn8_code cn8_name)

    flags = ~w(is_service is_inventory is_active auto_write_off)
    ints = ~w(inventory_account_id revenue_account_id expense_account_id)

    changes =
      Enum.reduce(strings, %{}, fn field, acc ->
        case Params.str(params, field) do
          {:present, value} -> Map.put(acc, String.to_existing_atom(field), value)
          {:error, message} -> throw({:error, {422, message}})
          :absent -> acc
        end
      end)

    changes =
      Enum.reduce(flags ++ ints, changes, fn field, acc ->
        value =
          if field in flags, do: Params.flag(params, field), else: Params.integer(params, field)

        case value do
          nil -> acc
          {:error, message} -> throw({:error, {422, message}})
          value -> Map.put(acc, String.to_existing_atom(field), value)
        end
      end)

    product = Ecto.Changeset.change(product, changes) |> Ecto.Changeset.apply_changes()

    if String.trim(product.name || "") == "" do
      {:error, {422, "name е задължително"}}
    else
      {:ok, product}
    end
  catch
    {:error, _} = error -> error
  end

  defp with_code(product) do
    if String.trim(product.code || "") == "" do
      {:ok, %{product | code: next_numeric_code(product.company_id)}}
    else
      {:ok, product}
    end
  end

  defp next_numeric_code(company_id) do
    max =
      Repo.all(from(p in Product, where: p.company_id == ^company_id, select: p.code))
      |> Enum.map(&to_int/1)
      |> Enum.max(fn -> 0 end)

    Stream.iterate(max + 1, &(&1 + 1))
    |> Enum.find(fn candidate -> not code_taken?(company_id, to_string(candidate), 0) end)
    |> to_string()
  end

  defp check_code(company_id, code, except_id) do
    if code_taken?(company_id, code, except_id) do
      {:error, {409, "артикул с този код вече съществува"}}
    else
      :ok
    end
  end

  defp code_taken?(company_id, code, except_id) do
    text = String.trim(code || "")

    if text == "" do
      false
    else
      Repo.all(
        from(p in Product,
          where: p.company_id == ^company_id and p.id != ^except_id,
          select: p.code
        )
      )
      |> Enum.any?(fn have ->
        String.downcase(String.trim(have || "")) == String.downcase(text)
      end)
    end
  end

  defp account_defaults(product) do
    if product.is_service == 0 and String.trim(product.product_type || "") == "10" do
      product =
        Enum.reduce(
          [
            {:inventory_account_id, "302"},
            {:revenue_account_id, "706"},
            {:expense_account_id, "601"}
          ],
          product,
          fn {field, number}, acc ->
            if Map.get(acc, field) > 0 do
              acc
            else
              Map.put(acc, field, Accounts.ensure_by_number(product.company_id, number))
            end
          end
        )

      {:ok, product}
    else
      {:ok, product}
    end
  end

  defp ensure_accounts(product) do
    Enum.reduce_while(
      [product.inventory_account_id, product.revenue_account_id, product.expense_account_id],
      :ok,
      fn id, _acc ->
        cond do
          id <= 0 ->
            {:cont, :ok}

          Repo.get_by(Catalog.Account, id: id, company_id: product.company_id) == nil ->
            {:halt, {:error, {404, "сметката не е намерен"}}}

          true ->
            {:cont, :ok}
        end
      end
    )
  end

  defp finish(product) do
    product =
      product
      |> Map.update!(:unit, &default(&1, "C62"))
      |> Map.update!(:price, &default(&1, "0"))
      |> Map.update!(:cost_price, &default(&1, "0"))
      |> Map.update!(:vat_rate, &default(&1, "20"))
      |> Map.update!(:stock_quantity, &default(&1, "0"))
      |> Map.update!(:product_type, &String.trim(&1 || ""))
      |> Map.update!(:cn8_code, &String.trim(&1 || ""))
      |> Map.update!(:cn8_name, &String.trim(&1 || ""))
      |> Map.update!(:auto_write_off, &if(&1 != 0, do: 1, else: 0))

    product =
      if product.is_service != 0 do
        %{
          product
          | is_service: 1,
            is_inventory: 0,
            stock_quantity: "0",
            stock_value: "0",
            product_type: "",
            expense_account_id: 0,
            auto_write_off: 0,
            cn8_code: if(product.cn8_code == "", do: "00000000", else: product.cn8_code)
        }
      else
        product = if product.product_type == "10", do: %{product | is_inventory: 1}, else: product

        product =
          cond do
            product.is_inventory != 0 ->
              type =
                if product.product_type in @product_types, do: product.product_type, else: "30"

              %{product | is_inventory: 1, product_type: type}

            product.product_type != "" and product.product_type not in @product_types ->
              %{product | product_type: ""}

            true ->
              product
          end

        if product.product_type != "10" or product.is_inventory == 0 do
          %{product | auto_write_off: 0}
        else
          product
        end
      end

    cond do
      product.auto_write_off == 1 and
          (product.expense_account_id <= 0 or product.inventory_account_id <= 0) ->
        {:error, {422, @auto_write_off_message}}

      product.cn8_code != "" and product.cn8_name == "" ->
        {:ok, %{product | cn8_name: Cn8.name_of(product.cn8_code) || ""}}

      true ->
        {:ok, product}
    end
  end

  defp default(value, fallback) do
    if String.trim(value || "") == "", do: fallback, else: value
  end

  defp to_int(nil), do: 0

  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> 0
    end
  end
end

defmodule Transport.AccessStub do
  @moduledoc """
  Заглушка на `Transport.Botyaga.check/3` за тестовете: един потребител,
  член само на фирма 1, освен ако тестът не добави друга с `grant_company/2`.
  """

  use Agent

  @default_sub "test@baga.example"

  def start_link(_opts),
    do: Agent.start_link(fn -> MapSet.new([{@default_sub, 1}]) end, name: __MODULE__)

  def check("ghost@baga.example", _ver, _company_id),
    do: {:error, {401, "потребителят не съществува"}}

  def check(sub, _ver, company_id) do
    if MapSet.member?(Agent.get(__MODULE__, & &1), {sub, company_id}),
      do: :ok,
      else: {:error, {403, "нямате достъп до тази фирма"}}
  end
end

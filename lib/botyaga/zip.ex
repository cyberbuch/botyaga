defmodule Botyaga.Zip do
  @moduledoc """
  ZIP без компресия (store), за да мине кирилицата като UTF-8. CRC32 е стандартният
  IEEE (`:erlang.crc32`). Ползва се за XLSX/ODS/DOCX/ODT. Порт на `reports_sheet.rs#pack`.
  """

  def pack(files) do
    {out, central, _offset} =
      Enum.reduce(files, {<<>>, <<>>, 0}, fn {name, data}, {out, central, offset} ->
        crc = :erlang.crc32(data)
        size = byte_size(data)
        name_size = byte_size(name)

        local =
          <<0x04034B50::little-32, 20::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-16, crc::little-32, size::little-32, size::little-32, name_size::little-16,
            0::little-16>> <> name <> data

        entry =
          <<0x02014B50::little-32, 20::little-16, 20::little-16, 0::little-16, 0::little-16,
            0::little-16, 0::little-16, crc::little-32, size::little-32, size::little-32,
            name_size::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-32, offset::little-32>> <> name

        {out <> local, central <> entry, offset + byte_size(local)}
      end)

    cd_off = byte_size(out)
    cd_len = byte_size(central)
    n = length(files)

    out <>
      central <>
      <<0x06054B50::little-32, 0::little-16, 0::little-16, n::little-16, n::little-16,
        cd_len::little-32, cd_off::little-32, 0::little-16>>
  end
end

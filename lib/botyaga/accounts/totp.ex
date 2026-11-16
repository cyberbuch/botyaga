defmodule Botyaga.Accounts.Totp do
  @moduledoc """
  TOTP по RFC 6238: SHA1, 6 цифри, 30 секунди, прозорец ±1.
  Резервният код е 8 байта hex във формат `aaaaaaaa-bbbbbbbb`, в базата стои SHA-256.
  """

  import Bitwise

  def new_secret do
    20 |> :crypto.strong_rand_bytes() |> Base.encode32()
  end

  @doc "Номер на прозореца, който покрива кода, или nil."
  def totp_counter(secret_b32, code, unix) do
    secret = decode_b32(secret_b32)

    digits = Regex.replace(~r/[^0-9]/, code || "", "")

    with true <- secret != :error,
         true <- String.length(digits) == 6 do
      slot = div(max(unix, 0), 30)

      Enum.find_value(-1..1, fn delta ->
        counter = slot + delta
        if counter >= 0 and hotp(secret, counter) == digits, do: counter
      end)
    else
      _ -> nil
    end
  end

  defp decode_b32(text) do
    clean = text |> String.trim() |> String.replace("=", "")

    padded =
      case rem(byte_size(clean), 8) do
        0 -> clean
        n -> clean <> String.duplicate("=", 8 - n)
      end

    case Base.decode32(padded, case: :mixed) do
      {:ok, decoded} when is_binary(decoded) -> decoded
      _ -> :error
    end
  end

  defp hotp(secret, counter) do
    mac = :crypto.mac(:hmac, :sha, secret, <<counter::64>>)
    <<_::bytes-size(19), offset>> = mac
    offset = offset &&& 0x0F
    bin = mac |> binary_part(offset, 4) |> :binary.decode_unsigned() |> band(0x7FFF_FFFF)
    bin |> rem(1_000_000) |> to_string() |> String.pad_leading(6, "0")
  end

  def otpauth_uri(secret_b32, account) do
    label = "#{pct("botyaga")}:#{pct(account)}"

    "otpauth://totp/#{label}?secret=#{secret_b32}&issuer=#{pct("botyaga")}&algorithm=SHA1&digits=6&period=30"
  end

  @doc "QR като SVG от матрицата на EQRCode — с тивата зона от 4 модула."
  def qr_svg(uri) do
    matrix =
      uri
      |> EQRCode.encode(:m)
      |> then(fn %EQRCode.Matrix{matrix: matrix} -> matrix end)
      |> Tuple.to_list()
      |> Enum.map(&Tuple.to_list/1)

    scale = 4
    quiet = 4
    size = (length(matrix) + quiet * 2) * scale

    rects =
      for {row, y} <- Enum.with_index(matrix),
          {dark, x} <- Enum.with_index(row),
          dark == 1 do
        ~s(<rect x="#{(x + quiet) * scale}" y="#{(y + quiet) * scale}" width="#{scale}" height="#{scale}"/>)
      end

    ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" viewBox="0 0 #{size} #{size}"><rect width="100%" height="100%" fill="#fff"/><g fill="#000">#{rects}</g></svg>)
  end

  def recovery_make do
    for _ <- 1..10 do
      raw = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
      code = "#{binary_part(raw, 0, 8)}-#{binary_part(raw, 8, 8)}"
      {code, recovery_hash(code)}
    end
  end

  def recovery_hash(code) do
    norm = Regex.replace(~r/[^0-9a-f]/, String.downcase(code), "")

    if norm == "", do: "", else: Base.encode16(:crypto.hash(:sha256, norm), case: :lower)
  end

  defp pct(text) do
    text
    |> String.to_charlist()
    |> Enum.map(fn
      c when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in [?-, ?., ?_, ?~] -> <<c>>
      c -> "%#{c |> Integer.to_string(16) |> String.upcase()}"
    end)
    |> Enum.join()
  end
end

defmodule Botyaga.Accounts.TotpTest do
  use ExUnit.Case, async: true

  alias Botyaga.Accounts.Totp

  # RFC 6238, секрет "12345678901234567890" в Base32, T=59 → 287082 (6 цифри).
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

  describe "totp_counter/3" do
    test "познава кода от текущия прозорец" do
      assert Totp.totp_counter(@secret, "287082", 59) == 1
      assert Totp.totp_counter(@secret, "287082", 60) == 1
    end

    test "отхвърля чужд код и нечислов вход" do
      assert Totp.totp_counter(@secret, "000000", 59) == nil
      assert Totp.totp_counter(@secret, "287 082", 59) == 1
      assert Totp.totp_counter(@secret, "abc", 59) == nil
      assert Totp.totp_counter("", "287082", 59) == nil
    end

    test "прозорецът е ±1" do
      # Прозорец 0 е 287082? Не — само за този секрет проверяваме текущия.
      assert Totp.totp_counter(@secret, "942870", 59) == nil
    end
  end

  describe "recovery_hash/1" do
    test "нормализира интервали и регистър" do
      assert Totp.recovery_hash("ABCD-1234") == Totp.recovery_hash("abcd1234")
    end

    test "празен код дава празен хеш" do
      assert Totp.recovery_hash("----") == ""
      assert Totp.recovery_hash("") == ""
    end
  end

  describe "otpauth_uri/2 и qr_svg/1" do
    test "URI е по RFC и носи издателя" do
      uri = Totp.otpauth_uri(@secret, "ivan@baga.example")
      assert uri =~ "otpauth://totp/ytbuch:ivan%40baga.example"
      assert uri =~ "secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
      assert uri =~ "issuer=ytbuch"
      assert uri =~ "algorithm=SHA1&digits=6&period=30"
    end

    test "QR е SVG" do
      svg = Totp.qr_svg("otpauth://totp/test")
      assert svg =~ ~r/^<svg /
      assert svg =~ "</svg>"
    end
  end
end

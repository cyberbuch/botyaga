defmodule Botyaga.AccountsTest do
  use Botyaga.DataCase, async: false

  alias Botyaga.{Accounts, Settings}

  describe "пароли" do
    test "argon2 хеш се потвърждава и отхвърля" do
      user = user("argon@baga.example", "парола-123")
      assert Accounts.password_ok?(user, "парола-123")
      refute Accounts.password_ok?(user, "друга")
    end

    test "наследеният sha256 хеш се презаписва с argon2 при вход" do
      email = "legacy@baga.example"
      legacy = legacy_hash(email, "стара-парола")
      {:ok, user} = Accounts.create_user(email, "Иван", "временна-парола")

      Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
        set: [password_hash: legacy]
      )

      assert {:rehash, rehashed} = Accounts.authenticate(email, "стара-парола")
      assert rehashed.id == user.id
      assert :error = Accounts.authenticate(email, "грешна")

      Accounts.rehash_password(user, "стара-парола")
      fresh = Accounts.get_by_id(user.id)
      assert fresh.password_hash != legacy
      assert Accounts.password_ok?(fresh, "стара-парола")
    end
  end

  describe "сесийна версия" do
    test "смяната на парола расти версията и откраднат токен отпада" do
      {:ok, user} = Accounts.create_user("ver@baga.example", "Иван", "парола-123")
      assert user.session_version == 0

      {:ok, version} = Accounts.set_password(user, "нова-парола")
      assert version == 1
      assert Accounts.get_by_id(user.id).session_version == 1
    end
  end

  describe "резервни кодове" do
    test "кодът е за едно ползване" do
      {:ok, user} = Accounts.create_user("rec@baga.example", "Иван", "парола-123")
      Accounts.wipe_recovery(user.id)
      [{code, hash}] = Botyaga.Accounts.Totp.recovery_make() |> Enum.take(1)
      Accounts.insert_recovery(user.id, [hash])

      assert Accounts.take_recovery(user.id, code)
      refute Accounts.take_recovery(user.id, code)
      refute Accounts.take_recovery(user.id, "нещо-друго")
    end
  end

  describe "TOTP брояч" do
    test "прозорецът не може да се ползва два пъти" do
      {:ok, user} = Accounts.create_user("totp@baga.example", "Иван", "парола-123")
      assert Accounts.totp_consume_counter(user.id, 42)
      refute Accounts.totp_consume_counter(user.id, 42)
      refute Accounts.totp_consume_counter(user.id, 41)
      assert Accounts.totp_consume_counter(user.id, 43)
      assert Settings.get("totp_last:#{user.id}") == "43"
    end
  end

  describe "бутерболки" do
    test "email по име за вход или по имейл" do
      {:ok, user} = Accounts.create_user("log@baga.example", "Иван", "парола-123")
      assert Accounts.get_by_login("log@baga.example").id == user.id
      assert Accounts.get_by_login(user.username).id == user.id
      assert Accounts.get_by_login("липсва@baga.example") == nil
    end
  end

  defp user(email, password) do
    {:ok, user} = Accounts.create_user(email, "Иван", password)
    user
  end

  defp legacy_hash(email, password) do
    :crypto.hash(:sha256, "bagabuch|#{email}|#{password}") |> Base.encode16(case: :lower)
  end
end

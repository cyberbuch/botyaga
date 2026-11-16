defmodule Botyaga.S3Test do
  use ExUnit.Case, async: true

  alias Botyaga.S3
  alias Botyaga.S3.Sign

  @cfg %{
    endpoint: "",
    bucket: "test-bucket",
    access_key: "AKIAEXAMPLE",
    secret_key: "secretexample",
    region: "us-east-1",
    prefix: "backups/"
  }

  test "uri_encode RFC3986" do
    assert Sign.uri_encode("a b") == "a%20b"
    assert Sign.uri_encode("a/b", true) == "a/b"
    assert Sign.uri_encode("a/b", false) == "a%2Fb"
    assert Sign.uri_encode("AZaz09-_.~") == "AZaz09-_.~"
    assert Sign.uri_encode("ключ") == "%D0%BA%D0%BB%D1%8E%D1%87"
  end

  test "canonical_query sorts by key" do
    assert Sign.canonical_query([{"prefix", "backups/"}, {"list-type", "2"}]) ==
             "list-type=2&prefix=backups%2F"
  end

  test "authorization is well-formed and deterministic" do
    now = ~U[2026-01-15 10:30:00Z]

    {url, headers} =
      Sign.sign_request("GET", "test-bucket", "", [{"list-type", "2"}], "", @cfg, now)

    assert url == "https://s3.us-east-1.amazonaws.com/test-bucket?list-type=2"
    {"authorization", auth} = List.keyfind(headers, "authorization", 0)
    assert auth =~ "AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20260115/us-east-1/s3/aws4_request"
    assert auth =~ "SignedHeaders=host;x-amz-content-sha256;x-amz-date"
    assert auth =~ ~r/Signature=[0-9a-f]{64}$/

    {_, headers2} =
      Sign.sign_request("GET", "test-bucket", "", [{"list-type", "2"}], "", @cfg, now)

    assert headers == headers2
  end

  test "host_of uses custom endpoint path-style" do
    assert Sign.host_of(@cfg) == "s3.us-east-1.amazonaws.com"
    assert Sign.host_of(%{@cfg | endpoint: "http://minio:9000/"}) == "minio:9000"
  end

  test "validate requires bucket and credentials" do
    assert {:error, {422, "S3 bucket е задължителен"}} = S3.validate(%{@cfg | bucket: ""})
    assert {:error, {400, "Невалидни credentials"}} = S3.validate(%{@cfg | access_key: ""})
    assert :ok = S3.validate(@cfg)
  end

  test "backup names are strict" do
    assert S3.is_backup_name("ytbuch_backup_20261027_221035.sql.gz")
    assert S3.is_backup_name("ydb_backup_2026-10-27.tar.gz")
    refute S3.is_backup_name("my_ytbuch_backup_notes.txt")
    refute S3.is_backup_name("ytbuch_backup_.sql.gz")
    refute S3.is_backup_name("ytbuch_backup_a/../../etc.sql.gz")
    refute S3.is_backup_name("ydb_backup_x.tar.gz/../../obj")
    refute S3.is_backup_name("other.txt")
  end

  test "human size" do
    assert S3.human(500) == "0.5 KB"
    assert S3.human(2_000_000) == "1.9 MB"
  end
end

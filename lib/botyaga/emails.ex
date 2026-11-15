defmodule Botyaga.Emails do
  @moduledoc "Писма по настройките на системата. Пускат се извън заявката."

  require Logger

  alias Botyaga.{Mailer, Settings}

  def reset_password(email, link) do
    deliver(
      email,
      "Възстановяване на парола — #{Settings.app_name()}",
      """
      <p>Заявка за нова парола в #{Settings.app_name()}.</p>
      <p><a href="#{escape(link)}">Смени паролата</a></p>
      <p>Линкът е валиден 1 час.</p>
      """
    )
  end

  def registration_taken(email) do
    deliver(
      email,
      "Опит за регистрация — #{Settings.app_name()}",
      """
      <p>Някой се опита да се регистрира в #{Settings.app_name()} с този email, но той вече е зает.</p>
      <p>Ако сте вие, влезте или сменете паролата. Ако не сте — игнорирайте писмото.</p>
      """
    )
  end

  def deliver(email, subject, html) do
    cfg = Settings.smtp_cfg()

    if cfg.host == "" do
      :ok
    else
      Task.start(fn ->
        deliver_now(email, subject, html)
      end)

      :ok
    end
  end

  @doc "Синхронно изпращане — за теста на SMTP, за да се види грешката."
  def deliver_now(email, subject, html) do
    cfg = Settings.smtp_cfg()

    try do
      Swoosh.Email.new()
      |> Swoosh.Email.to(email)
      |> Swoosh.Email.from({cfg.from_name, cfg.from_email})
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(html)
      |> Mailer.deliver(smtp_opts(cfg))
    rescue
      error -> {:error, inspect(error)}
    end
  end

  defp smtp_opts(cfg) do
    opts = [adapter: Swoosh.Adapters.SMTP, relay: cfg.host, port: cfg.port]

    opts =
      if cfg.username != "" do
        Keyword.merge(opts, username: cfg.username, password: cfg.password, auth: :always)
      else
        opts
      end

    # 465 е implicit TLS, иначе STARTTLS при включена опция.
    cond do
      cfg.port == 465 -> Keyword.put(opts, :ssl, true)
      cfg.use_tls -> Keyword.merge(opts, tls: :always)
      true -> Keyword.merge(opts, tls: :never)
    end
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end
end

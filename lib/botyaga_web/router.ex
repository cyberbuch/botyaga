defmodule BotyagaWeb.Router do
  use BotyagaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug BotyagaWeb.Plugs.RateLimitGeneral
  end

  pipeline :auth_limit do
    plug BotyagaWeb.Plugs.RateLimitAuth
  end

  pipeline :gate do
    plug BotyagaWeb.Plugs.Gate
  end

  scope "/" do
    pipe_through :api

    get "/health", BotyagaWeb.HealthController, :health
    get "/ready", BotyagaWeb.HealthController, :ready
    get "/readyz", BotyagaWeb.HealthController, :ready
  end

  # Шестте публични входни пътя: по-строг лимит на адреса.
  scope "/v1/auth", BotyagaWeb do
    pipe_through [:api, :auth_limit, :gate]

    post "/token", AuthController, :token
    post "/mfa", AuthController, :mfa
    get "/registration-status", AuthFlowController, :registration_status
    post "/register", AuthFlowController, :register
    post "/forgot-password", AuthFlowController, :forgot_password
    post "/reset-password", AuthFlowController, :reset_password
  end

  scope "/v1", BotyagaWeb do
    pipe_through [:api, :gate]

    get "/me", ProfileController, :me
    patch "/me", ProfileController, :update_name
    post "/me/password", ProfileController, :change_password
    post "/me/email", ProfileController, :change_email
    post "/me/totp/start", ProfileController, :totp_start
    post "/me/totp/confirm", ProfileController, :totp_confirm
    post "/me/totp/disable", ProfileController, :totp_disable

    get "/companies", CompaniesController, :index
    post "/companies", CompaniesController, :create
    get "/companies/:id/settings", CompaniesController, :settings
    get "/companies/:id", CompaniesController, :show
    patch "/companies/:id", CompaniesController, :update
    delete "/companies/:id", CompaniesController, :delete
    get "/active-company", CompaniesController, :active_get
    put "/active-company", CompaniesController, :active_set
    get "/dashboard", CompaniesController, :dashboard

    post "/companies/:id/locations", RelatedController, :create_location
    patch "/company-locations/:id", RelatedController, :update_location
    delete "/company-locations/:id", RelatedController, :delete_location
    post "/companies/:id/beneficial-owners", RelatedController, :create_owner
    patch "/beneficial-owners/:id", RelatedController, :update_owner
    delete "/beneficial-owners/:id", RelatedController, :delete_owner
    post "/companies/:id/ultimate-parents", RelatedController, :create_parent
    patch "/ultimate-parents/:id", RelatedController, :update_parent
    delete "/ultimate-parents/:id", RelatedController, :delete_parent
    post "/companies/:id/document-series", RelatedController, :create_series
    patch "/document-series/:id", RelatedController, :update_series
    delete "/document-series/:id", RelatedController, :delete_series

    get "/companies/:id/users", MembersController, :index
    post "/companies/:id/users", MembersController, :add
    patch "/companies/:id/users/:user_id", MembersController, :update
    delete "/companies/:id/users/:user_id", MembersController, :remove

    get "/users", AccessController, :users_index
    post "/users", AccessController, :users_create
    patch "/users/:id", AccessController, :users_update
    delete "/users/:id", AccessController, :users_delete
    get "/roles", AccessController, :roles_index
    post "/roles", AccessController, :roles_create
    patch "/roles/:id", AccessController, :roles_update
    delete "/roles/:id", AccessController, :roles_delete

    get "/system-settings", SettingsController, :index
    put "/system-settings", SettingsController, :update
    post "/system-settings/smtp-test", SettingsController, :smtp_test

    get "/accounts", CatalogController, :accounts
    post "/accounts", CatalogController, :account_create
    post "/accounts/seed-saft", CatalogController, :seed_saft
    get "/accounts/:id", CatalogController, :account_show
    patch "/accounts/:id", CatalogController, :account_update
    delete "/accounts/:id", CatalogController, :account_delete

    get "/counterparts", CatalogController, :counterparts
    post "/counterparts", CatalogController, :counterpart_create
    get "/counterparts/:id", CatalogController, :counterpart_show
    patch "/counterparts/:id", CatalogController, :counterpart_update
    delete "/counterparts/:id", CatalogController, :counterpart_delete

    get "/products", CatalogController, :products
    post "/products", CatalogController, :product_create
    post "/products/cn8-suggest", CatalogController, :cn8_suggest
    get "/products/:id", CatalogController, :product_show
    patch "/products/:id", CatalogController, :product_update
    delete "/products/:id", CatalogController, :product_delete

    get "/saft/nomenclatures", CatalogController, :nomenclatures
    get "/units", CatalogController, :units

    get "/invoices", InvoicesController, :index
    post "/invoices", InvoicesController, :create
    get "/invoices/next-number", InvoicesController, :next_number
    post "/invoices/bulk/post", InvoicesController, :bulk_post
    post "/invoices/bulk/unpost", InvoicesController, :bulk_unpost
    post "/invoices/bulk/delete", InvoicesController, :bulk_delete
    get "/invoices/:id", InvoicesController, :show
    patch "/invoices/:id", InvoicesController, :update
    delete "/invoices/:id", InvoicesController, :delete
    post "/invoices/:id/post", InvoicesController, :post

    get "/journal", JournalController, :index
    post "/journal", JournalController, :create
    post "/journal/bulk/delete", JournalController, :bulk_delete
    get "/journal/:id", JournalController, :show
    put "/journal/:id", JournalController, :update
    patch "/journal/:id", JournalController, :update
    delete "/journal/:id", JournalController, :delete

    get "/accounting-periods", PeriodsController, :index
    post "/accounting-periods/close", PeriodsController, :close
    post "/accounting-periods/reopen", PeriodsController, :reopen

    match :*, "/*path", FallbackController, :fallback
  end

  # LiveDashboard и пощенската кутия само за локална разработка.
  if Application.compile_env(:botyaga, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: BotyagaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

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
    post "/logout", AuthController, :logout
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

    get "/admin/access", AdminController, :access
    get "/admin/login-events", AdminController, :login_events
    post "/admin/users/:id/revoke-sessions", AdminController, :revoke_sessions

    get "/system-settings", SettingsController, :index
    put "/system-settings", SettingsController, :update
    post "/system-settings/smtp-test", SettingsController, :smtp_test
    get "/system-settings/db-check", SettingsController, :db_check
    post "/system-settings/s3-test", SettingsController, :s3_test
    post "/system-settings/s3-backup", SettingsController, :s3_backup
    get "/system-settings/s3-backups", SettingsController, :s3_backups
    post "/system-settings/s3-delete", SettingsController, :s3_delete

    get "/accounts", CatalogController, :accounts
    post "/accounts", CatalogController, :account_create
    post "/accounts/seed-saft", CatalogController, :seed_saft
    get "/accounts/:id", CatalogController, :account_show
    patch "/accounts/:id", CatalogController, :account_update
    delete "/accounts/:id", CatalogController, :account_delete

    get "/counterparts", CatalogController, :counterparts
    post "/counterparts", CatalogController, :counterpart_create
    get "/counterparts/vies-lookup", ViesController, :lookup
    post "/counterparts/vies", ViesController, :create
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
    post "/invoices/:id/pay", InvoicesController, :pay
    post "/invoices/:id/unpay", InvoicesController, :unpay
    get "/invoices/:id/print", InvoicesController, :print
    get "/invoices/:id/ubl", InvoicesController, :ubl
    post "/invoices/:id/issue-protocol", InvoicesController, :issue_protocol
    post "/invoices/:id/issue-customs", InvoicesController, :issue_customs

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

    get "/opening-balances", OpeningController, :index
    post "/opening-balances", OpeningController, :create
    patch "/opening-balances/:id", OpeningController, :update
    delete "/opening-balances/:id", OpeningController, :delete

    get "/closing-operations/preview", ClosingController, :preview
    post "/closing-operations/run", ClosingController, :run

    get "/vat/registers", VatController, :registers
    get "/vat/return", VatController, :registers
    get "/vat/export", VatController, :export
    put "/vat/manual", VatController, :manual_save
    get "/vat/operations/codes", VatController, :operations_codes
    get "/vat/operations", VatController, :operations_index
    post "/vat/operations", VatController, :operations_create
    patch "/vat/operations/:id", VatController, :operations_update
    delete "/vat/operations/:id", VatController, :operations_delete
    get "/oss/reports", OssController, :reports
    post "/oss/reports", OssController, :create
    get "/oss/reports/:id", OssController, :report
    patch "/oss/reports/:id", OssController, :update
    delete "/oss/reports/:id", OssController, :delete
    get "/oss/reports/:id/preview", OssController, :preview
    post "/oss/reports/:id/confirm", OssController, :confirm
    post "/oss/reports/:id/unpost", OssController, :unpost
    get "/oss/month/:month", OssController, :month
    post "/oss/month/:month/declare", OssController, :declare
    delete "/oss/month/:month/declare", OssController, :undeclare
    get "/oss/quarter/:year/:quarter", OssController, :quarter
    post "/oss/quarter/:year/:quarter/freeze", OssController, :freeze
    post "/oss/quarter/:year/:quarter/submit", OssController, :submit
    post "/oss/quarter/:year/:quarter/unsubmit", OssController, :unsubmit
    get "/oss/quarter/:year/:quarter/register", OssController, :register
    get "/vat-exemptions", VatController, :exemptions

    get "/bank-formats", BankingController, :formats
    get "/bank-accounts", BankingController, :index
    post "/bank-accounts", BankingController, :create
    patch "/bank-accounts/:id", BankingController, :update
    delete "/bank-accounts/:id", BankingController, :delete

    get "/bank-transactions", BankingController, :transactions
    post "/bank-transactions/preview", BankingController, :preview
    post "/bank-transactions/import", BankingController, :import
    post "/bank-transactions/bulk/delete", BankingController, :bulk_delete_transactions
    post "/bank-transactions/auto-allocate", BankingController, :auto_allocate
    post "/bank-transactions/auto-allocate/preview", BankingController, :allocate_preview
    post "/bank-transactions/:id/book/preview", BankingController, :book_preview
    post "/bank-transactions/:id/book", BankingController, :book
    post "/bank-transactions/:id/reallocate", BankingController, :reallocate
    post "/bank-transactions/:id/unbook", BankingController, :unbook
    delete "/bank-transactions/:id", BankingController, :delete_transaction

    get "/bank-matching-rules", BankingController, :rules
    post "/bank-matching-rules", BankingController, :create_rule
    post "/bank-matching-rules/defaults", BankingController, :rule_defaults
    patch "/bank-matching-rules/:id", BankingController, :update_rule
    delete "/bank-matching-rules/:id", BankingController, :delete_rule

    get "/fixed-asset-categories", AssetsController, :categories
    post "/fixed-asset-categories", AssetsController, :category_create
    patch "/fixed-asset-categories/:id", AssetsController, :category_update
    delete "/fixed-asset-categories/:id", AssetsController, :category_delete

    get "/fixed-assets", AssetsController, :index
    post "/fixed-assets", AssetsController, :create
    post "/fixed-assets/depreciation/preview", AssetsController, :depreciation_preview
    post "/fixed-assets/depreciation/post", AssetsController, :depreciation_post
    get "/fixed-assets/:id", AssetsController, :show
    patch "/fixed-assets/:id", AssetsController, :update
    delete "/fixed-assets/:id", AssetsController, :delete
    post "/fixed-assets/:id/revalue", AssetsController, :revalue
    post "/fixed-assets/:id/move", AssetsController, :move
    post "/fixed-assets/:id/conserve", AssetsController, :conserve
    post "/fixed-assets/:id/end-conserve", AssetsController, :end_conserve
    post "/fixed-assets/:id/dispose", AssetsController, :dispose
    get "/fixed-assets/:id/events", AssetsController, :events

    get "/stock/rules", StockController, :rules
    post "/stock/rules", StockController, :create_rule
    delete "/stock/rules/:id", StockController, :delete_rule
    post "/stock/rebuild", StockController, :rebuild
    post "/stock/writeoff", StockController, :writeoff
    get "/stock/report", StockController, :report
    get "/inventory/at-location", StockController, :at_location

    get "/material-issues", StockController, :material_issues
    post "/material-issues", StockController, :material_issue_create
    get "/material-issues/:id", StockController, :material_issue_show
    patch "/material-issues/:id", StockController, :material_issue_update
    delete "/material-issues/:id", StockController, :material_issue_delete
    post "/material-issues/:id/confirm", StockController, :material_issue_confirm
    post "/material-issues/:id/unpost", StockController, :material_issue_unpost

    get "/production-receipts/preview", StockController, :production_receipt_preview
    get "/production-receipts", StockController, :production_receipts
    post "/production-receipts", StockController, :production_receipt_create
    get "/production-receipts/:id", StockController, :production_receipt_show
    patch "/production-receipts/:id", StockController, :production_receipt_update
    delete "/production-receipts/:id", StockController, :production_receipt_delete
    post "/production-receipts/:id/confirm", StockController, :production_receipt_confirm
    post "/production-receipts/:id/unpost", StockController, :production_receipt_unpost

    get "/internal-docs/next-number", StockController, :internal_doc_next_number
    get "/internal-docs", StockController, :internal_docs
    post "/internal-docs", StockController, :internal_doc_create
    get "/internal-docs/:id", StockController, :internal_doc_show
    get "/internal-docs/:id/print", StockController, :internal_doc_print
    patch "/internal-docs/:id", StockController, :internal_doc_update
    delete "/internal-docs/:id", StockController, :internal_doc_delete
    post "/internal-docs/:id/confirm", StockController, :internal_doc_confirm

    get "/recipes", ProductionController, :recipes
    post "/recipes", ProductionController, :recipe_create
    get "/recipes/:id", ProductionController, :recipe_show
    patch "/recipes/:id", ProductionController, :recipe_update
    delete "/recipes/:id", ProductionController, :recipe_delete

    get "/attachments/:doc_type/:doc_id", AttachmentsController, :index
    post "/attachments/:doc_type/:doc_id", AttachmentsController, :create
    get "/attachments/:id/download", AttachmentsController, :download
    delete "/attachments/:id", AttachmentsController, :delete
    get "/kits", StockController, :kits
    post "/kits", StockController, :kit_create
    get "/kits/:id", StockController, :kit
    patch "/kits/:id", StockController, :kit_update
    delete "/kits/:id", StockController, :kit_delete
    post "/kits/:id/confirm", StockController, :kit_confirm
    post "/kits/:id/unpost", StockController, :kit_unpost
    get "/production-orders/:id/pdf", ProductionController, :order_pdf
    get "/production-cards/:id/pdf", ProductionController, :card_pdf
    get "/production-receipts/:id/pdf", StockController, :receipt_pdf
    get "/kits/:id/pdf", StockController, :kit_pdf
    get "/production-cards", ProductionController, :cards
    post "/production-cards", ProductionController, :card_create
    get "/production-cards/:id", ProductionController, :card
    patch "/production-cards/:id", ProductionController, :card_update
    delete "/production-cards/:id", ProductionController, :card_delete
    get "/production-cards/:id/preview", ProductionController, :card_preview
    post "/production-cards/:id/confirm", ProductionController, :card_confirm
    post "/production-cards/:id/unpost", ProductionController, :card_unpost
    get "/production-orders", ProductionController, :orders
    post "/production-orders", ProductionController, :order_create
    get "/production-orders/:id", ProductionController, :order_show
    delete "/production-orders/:id", ProductionController, :order_delete
    post "/production-orders/:id/confirm", ProductionController, :order_confirm

    get "/dividend-distributions", DividendsController, :index
    post "/dividend-distributions", DividendsController, :create
    get "/dividend-distributions/:id", DividendsController, :show
    patch "/dividend-distributions/:id", DividendsController, :update
    delete "/dividend-distributions/:id", DividendsController, :delete
    post "/dividends/:id/pay", DividendsController, :pay

    get "/reports", ReportsController, :index
    get "/reports/export", ReportsController, :export

    get "/fs/lines", FsController, :lines
    get "/fs/formulas", FsController, :index
    put "/fs/formulas", FsController, :put
    post "/fs/formulas/defaults", FsController, :defaults
    post "/fs/formulas/validate", FsController, :validate
    post "/fs/formulas/clear", FsController, :clear

    get "/saft/export", SaftController, :export
    get "/saft/preview", SaftController, :preview
    get "/saft/movement-mappings", SaftController, :mappings_index
    post "/saft/movement-mappings", SaftController, :mappings_create
    post "/saft/movement-mappings/defaults", SaftController, :mappings_defaults
    patch "/saft/movement-mappings/:id", SaftController, :mappings_update
    delete "/saft/movement-mappings/:id", SaftController, :mappings_delete

    post "/scans/ubl", ScansController, :ubl
    post "/scans/extract", ScansController, :extract
    get "/product-name-mappings", PnmapController, :index
    post "/product-name-mappings", PnmapController, :save

    get "/exchange-rates", RatesController, :index
    get "/exchange-rates/rate", RatesController, :rate
    get "/exchange-rates/cross", RatesController, :cross
    post "/exchange-rates/import", RatesController, :import

    post "/addresses/parse", AddressesController, :parse

    get "/audit-logs", AuditController, :index
    get "/audit-logs/:entity_type/:entity_id", AuditController, :entity_history

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

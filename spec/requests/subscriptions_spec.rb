# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the e-mail alert subscriptions (civora-org/civora-platform
# #121): the form, the double opt-in, token tampering, expiry, unsubscribing
# (page, POST and the mail clients' one-click POST), the rate limit and the
# response that must not reveal whether an address is subscribed. :db group,
# synthetic data only; the dummy mailer delivers into ActionMailer's test
# store.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "e-mail alert subscriptions", :db, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:subscription_class) { Decidim::ContractsSk::Subscription }
  let(:throttle) { Decidim::ContractsSk::SubscriptionThrottle.default }
  let(:email) { "reader@example.org" }

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "en", name: { "en" => "Green Village" })
    [Decidim::ContractsSk::SubscriptionsController, Decidim::ContractsSk::ContractsController].each do |controller|
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end
    throttle.reset!
    ActionMailer::Base.deliveries.clear
  end

  after { throttle.reset! }

  def subscribe(address = email, filters = { "q" => "cesta" }, **opts)
    post "/subscriptions", params: { email: address }.merge(filters), **opts
  end

  def mails
    ActionMailer::Base.deliveries
  end

  def mail_body(mail = mails.last)
    mail.body.decoded
  end

  # The raw confirmation token out of the confirmation e-mail.
  def mailed_token(mail = mails.last)
    mail_body(mail)[%r{/subscriptions/([^/]+)/confirm}, 1]
  end

  # Every stored value of every row, as one string.
  def table_dump
    ActiveRecord::Base.connection.select_rows("SELECT * FROM decidim_contracts_sk_subscriptions").flatten.join(" ")
  end

  def mailed_unsubscribe_token(mail = mails.last)
    mail_body(mail)[%r{/subscriptions/([^/"]+)/unsubscribe}, 1]
  end

  # Starts a subscription and returns [record, raw token].
  def start!(address = email, filters = { "q" => "cesta" })
    subscribe(address, filters)
    [subscription_class.find_by!(email: address), mailed_token]
  end

  describe "the form" do
    it "is on the catalogue page next to the downloads, posting the normalized filters but not the sort" do
      get "/?q=cesta&amount_min=10+000,5&sort=amount_asc&bogus=1"

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      form = html.at_css("section.cs-alerts form[action='/subscriptions'][method='post']")
      expect(form).to be_present
      expect(form.at_css("input[type=email][name=email][required][autocomplete=email]")).to be_present
      expect(form.at_css("label[for=alert_email]")).to be_present
      hidden = form.css("input[type=hidden]").to_h { |input| [input["name"], input["value"]] }
      expect(hidden).to include("q" => "cesta", "amount_min" => "10000.5")
      expect(hidden.keys).not_to include("sort", "bogus")
    end

    it "is absent for the source=crz filter, whose own-records alerts could never match" do
      get "/?source=crz"

      expect(response.body).not_to include("cs-alerts")
    end

    it "has a page of its own that restates the search and offers the same form" do
      get "/subscriptions/new?q=cesta&sort=amount_asc"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Search: cesta").and include("/subscriptions")
      expect(response.body).not_to include("Sort:")
      # The harness layout echoes the request URL into its meta tags, so the
      # sort check is on the form's fields.
      hidden = Nokogiri::HTML(response.body).css("form input[type=hidden]").map { |input| input["name"] }
      expect(hidden).to include("q")
      expect(hidden).not_to include("sort")
      expect(response.body).to include('name="robots" content="noindex"')
    end

    it "refuses to offer alerts on the new page for a CRZ-only search" do
      get "/subscriptions/new?source=crz"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('action="/subscriptions"')
    end
  end

  describe "subscribing" do
    it "stores an unconfirmed subscription and sends exactly one confirmation e-mail, nothing else" do
      expect { subscribe }.to change(subscription_class, :count).by(1)

      subscription = subscription_class.last
      expect(response).to have_http_status(:ok)
      expect(subscription.confirmed_at).to be_nil
      expect(subscription.last_notified_at).to be_nil
      expect(subscription.email).to eq("reader@example.org")
      expect(subscription.filter_params).to eq("q" => "cesta")
      expect(subscription.locale).to eq("en")
      expect(mails.size).to eq(1)
      expect(mails.first.to).to eq(["reader@example.org"])
      expect(mails.first.subject).to include("Confirm your contract alerts")
    end

    it "answers with a page that does not contain the address" do
      subscribe("someone.private@example.org")

      expect(response.body).to include("Check your inbox")
      expect(response.body).not_to include("someone.private@example.org")
    end

    it "stores the token only as a digest: the raw token is in the mail and nowhere in the database" do
      subscribe
      token = mailed_token
      row = subscription_class.last

      expect(token).to match(/\A[A-Za-z0-9_-]{43}\z/)
      expect(row.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(token))
      expect(table_dump).not_to include(token)
    end

    it "stores nothing beyond the approved columns: no IP, no user agent" do
      subscribe(email, { "q" => "cesta" },
                headers: { "REMOTE_ADDR" => "203.0.113.55", "User-Agent" => "UA-SENTINEL-9" })

      expect(table_dump).not_to include("203.0.113.55")
      expect(table_dump).not_to include("UA-SENTINEL-9")
    end

    it "stores the request locale and mails in it" do
      I18n.with_locale(:sk) { subscribe }

      expect(subscription_class.last.locale).to eq("sk")
      expect(mails.last.subject).to start_with("Potvrďte upozornenia")
    end

    it "is the same for a signed-in visitor: still unconfirmed, still a confirmation mail" do
      allow_any_instance_of(Decidim::ContractsSk::SubscriptionsController)
        .to receive(:current_user).and_return(Decidim::User.create!(organization: organization))

      subscribe

      expect(subscription_class.last.confirmed_at).to be_nil
      expect(mails.size).to eq(1)
    end

    it "sets the privacy headers on every subscription response: no-store, no referrer" do
      subscribe

      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.body).to include('name="robots" content="noindex"')
    end

    it "rejects a malformed address with 422, an error on the field, no row and no mail" do
      subscribe("not-an-address")

      expect(response).to have_http_status(:unprocessable_entity)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("#alert-error[role=alert]").text).to include("valid e-mail")
      expect(html.at_css("#alert_email")["aria-invalid"]).to eq("true")
      expect(subscription_class.count).to eq(0)
      expect(mails).to be_empty
    end

    it "echoes a rejected address back only escaped" do
      subscribe("\"><script>alert(1)</script>")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include("<script>alert(1)</script>")
    end

    it "rejects a CRZ-only search with 422" do
      subscribe(email, { "source" => "crz" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(subscription_class.count).to eq(0)
    end

    it "survives hostile filter params without a 500" do
      post "/subscriptions", params: { email: email, q: ["a"], "party" => { "x" => "y" }, amount_min: "9" * 400,
                                       published_from: "9999999-99-99", unknown: "1" }

      expect(response).to have_http_status(:ok)
      expect(subscription_class.last.filter_params).not_to have_key("unknown")
    end

    it "does not break on an array or hash e-mail param, and never turns it into an address" do
      allow(Decidim::ContractsSk::CreateSubscription).to receive(:call).and_call_original

      post "/subscriptions", params: { email: ["a@example.org"] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::CreateSubscription).to have_received(:call).with(hash_including(email: ""))
    end

    it "re-renders a rejected post with the search but without the posted sort or foreign params" do
      subscribe("nope", { "q" => "cesta", "sort" => "amount_asc", "bogus" => "1" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Search: cesta")
      expect(response.body).not_to include("Sort:")
      hidden = Nokogiri::HTML(response.body).css("form input[type=hidden]").map { |input| input["name"] }
      expect(hidden).not_to include("sort", "bogus", "email")
    end

    it "removes the row and says so when the confirmation mail cannot be sent" do
      allow(Decidim::ContractsSk::SubscriptionMailer)
        .to receive(:confirmation).and_raise(Net::SMTPFatalError, "550 reader@example.org")

      expect { subscribe }.not_to change(subscription_class, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include("could not be sent")
      expect(response.body).not_to include("reader@example.org")
    end
  end

  describe "not revealing whether an address is subscribed" do
    it "answers a confirmed address with the same page, and sends no mail" do
      record, token = start!
      post "/subscriptions/#{token}/confirm"
      expect(record.reload).to be_confirmed
      first_page = response.body
      mails.clear
      throttle.reset!

      subscribe
      expect(response.body).to include("Check your inbox")
      expect(mails).to be_empty
      expect(subscription_class.count).to eq(1)
      expect(first_page).to include("Alerts are on")
    end

    it "answers an address over the cap with the same page, no new row and no mail" do
      subscription_class::MAX_PER_EMAIL.times do |i|
        travel_to(Time.utc(2026, 10, 13) + (i * 2).hours) { subscribe(email, { "q" => "term#{i}" }) }
      end
      mails.clear

      travel_to(Time.utc(2026, 10, 13) + 20.hours) { subscribe(email, { "q" => "one-too-many" }) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Check your inbox")
      expect(subscription_class.count).to eq(subscription_class::MAX_PER_EMAIL)
      expect(mails).to be_empty
    end
  end

  describe "double opt-in" do
    it "does not confirm on GET: the link opens a page with a button, the row stays unconfirmed" do
      record, token = start!

      get "/subscriptions/#{token}/confirm"

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("form[action='/subscriptions/#{token}/confirm'][method=post] button")).to be_present
      expect(response.body).to include("Search: cesta")
      expect(response.body).not_to include(email)
      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(record.reload.confirmed_at).to be_nil
    end

    it "confirms on POST and starts the delivery window at that moment" do
      record, token = start!

      moment = Time.current.change(usec: 0) + 1.hour
      travel_to(moment) do
        post "/subscriptions/#{token}/confirm"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Alerts are on")
      end

      record.reload
      expect(record.confirmed_at).to eq(moment)
      expect(record.last_notified_at).to eq(moment)
    end

    it "treats a repeated confirmation (a scanner, a double click) as a success that changes nothing" do
      record, token = start!
      moment = Time.current.change(usec: 0) + 1.hour
      travel_to(moment) { post "/subscriptions/#{token}/confirm" }

      travel_to(moment + 1.day) { post "/subscriptions/#{token}/confirm" }

      expect(response).to have_http_status(:ok)
      expect(record.reload.confirmed_at).to eq(moment)
    end

    it "sends nothing to an unconfirmed address: the only mail ever sent is the confirmation" do
      start!

      expect(mails.size).to eq(1)
      expect(mails.first.subject).to include("Confirm")
    end
  end

  describe "token tampering" do
    it "refuses a changed, shortened, lengthened or foreign confirmation token with 404 and changes nothing" do
      record, token = start!
      flipped = token.dup.tap { |t| t[5] = t[5] == "A" ? "B" : "A" }
      candidates = [flipped, "#{token[0..-2]}x", "#{token}A", "A" * 43, record.token_digest, "x" * 16]

      candidates.each do |candidate|
        get "/subscriptions/#{candidate}/confirm"
        expect(response).to have_http_status(:not_found), "GET #{candidate}"
        post "/subscriptions/#{candidate}/confirm"
        expect(response).to have_http_status(:not_found), "POST #{candidate}"
      end
      expect(response.body).to include("This link is not valid")
      expect(record.reload.confirmed_at).to be_nil
    end

    it "does not let the unsubscribe token confirm, nor the confirmation token unsubscribe" do
      record, token = start!
      unsubscribe_token = mailed_unsubscribe_token

      post "/subscriptions/#{unsubscribe_token}/confirm"
      expect(response).to have_http_status(:not_found)
      expect(record.reload.confirmed_at).to be_nil

      post "/subscriptions/#{token}/unsubscribe"
      expect(response).to have_http_status(:not_found)
      expect(subscription_class.exists?(record.id)).to be(true)
    end

    it "refuses a token that is not in the route's URL-safe alphabet or length" do
      expect { get "/subscriptions/short/confirm" }.to raise_error(ActionController::RoutingError)
      expect { get "/subscriptions/#{"a" * 16}%00/confirm" }.to raise_error(ActionController::RoutingError)
    end

    it "does not honour another organization's token on this host" do
      _record, token = start!
      other = Decidim::Organization.create!(host: "other.example.org")
      allow_any_instance_of(Decidim::ContractsSk::SubscriptionsController)
        .to receive(:current_organization).and_return(other)

      post "/subscriptions/#{token}/confirm"
      expect(response).to have_http_status(:not_found)

      post "/subscriptions/#{mailed_unsubscribe_token}/unsubscribe"
      expect(response).to have_http_status(:not_found)
      expect(subscription_class.count).to eq(1)
    end

    it "refuses a tampered unsubscribe token and keeps the subscription" do
      record, = start!
      token = mailed_unsubscribe_token
      tampered = token.sub(/.(?=\z)/) { |c| c == "a" ? "b" : "a" }

      get "/subscriptions/#{tampered}/unsubscribe"
      expect(response).to have_http_status(:not_found)
      post "/subscriptions/#{tampered}/unsubscribe"
      expect(response).to have_http_status(:not_found)
      expect(subscription_class.exists?(record.id)).to be(true)
    end
  end

  describe "expiry" do
    it "refuses a confirmation after 48 hours and deletes the row, for GET and POST alike" do
      record, token = start!

      travel_to(Time.current + 49.hours) do
        get "/subscriptions/#{token}/confirm"
        expect(response).to have_http_status(:not_found)
      end
      expect(subscription_class.exists?(record.id)).to be(false)

      record, token = start!("second@example.org")
      travel_to(Time.current + 49.hours) do
        post "/subscriptions/#{token}/confirm"
        expect(response).to have_http_status(:not_found)
        expect(response.body).to include("This link is not valid")
      end
      expect(subscription_class.exists?(record.id)).to be(false)
    end

    it "still confirms inside the window" do
      record, token = start!

      travel_to(Time.current + 47.hours) { post "/subscriptions/#{token}/confirm" }

      expect(response).to have_http_status(:ok)
      expect(record.reload).to be_confirmed
    end

    it "does not expire a confirmed subscription" do
      record, token = start!
      post "/subscriptions/#{token}/confirm"

      travel_to(Time.current + 30.days) { post "/subscriptions/#{token}/confirm" }

      expect(response).to have_http_status(:ok)
      expect(subscription_class.exists?(record.id)).to be(true)
    end
  end

  describe "unsubscribing" do
    it "opens a page with a button on GET and deletes nothing" do
      record, = start!
      token = mailed_unsubscribe_token

      get "/subscriptions/#{token}/unsubscribe"

      expect(response).to have_http_status(:ok)
      form = Nokogiri::HTML(response.body).at_css("form[action='/subscriptions/#{token}/unsubscribe'] button")
      expect(form).to be_present
      expect(subscription_class.exists?(record.id)).to be(true)
    end

    it "deletes the row on POST (no flag is kept), from a pending or a confirmed subscription" do
      pending_record, = start!
      pending_token = mailed_unsubscribe_token
      confirmed_record, confirm_token = start!("confirmed@example.org")
      post "/subscriptions/#{confirm_token}/confirm"
      confirmed_token = mailed_unsubscribe_token

      post "/subscriptions/#{pending_token}/unsubscribe"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You are unsubscribed")
      post "/subscriptions/#{confirmed_token}/unsubscribe"

      expect(subscription_class.exists?(pending_record.id)).to be(false)
      expect(subscription_class.exists?(confirmed_record.id)).to be(false)
      expect(subscription_class.count).to eq(0)
    end

    it "treats the second use of an unsubscribe link as an invalid link, not an error" do
      start!
      token = mailed_unsubscribe_token
      post "/subscriptions/#{token}/unsubscribe"

      post "/subscriptions/#{token}/unsubscribe"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("already be unsubscribed")
    end

    it "accepts the mail client's one-click POST without a CSRF token, but still requires one for the other forms" do
      record, token = start!
      unsubscribe_token = mailed_unsubscribe_token
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      expect { post "/subscriptions/#{token}/confirm" }.to raise_error(ActionController::InvalidAuthenticityToken)
      expect { post "/subscriptions", params: { email: email } }.to raise_error(ActionController::InvalidAuthenticityToken)
      expect(record.reload.confirmed_at).to be_nil

      post "/subscriptions/#{unsubscribe_token}/unsubscribe", params: { "List-Unsubscribe" => "One-Click" }
      expect(response).to have_http_status(:ok)
      expect(subscription_class.exists?(record.id)).to be(false)
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  describe "rate limit" do
    it "refuses the fourth request for one address within the hour with 429, and sends no further mail" do
      3.times { |i| subscribe(email, { "q" => "term#{i}" }) }
      expect(response).to have_http_status(:ok)
      mails.clear

      subscribe(email, { "q" => "term-4" })

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("Too many requests")
      expect(subscription_class.count).to eq(3)
      expect(mails).to be_empty
    end

    it "counts the address case-insensitively and counts invalid attempts too" do
      subscribe("Reader@Example.org")
      subscribe("READER@example.org ")
      subscribe("reader@EXAMPLE.org")

      subscribe("reader@example.org")

      expect(response).to have_http_status(:too_many_requests)
    end

    it "refuses the eleventh request from one IP within the hour, whatever the addresses" do
      10.times { |i| subscribe("user#{i}@example.org") }
      expect(response).to have_http_status(:ok)

      subscribe("user11@example.org")

      expect(response).to have_http_status(:too_many_requests)
      expect(subscription_class.count).to eq(10)
    end

    it "lets another IP through" do
      10.times { |i| subscribe("user#{i}@example.org") }

      post "/subscriptions", params: { email: "other@example.org" }, headers: { "REMOTE_ADDR" => "198.51.100.7" }

      expect(response).to have_http_status(:ok)
    end

    it "frees the address again after the window" do
      3.times { |i| subscribe(email, { "q" => "term#{i}" }) }
      subscribe(email, { "q" => "again" })
      expect(response).to have_http_status(:too_many_requests)

      travel_to(Time.current + 61.minutes) { subscribe(email, { "q" => "again" }) }

      expect(response).to have_http_status(:ok)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance

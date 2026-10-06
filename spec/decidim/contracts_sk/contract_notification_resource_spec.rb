# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db spec for the notification-resource contract of Decidim::ContractsSk::
# Contract (civora-org/civora-platform#94, M03-05-C live fix).
#
# The live host answered GET /notifications with a 500 because Decidim's
# notification surfaces call resource.can_participate?(user) and the
# contract did not define it. This spec exercises the REAL decidim-core
# 0.31.7 classes on a contract notification, loaded by absolute path from
# the pinned gem (see the harness below): Decidim::Notification,
# NotificationPresenter, NotificationCell (its #show decision, title and
# action hooks), NotificationMailer, NotificationsDigestMailer and its
# presenter, the real event_received mail template, the real SimpleEvent
# hierarchy and the engine's ContractTransitionEvent, and the download-
# your-data serializer.
#
# What is NOT real: the cell's template rendering (the cells view stack
# needs a full Decidim app; the cell stand-in returns the chosen template
# name and the spec calls, one by one, the helpers those templates call)
# and the mail transport (the stand-in mailer returns its headers). The
# stand-ins are removed again after the group so the offline suite never
# sees them.
#
# Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "action_mailer"
require "erb"

# The harness defines and removes stand-in constants and carries state between
# before/after(:context) by design, and the examples assert several related
# facts per surface.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/InstanceVariable, RSpec/RemoveConst, Style/FormatStringToken
RSpec.describe Decidim::ContractsSk::Contract, :db do
  def core_path = Gem::Specification.find_by_name("decidim-core").full_gem_path

  # Defines the minimal stand-ins and loads the real pinned-gem classes.
  # Run once per group (before(:context): no DB needed, class-level only).
  before(:context) do # rubocop:disable RSpec/BeforeAfterAll
    @decidim_constants_before = Decidim.constants
    core = Gem::Specification.find_by_name("decidim-core").full_gem_path
    real = ->(path) { load File.join(core, path) }

    Decidim.module_eval do
      const_set(:SanitizeHelper, Module.new do
        # The real helper's included hook pulls in translated_attribute.
        def self.included(base) = base.include(Decidim::TranslatableAttributes)

        def decidim_html_escape(text) = ERB::Util.unwrapped_html_escape(text.to_str)

        def decidim_sanitize_translated(text) = text.to_s

        def decidim_sanitize(html, options = {})
          helpers = ActionController::Base.helpers
          options[:strip_tags] ? helpers.strip_tags(html) : helpers.sanitize(html)
        end
      end)
      const_set(:OrganizationHelper, Module.new)
      const_set(:ResourceHelper, Module.new)
      const_set(:Participable, Module.new)
      const_set(:Component, Class.new)
      const_set(:Comments, Module.new)
      const_get(:Comments).const_set(:CommentEvent, Module.new)
      const_set(:Core, Module.new)
      const_get(:Core).const_set(:Engine, Class.new do
        def self.routes = Struct.new(:url_helpers).new(Module.new)
      end)
      # Cell stand-in: #render answers the template name, which is all the
      # decision logic of NotificationCell#show needs.
      const_set(:ViewModel, Class.new do
        attr_reader :model

        def initialize(model, options = {})
          @model = model
          @options = options
        end

        def current_user = @options[:current_user]

        def render(template, **) = template

        def t(*, **) = I18n.t(*, **)
      end)
      # Mailer stand-in: the real mailer classes run, #mail returns headers.
      const_set(:ApplicationMailer, Class.new(ActionMailer::Base) do
        def with_user(_user) = yield

        def mail(**headers) = headers
      end)
    end

    real.call("app/helpers/decidim/component_path_helper.rb")
    %w[base_event email_event notification_event simple_event].each { |f| real.call("lib/decidim/events/#{f}.rb") }
    real.call("lib/decidim/download_your_data.rb")
    real.call("app/models/decidim/notification.rb")
    # Real Decidim derives the prefix from its module; the stand-in base does not.
    Decidim::Notification.table_name = "decidim_notifications"
    real.call("app/presenters/decidim/notification_presenter.rb")
    real.call("app/presenters/decidim/notification_to_mailer_presenter.rb")
    real.call("app/presenters/decidim/notifications_digest_presenter.rb")
    real.call("app/cells/decidim/notification_cell.rb")
    real.call("app/mailers/decidim/notification_mailer.rb")
    real.call("app/mailers/decidim/notifications_digest_mailer.rb")
    real.call("app/serializers/decidim/exporters/serializer.rb")
    real.call("lib/decidim/download_your_data_serializers/download_your_data_notification_serializer.rb")

    # The engine's event class, resolved the way the host does (autoload),
    # or loaded from its file when an earlier spec replaced the autoload.
    unless Decidim::ContractsSk.const_defined?(:ContractTransitionEvent, false)
      load File.expand_path("../../../app/events/decidim/contracts_sk/contract_transition_event.rb", __dir__)
    end

    I18n.backend.store_translations(:en,
                                    decidim: { user_conversations: { index: { time_ago: "%{time} ago" } },
                                               notifications: { show: { missing_event: "MISSING EVENT" } },
                                               events: { email_event: { email_greeting: "Hello %{user_name}," } } },
                                    time: { formats: { time_of_day: "%H:%M", decidim_short: "%d/%m/%Y %H:%M",
                                                       ddmm: "%d/%m", ddmmyyyy: "%d/%m/%Y" } })
  end

  after(:context) do # rubocop:disable RSpec/BeforeAfterAll
    (Decidim.constants - @decidim_constants_before).each { |name| Decidim.send(:remove_const, name) }
    if Decidim::ContractsSk.const_defined?(:ContractTransitionEvent, false)
      Decidim::ContractsSk.send(:remove_const, :ContractTransitionEvent)
    end
  end

  let(:event_class) { "Decidim::ContractsSk::ContractTransitionEvent" }
  let(:recipient) { Decidim::User.create!(organization: organization, name: "Test Recipient", email: "r@example.org") }
  let(:outsider_organization) { Decidim::Organization.create!(host: "other.example.org") }
  let(:outsider) { Decidim::User.create!(organization: outsider_organization, name: "Outsider", email: "o@example.org") }
  let(:contract) do
    described_class.create!(organization: organization, author: author, title: "Rekonštrukcia cesty <b>A&B</b>",
                            reference: "ZP-2026-001", state: "returned", review_reason: "Doplňte prílohu.")
  end
  let(:notification) do
    Decidim::Notification.create!(
      user: recipient, resource: contract, event_class: event_class,
      event_name: "decidim.events.contracts_sk.contract_returned",
      extra: { "reason" => "Doplňte prílohu.", "received_as" => "affected_user" }
    )
  end
  let(:organization) { Decidim::Organization.create!(host: "example.org", name: { "en" => "Org" }) }

  before do
    migrate_engine_schema!
    ActiveRecord::Base.connection.create_table :decidim_notifications do |t|
      t.timestamps
      t.bigint :decidim_user_id
      t.string :decidim_resource_type
      t.bigint :decidim_resource_id
      t.string :event_class
      t.string :event_name
      t.json :extra, default: {}
    end
    Decidim::Notification.reset_column_information
    # Columns the real mailers read that the stand-in tables do not carry.
    allow_any_instance_of(Decidim::Organization).to receive(:time_zone).and_return("UTC") # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Decidim::User).to receive(:notifications_sending_frequency).and_return("daily") # rubocop:disable RSpec/AnyInstance
    # The mounted engine's route proxy (real hosts mount the engine).
    allow(Rails.application.routes).to receive(:mounted_helpers).and_call_original
  end

  describe "#can_participate? (the method the live host was missing)" do
    it "is true for a user of the contract's organization" do
      expect(contract.can_participate?(recipient)).to be(true)
    end

    it "is false for nil" do
      expect(contract.can_participate?(nil)).to be(false)
    end

    it "is false for a user of another organization" do
      expect(contract.can_participate?(outsider)).to be(false)
    end

    it "is false for a contract without an organization id" do
      expect(described_class.new.can_participate?(recipient)).to be(false)
    end

    it "is false when neither side has an organization (nil never equals nil)" do
      orphan = Decidim::User.create!(name: "Orphan", email: "x@example.org")

      expect(described_class.new.can_participate?(orphan)).to be(false)
    end
  end

  describe "Decidim::Notification (notification.rb)" do
    it "answers can_participate? through the resource (line 41)" do
      expect(notification.can_participate?(recipient)).to be(true)
      expect(notification.can_participate?(outsider)).to be(false)
    end

    it "answers hidden_resource? and deleted_resource? (lines 49, 53) as false: a contract is neither" do
      expect([notification.hidden_resource?, notification.deleted_resource?]).to eq([false, false])
    end

    it "resolves the polymorphic resource and builds the event instance with the real SimpleEvent" do
      reloaded = Decidim::Notification.find(notification.id)

      expect(reloaded.resource).to eq(contract)
      expect(reloaded.event_class_instance).to be_a(Decidim::Events::SimpleEvent)
      expect(reloaded.user_role).to eq("affected_user")
    end
  end

  describe "Decidim::NotificationCell (notification_cell.rb)" do
    let(:cell) { Decidim::NotificationCell.new(notification, current_user: recipient) }

    it "chooses the show template for a recipient of the organization" do
      expect(cell.show).to eq(:show)
    end

    it "chooses not_available for a user of another organization" do
      expect(Decidim::NotificationCell.new(notification, current_user: outsider).show).to eq(:not_available)
    end

    it "chooses not_available for no user" do
      expect(Decidim::NotificationCell.new(notification, current_user: nil).show).to eq(:not_available)
    end

    it "renders the real notification title, not the missing-event fallback (line 20 rescues StandardError)" do
      title = cell.notification_title

      expect(title).not_to eq("MISSING EVENT")
      expect(title).to include("ZP-2026-001")
      expect(title).to include("Rekonštrukcia cesty &lt;b&gt;A&amp;B&lt;/b&gt;")
      expect(title).to include("Doplňte prílohu.")
      expect(title).to include("/admin/contracts/#{contract.id}/edit")
    end

    it "has no participatory-space link and no action cell (lines 24, 33, 37)" do
      expect(cell.participatory_space_link).to be_nil
      expect(cell.action_cell).to be_nil
    end

    it "serves the template helpers (show.erb lines 3, 6)" do
      presenter = cell.send(:notification)

      expect(presenter.created_at_in_words).to be_present
      expect(presenter.display_resource_text?).to be(false)
      expect(presenter.created_at.to_s).to be_present
    end
  end

  describe "the email path" do
    it "NotificationMailer#event_received builds the real event and its subject (notification_mailer.rb:13-14)" do
      mailer = Decidim::NotificationMailer.new
      headers = mailer.event_received("decidim.events.contracts_sk.contract_returned", event_class, contract,
                                      recipient, "affected_user", { "reason" => "Doplňte prílohu." })

      expect(headers).to eq(to: "r@example.org", subject: "Contract returned for changes: ZP-2026-001")
    end

    it "renders the real event_received template for a contract event" do
      event = Decidim::ContractsSk::ContractTransitionEvent.new(
        resource: contract, event_name: "decidim.events.contracts_sk.contract_returned", user: recipient,
        user_role: "affected_user", extra: { "reason" => "Doplňte prílohu." }
      )
      template = File.read(File.join(core_path, "app/views/decidim/notification_mailer/event_received.html.erb"))
      controller = Class.new(ActionController::Base) do
        include Decidim::SanitizeHelper
        helper_method :decidim_sanitize
      end

      html = controller.render(inline: template, assigns: { event_instance: event, organization: organization })

      expect(html).to include("ZP-2026-001")
      expect(html).to include("Doplňte prílohu.")
      expect(html).to include(%(href="http://example.org/admin/contracts/#{contract.id}/edit"))
      expect(html).to include("Test Recipient")
    end

    it "builds the digest through the real NotificationsDigestMailer and presenter" do
      notification
      mailer = Decidim::NotificationsDigestMailer.new
      headers = mailer.digest_mail(recipient, [notification.id])
      entries = mailer.instance_variable_get(:@notifications)

      expect(headers).to include(to: "r@example.org")
      expect(entries.size).to eq(1)
      entry = entries.first
      expect(entry.email_intro).to include("ZP-2026-001")
      expect(entry.resource_title).to include("Rekonštrukcia cesty")
      expect(entry.resource_path).to eq("/admin/contracts/#{contract.id}/edit")
      expect(entry.resource_url).to eq("http://example.org/admin/contracts/#{contract.id}/edit")
      expect(entry.date_time).to be_present
      expect(entry.show_extended_information?).to be(false)
      expect(entry.safe_resource_text).to eq("")
    end

    it "keeps a notification out of the digest for a user of another organization" do
      notification
      mailer = Decidim::NotificationsDigestMailer.new
      mailer.digest_mail(outsider, [notification.id])

      expect(mailer.instance_variable_get(:@notifications)).to eq([])
    end
  end

  describe "the download-your-data serializer" do
    it "serializes the notification from its own columns only" do
      data = Decidim::DownloadYourDataSerializers::DownloadYourDataNotificationSerializer.new(notification).serialize

      expect(data).to include(event_name: "decidim.events.contracts_sk.contract_returned", event_class: event_class)
      expect(data[:resource_type]).to eq(id: contract.id, type: "Decidim::ContractsSk::Contract")
    end
  end
end
# rubocop:enable RSpec/InstanceVariable, RSpec/RemoveConst, Style/FormatStringToken
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

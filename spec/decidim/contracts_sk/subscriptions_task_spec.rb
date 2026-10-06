# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Spec for the host-scheduled alert tasks (civora-org/civora-platform#121):
# the real task file runs in an isolated Rake application over the :db
# harness (`:environment` stubbed, like the demo-seed task spec). The output
# is counts and ids only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "rake"

# rubocop:disable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "decidim_contracts_sk:subscriptions tasks", :db do
  let(:subscription_class) { Decidim::ContractsSk::Subscription }

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "en", name: { "en" => "Green Village" })
    ActionMailer::Base.deliveries.clear
    Rake.application = Rake::Application.new
    load File.join(engine_root, "lib", "tasks", "decidim_contracts_sk_subscriptions.rake")
    Rake::Task.define_task(:environment)
  end

  def run_task(name, *args)
    task = Rake::Task["decidim_contracts_sk:subscriptions:#{name}"]
    task.reenable
    task.invoke(*args)
  end

  def subscribe!(org, email, created_at)
    token = subscription_class.generate_token
    subscription_class.create!(organization: org, email: email, filter_params: {}, locale: "en",
                               token_digest: subscription_class.digest(token), created_at: created_at)
  end

  it "delivers for the given organization and prints counts, never an address" do
    subscription = subscribe!(organization, "reader@example.org", 2.hours.ago)
    subscription.confirm!(1.hour.ago)
    Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published", published_at: 30.minutes.ago))

    expect { run_task(:deliver, organization.id.to_s) }
      .to output("organization #{organization.id}: purged=0 checked=1 delivered=1 failed=0\n").to_stdout
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "skips organizations other than the given one" do
    other = Decidim::Organization.create!(host: "other.example.org")
    subscribe!(other, "other@example.org", 2.hours.ago).confirm!(1.hour.ago)

    expect { run_task(:deliver, organization.id.to_s) }
      .to output("organization #{organization.id}: purged=0 checked=0 delivered=0 failed=0\n").to_stdout
  end

  it "runs for every organization without an argument" do
    other = Decidim::Organization.create!(host: "other.example.org")

    expect { run_task(:deliver) }.to output(/organization #{organization.id}:.*\norganization #{other.id}:/m).to_stdout
  end

  it "purges the expired unconfirmed subscriptions on request" do
    subscribe!(organization, "stale@example.org", 49.hours.ago)
    kept = subscribe!(organization, "recent@example.org", 1.hour.ago)

    expect { run_task(:purge_expired) }.to output("purged=1\n").to_stdout
    expect(subscription_class.all).to contain_exactly(kept)
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength

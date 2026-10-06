# frozen_string_literal: true

# E-mail alert subscriptions (civora-org/civora-platform#121): the
# host-scheduled delivery of the digests of newly published contracts. Run
# from the host app root, for one organization or for all:
#
#   bin/rails "decidim_contracts_sk:subscriptions:deliver[<organization_id>]"
#   bin/rails decidim_contracts_sk:subscriptions:deliver
#
# Schedule it (cron, the host's job runner) once a day, e.g. 07:00. It also
# deletes the unconfirmed subscriptions that passed their 48 hours. To purge
# only:
#
#   bin/rails decidim_contracts_sk:subscriptions:purge_expired
#
# Fail-soft: one failing subscription is logged (class and id only) and
# retried by the next run; the task exits 0 and prints counts. See
# docs/search-alerts.md.
#
# Privacy: output and logs carry counts and ids only, never an address.

namespace :decidim_contracts_sk do
  namespace :subscriptions do
    desc "Deliver the e-mail alert digests (all organizations, or the given organization id)"
    task :deliver, [:organization_id] => :environment do |_task, args|
      organizations = Decidim::Organization.all
      organizations = organizations.where(id: args[:organization_id].to_i) if args[:organization_id].present?

      organizations.find_each do |organization|
        summary = Decidim::ContractsSk::DeliverSubscriptionDigests.call(organization: organization)
        puts "organization #{organization.id}: purged=#{summary.purged} checked=#{summary.checked} " \
             "delivered=#{summary.delivered} failed=#{summary.failed}"
      end
    end

    desc "Delete the unconfirmed e-mail alert subscriptions older than 48 hours"
    task purge_expired: :environment do
      puts "purged=#{Decidim::ContractsSk::Subscription.purge_expired}"
    end
  end
end

# frozen_string_literal: true

# Morning CRZ deadline digest (civora-org/civora-platform#202): an e-mail to
# the admins and editors of each organization listing the contracts that are
# not yet effective because they are not confirmed as filed in the CRZ and
# whose deadline is overdue or near. Run from the host app root, for one
# organization or for all:
#
#   bin/rails "decidim_contracts_sk:crz_deadline_digest[<organization_id>]"
#   bin/rails decidim_contracts_sk:crz_deadline_digest
#
# Schedule it (cron, the host's job runner) once a day, on working days,
# e.g. 07:30. Nothing due, nothing sent. Fail-soft: a failing recipient is
# logged (class and id only) and counted; the task exits 0.
#
# Privacy: output and logs carry counts only, never an address.

namespace :decidim_contracts_sk do
  desc "Send the morning CRZ deadline digest (all organizations, or the given organization id)"
  task :crz_deadline_digest, [:organization_id] => :environment do |_task, args|
    organizations = Decidim::Organization.all
    organizations = organizations.where(id: args[:organization_id].to_i) if args[:organization_id].present?

    organizations.find_each do |organization|
      summary = Decidim::ContractsSk::DeliverCrzDeadlineDigest.call(organization: organization)
      puts "organization #{organization.id}: contracts=#{summary.contracts} recipients=#{summary.recipients} " \
           "delivered=#{summary.delivered} failed=#{summary.failed}"
    end
  end
end

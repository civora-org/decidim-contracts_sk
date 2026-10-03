# frozen_string_literal: true

# CRZ import sync (ADR-008, civora-org/civora-platform#86): the
# host-scheduled trigger for the idempotent ekosystem sync. Run from the
# host app root:
#
#   bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE>]"
#
# SINCE is an ISO8601 timestamp (the updated-since cursor seed); it may be
# passed as the second task argument or through the SINCE env variable:
#
#   SINCE=2026-09-08T00:00:00Z bin/rails "decidim_contracts_sk:crz_import:sync[1]"
#
# The import needs an actor for the audit rows and record authorship (both
# columns are NOT NULL by engine schema): by default the organization's
# first admin who accepted the admin terms is used; set ACTOR_EMAIL to pin
# a specific account. See docs/crz-import.md for operations, scheduling and
# failure modes.
#
# Scope (civora-org/civora-platform#145): only the organization's own
# contracts are mirrored — records whose parties carry its IČO, resolved
# through Decidim::ContractsSk.crz_organization_ico_resolver. Without a
# configured IČO the sync refuses to run (exit 1). Mirrors imported before
# the scoping existed are removed with the prune task:
#
#   bin/rails "decidim_contracts_sk:crz_import:prune_out_of_scope[<organization_id>]"            # dry run
#   CONFIRM=1 bin/rails "decidim_contracts_sk:crz_import:prune_out_of_scope[<organization_id>]"  # delete
#
# Privacy: the sync logs ids, statuses and counts only — never payloads or
# party names.

namespace :decidim_contracts_sk do
  namespace :crz_import do
    desc "Sync CRZ contract mirrors from ekosystem.slovensko.digital into one organization (SINCE env/arg = ISO8601)"
    task :sync, %i[organization_id since] => :environment do |_task, args|
      require "time"

      org_id = args[:organization_id].to_i
      unless org_id.positive?
        abort "Usage: rails \"decidim_contracts_sk:crz_import:sync[<organization_id>,<since ISO8601>]\" " \
              "(since also via the SINCE env variable)"
      end

      since = args[:since].presence || ENV["SINCE"].presence
      if since.blank?
        abort "A SINCE timestamp (ISO8601) is required — pass it as the second argument or via the SINCE env variable"
      end

      begin
        Time.iso8601(since)
      rescue ArgumentError
        abort "SINCE is not a valid ISO8601 timestamp: #{since}"
      end

      organization = Decidim::Organization.find_by(id: org_id)
      abort "Organization ##{org_id} not found" unless organization

      actor = import_actor!(organization)

      result = Decidim::ContractsSk::CrzImport::Sync.run(
        organization: organization, since: since, actor: actor
      )

      puts "CRZ import for organization ##{organization.id} (since #{since}):"
      puts "  created=#{result.created} updated=#{result.updated} unchanged=#{result.unchanged}"
      puts "  collisions=#{result.collisions} quarantined=#{result.quarantined} " \
           "failed=#{result.failed} skipped=#{result.skipped} out_of_scope=#{result.out_of_scope}"
      puts "  created ids: #{result.created_ids.join(", ")}" if result.created_ids.any?
      puts "  collision ids: #{result.collision_ids.join(", ")}" if result.collision_ids.any?
      puts "  quarantined source ids: #{result.quarantined_ids.compact.join(", ")}" if result.quarantined_ids.any?
      puts "  failed ids: #{result.failed_ids.compact.join(", ")}" if result.failed_ids.any?
      puts "  collisions must be resolved manually (docs/crz-import.md)." if result.collisions.positive?

      if result.error
        refused = result.error == Decidim::ContractsSk::CrzImport::Sync::NOT_CONFIGURED_MESSAGE
        warn "  sync #{refused ? "refused" : "stopped early"}: #{result.error}"
        exit 1
      end
    end

    desc "List (dry run) or delete (CONFIRM=1) CRZ mirrors that are not the organization's own contracts"
    task :prune_out_of_scope, %i[organization_id] => :environment do |_task, args|
      org_id = args[:organization_id].to_i
      unless org_id.positive?
        abort "Usage: rails \"decidim_contracts_sk:crz_import:prune_out_of_scope[<organization_id>]\""
      end

      organization = Decidim::Organization.find_by(id: org_id)
      abort "Organization ##{org_id} not found" unless organization

      ico = Decidim::ContractsSk.crz_organization_ico(organization)
      unless ico
        abort "No IČO configured for organization ##{org_id} (Decidim::ContractsSk.crz_organization_ico_resolver)"
      end

      pruned = Decidim::ContractsSk::CrzImport::Prune.call(organization: organization, ico: ico,
                                                           confirm: ENV["CONFIRM"] == "1")

      if pruned.confirmed
        puts "Deleted #{pruned.matched} out-of-scope CRZ mirror(s) from organization ##{org_id}."
      else
        puts "Dry run: #{pruned.matched} out-of-scope CRZ mirror(s) in organization ##{org_id} " \
             "(IČO #{ico} on neither party). Re-run with CONFIRM=1 to delete them."
      end
    end

    # The audit/authorship persona behind the sync: an explicit ACTOR_EMAIL
    # wins, otherwise the organization's first admin with accepted admin
    # terms (the default role_resolver's editor persona). No synthetic
    # users are fabricated.
    def import_actor!(organization)
      email = ENV["ACTOR_EMAIL"].presence
      user = email && Decidim::User.find_by(email: email, organization: organization)
      user ||= Decidim::User.where(organization: organization, admin: true)
                            .where.not(admin_terms_accepted_at: nil)
                            .order(:id).first

      unless user
        abort "No import actor for organization ##{organization.id} — " \
              "an admin with accepted admin terms must exist, or set ACTOR_EMAIL=<login email>"
      end

      user
    end
  end
end

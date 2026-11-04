# frozen_string_literal: true

# Contract templates (civora-org/civora-platform#211): load a fields-ready .docx
# as an active template of one organization, by hand, until there is an upload
# screen. Run from the host app root:
#
#   bin/rails "decidim_contracts_sk:templates:import[<org_id>,<path/to/file.docx>,<lineage_key>,<Template name>]"
#
# The file is linted and sanitized first; any lint error refuses it. Field types
# are guessed from the merge field names; an optional sidecar
# `<path>.fields.yml` marks person (personal data) fields, labels, groups and
# required fields. A re-import with the same lineage_key creates the next
# version, archives the older active one and carries the previous version's
# template settings (reference_pattern) over unless the sidecar sets them. See docs/contract-templates.md.
#
# Output lists field names and counts only, never any document content.

namespace :decidim_contracts_sk do
  namespace :templates do
    desc "Import a .docx as an active contract template: import[organization_id,path,lineage_key,name]"
    task :import, %i[organization_id path lineage_key name] => :environment do |_task, args|
      missing = %i[organization_id path lineage_key name].select { |key| args[key].blank? }
      abort "missing arguments: #{missing.join(", ")}" if missing.any?

      organization = Decidim::Organization.find_by(id: args[:organization_id])
      abort "organization #{args[:organization_id]} not found" unless organization

      begin
        result = Decidim::ContractsSk::Templates::Importer.call(
          organization: organization, path: args[:path], lineage_key: args[:lineage_key], name: args[:name]
        )
      rescue Decidim::ContractsSk::Templates::Importer::Error => e
        abort e.message
      end

      template = result.template
      puts "template #{template.id} (#{template.lineage_key} v#{template.version}) " \
           "is active with #{result.fields.size} fields"
      if result.previous_version
        carried = result.carried_over.map { |setting, value| "#{setting}=#{value}" }
        puts "carried over from v#{result.previous_version}: #{carried.presence&.join(", ") || "nothing to carry"}"
      end
      result.fields.each do |field|
        flags = [("personal" if field.personal_data), ("required" if field.required)].compact
        puts ["  #{field.key}: #{field.field_type}", flags.map { |f| "(#{f})" }.join(" ").presence].compact.join(" ")
      end
      result.warnings.each { |warning| puts "warning: #{warning.code}: #{warning.message}" }
    end
  end
end

# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Templates
      # The values of the two parties a contract template creates
      # (civora-org/civora-platform#211): the municipality from the header
      # profile and the counterparty from the fields the template declares
      # (`ContractTemplateField#party_part`). Pure: records in, hashes out; no
      # writes.
      #
      # Privacy rule, enforced here and nowhere else: a counterparty whose
      # name field is personal data is a natural person. Its party carries
      # only Party::NATURAL_PERSON_NAME; no value of any field is read for it,
      # so the name, address, birth date or birth number can never reach the
      # public parties table.
      module PartyValues
        # Roles are the catalogue's own vocabulary: the contracting body is the
        # "object" party, the other side the "contractor". The role titles of
        # the contract itself (predávajúci, kupujúci, prenajímateľ) live in
        # the document, not in the party.
        MUNICIPALITY_ROLE = "object"
        COUNTERPARTY_ROLE = "contractor"

        module_function

        def normalize_ico(value)
          value.to_s.gsub(/[[:space:]]/, "")
        end

        # { role:, name:, ico:, address: } or nil when the header names nothing.
        def municipality(profile, organization)
          name = profile&.header_value("official_name").presence || organization_name(organization)
          return unless name

          address = profile&.header_value("seat")
          { role: MUNICIPALITY_ROLE, name: name.to_s.truncate(255, omission: ""),
            ico: profile&.header_value("ico"), address: address&.truncate(255, omission: "") }
        end

        # Decidim keeps the organization name as a translated hash.
        def organization_name(organization)
          name = organization.name
          return name.to_s.presence unless name.is_a?(Hash)

          name[organization.default_locale.to_s].presence || name.values.find(&:present?)
        end

        # { role:, name:, ico:, address: } or nil when the template declares no
        # counterparty or the person left the name empty. `values` is the
        # non-personal canonical values of the form (key => string).
        def counterparty(template, values, personal_values)
          fields = template.counterparty_fields
          name_field = fields["name"]
          return unless name_field

          if name_field.personal_data
            return unless personal_values[name_field.key].to_s.strip.present?

            return { role: COUNTERPARTY_ROLE, name: Party::NATURAL_PERSON_NAME, ico: nil, address: nil }
          end

          company(fields, values, name_field)
        end

        def company(fields, values, name_field)
          name = values[name_field.key].to_s.strip
          return if name.empty?

          ico = normalize_ico(values[fields["ico"]&.key]).presence
          address = values[fields["address"]&.key].to_s.strip.presence
          { role: COUNTERPARTY_ROLE, name: name.truncate(255, omission: ""),
            ico: (ico if ICO_FORMAT.match?(ico.to_s)), address: address&.truncate(255, omission: "") }
        end
      end
    end
  end
end

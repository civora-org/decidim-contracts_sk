# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Templates
      # The naming conventions that tell the generator which merge fields a
      # person never types (civora-org/civora-platform#211). Pure: field keys
      # in, answers out; no records are read.
      #
      # A template author needs only to NAME a merge field:
      #
      #   cislo_zmluvy, interne_cislo, internal_number   the internal number
      #   org_ico, org_nazov, ...                        the organization header
      #   <money field>_slovom, <money field>_words      the amount in words
      #
      # Everything else is asked for in the form. Contract amount and signing
      # date are taken from the first money / date field with a well-known name,
      # so the contract record is filled from the same entry.
      module TemplateFields
        INTERNAL_NUMBER_KEYS = %w[cislo_zmluvy interne_cislo internal_number].freeze
        WORDS_SUFFIXES = %w[_slovom _words].freeze

        # Template key => ContractOrganizationProfile header key. A key
        # "org_<header key>" (org_ico, org_seat) maps to itself.
        ORG_HEADER_ALIASES = {
          "org_nazov" => "official_name", "org_sidlo" => "seat", "org_adresa" => "seat",
          "org_banka" => "bank_name", "org_statutar" => "statutory_name",
          "org_statutar_funkcia" => "statutory_title", "org_miesto_podpisu" => "signing_place"
        }.freeze

        AMOUNT_KEYS = %w[suma_celkom cena_celkom celkova_cena suma cena kupna_cena].freeze
        SIGNED_ON_KEYS = %w[datum_podpisu datum_uzavretia datum_zmluvy signed_on].freeze

        module_function

        def internal_number_key?(key)
          INTERNAL_NUMBER_KEYS.include?(key.to_s)
        end

        # The header key behind a template key, or nil when the key is not an
        # organization header field.
        def org_header_key(key)
          name = key.to_s
          return ORG_HEADER_ALIASES[name] if ORG_HEADER_ALIASES.key?(name)

          candidate = name.delete_prefix("org_")
          candidate if name.start_with?("org_") && ContractOrganizationProfile::HEADER_KEYS.include?(candidate)
        end

        def words_suffix?(key)
          WORDS_SUFFIXES.any? { |suffix| key.to_s.end_with?(suffix) && key.to_s.length > suffix.length }
        end

        # The money field a "...slovom" field spells out: the field named like
        # it without the suffix, else the only money field of the template.
        # nil when there is none (the field is then asked for like any other).
        def words_source(words_field, fields)
          return unless words_suffix?(words_field.key)

          base = WORDS_SUFFIXES.filter_map do |s|
            words_field.key.delete_suffix(s) if words_field.key.end_with?(s)
          end.first
          money = fields.select { |f| f.field_type.to_s == "money" && f != words_field }
          money.find { |f| f.key == base } || (money.one? ? money.first : nil)
        end

        # The fields a person fills in: everything except the organization
        # header, the internal number and the spelled-out amounts.
        def input_fields(fields)
          fields.reject do |field|
            header_field?(field) || internal_number_key?(field.key) || words_source(field, fields)
          end
        end

        def header_fields(fields)
          fields.select { |field| header_field?(field) }
        end

        def words_fields(fields)
          fields.select { |field| words_source(field, fields) }
        end

        def header_field?(field)
          field.field_type.to_s == "org_header" && !org_header_key(field.key).nil?
        end

        def amount_field(fields)
          pick(fields, "money", AMOUNT_KEYS)
        end

        def signed_on_field(fields)
          pick(fields, "date", SIGNED_ON_KEYS)
        end

        def pick(fields, type, keys)
          typed = fields.select { |field| field.field_type.to_s == type }
          keys.each do |key|
            found = typed.find { |field| field.key == key }
            return found if found
          end
          nil
        end
      end
    end
  end
end

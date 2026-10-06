# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for creating and updating contract templates
      # (civora-org/civora-platform#127).
      #
      # Deliberately narrow: only the template's own content (name, title
      # pattern, subject matter, currency and the object-party skeleton) is
      # exposed. The organization is never form input - the controller's
      # tenant context supplies it - so a param cannot move a template to
      # another tenant. The validations mirror the Template model's, so a
      # rejection surfaces on the form before the command boundary; the
      # per-organization name uniqueness needs the database and is reported
      # by the commands (they add the :taken error to this form).
      class TemplateForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :name, :string
        attribute :title_pattern, :string
        attribute :subject_matter, :string
        attribute :currency, :string, default: "EUR"
        attribute :object_party_name, :string
        attribute :object_party_ico, :string
        attribute :object_party_address, :string

        validates :name, presence: true, length: { maximum: 255 }
        validates :title_pattern, length: { maximum: 255 }, allow_nil: true
        validates :currency, inclusion: { in: Decidim::ContractsSk::Contract::SUPPORTED_CURRENCIES }
        validates :object_party_name, presence: true, if: :party_details?
        validates :object_party_name, :object_party_address, length: { maximum: 255 }, allow_nil: true
        validates :object_party_ico, length: { is: 8 },
                                     format: { with: Decidim::ContractsSk::ICO_FORMAT },
                                     allow_blank: true

        private

        def party_details?
          object_party_ico.present? || object_party_address.present?
        end
      end
    end
  end
end

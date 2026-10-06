# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The form-sourced attribute set shared by the template commands.
      module TemplateAttributes
        def self.from(form)
          {
            name: form.name.to_s.strip, title_pattern: form.title_pattern,
            subject_matter: form.subject_matter, currency: form.currency,
            object_party_name: form.object_party_name,
            object_party_ico: form.object_party_ico,
            object_party_address: form.object_party_address
          }
        end

        # Adds the :taken error to the form's name when the failure was the
        # per-organization name uniqueness (the model validation, or the
        # unique index when two requests race past it); any other failure
        # leaves the form as it is.
        def self.flag_taken(form, error)
          taken = error.is_a?(ActiveRecord::RecordNotUnique) ||
                  (error.is_a?(ActiveRecord::RecordInvalid) && error.record.errors.of_kind?(:name, :taken))
          form.errors.add(:name, :taken) if taken
        end
      end
    end
  end
end

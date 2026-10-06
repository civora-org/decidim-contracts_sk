# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Creates a contract template from the admin form
      # (civora-org/civora-platform#127).
      #
      # The organization is a command input taken from the controller's
      # tenant context, never from the form. A name already used in the
      # organization (the model validation, or the unique index when two
      # requests race) answers :invalid with the :taken error added to the
      # form, so the re-render says why.
      class CreateTemplate < Decidim::Command
        def initialize(form, organization:)
          super()
          @form = form
          @organization = organization
        end

        def call
          return broadcast(:invalid) unless form.valid?

          broadcast(:ok, Template.create!(organization: organization, **TemplateAttributes.from(form)))
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          TemplateAttributes.flag_taken(form, e)
          broadcast(:invalid)
        end

        private

        attr_reader :form, :organization
      end
    end
  end
end

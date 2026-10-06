# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Updates a contract template in place (civora-org/civora-platform#127).
      #
      # The controller loads the template from the organization's scope, so
      # it is tenant-scoped by construction. The write runs inside the row
      # lock (the repo-wide discipline): with_lock reloads the row first, so
      # a template removed in the meantime answers :invalid instead of being
      # resurrected by a stale in-memory copy, and it serializes against a
      # contract being created from the same template. Contracts created
      # earlier are copies and are never touched.
      class UpdateTemplate < Decidim::Command
        def initialize(form, template)
          super()
          @form = form
          @template = template
        end

        def call
          return broadcast(:invalid) unless form.valid?

          template.with_lock { template.update!(TemplateAttributes.from(form)) }

          broadcast(:ok, template)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotFound => e
          TemplateAttributes.flag_taken(form, e)
          broadcast(:invalid)
        end

        private

        attr_reader :form, :template
      end
    end
  end
end

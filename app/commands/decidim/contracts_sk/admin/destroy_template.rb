# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes a contract template (civora-org/civora-platform#127).
      #
      # Contracts keep no reference to the template they were created from,
      # so removal never touches a contract. The destroy runs inside the row
      # lock: a template already removed by a concurrent request fails the
      # reload and answers :invalid (the index then shows the truth).
      class DestroyTemplate < Decidim::Command
        def initialize(template)
          super()
          @template = template
        end

        def call
          template.with_lock { template.destroy! }

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordNotFound
          broadcast(:invalid)
        end

        private

        attr_reader :template
      end
    end
  end
end

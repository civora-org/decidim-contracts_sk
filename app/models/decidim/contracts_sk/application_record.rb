# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Abstract base record for all ContractsSk models.
    #
    # Approved design decisions (civora-org/civora-platform#37):
    # - No default_scope for tenant isolation: tenant scoping happens on
    #   concrete models via their organization association plus query
    #   object scoping, matching Decidim core conventions.
    # - No associations on this base class: belongs_to :organization and
    #   other associations belong on concrete models.
    class ApplicationRecord < Decidim::ApplicationRecord
      self.abstract_class = true

      # In a mounted app, railties also defines table_name_prefix on the
      # Decidim::ContractsSk namespace module (isolate_namespace) and resolves
      # that method first for nested models. Both values agree by convention.
      self.table_name_prefix = "decidim_contracts_sk_"
    end
  end
end

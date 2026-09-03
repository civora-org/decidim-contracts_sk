# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Base controller for the Decidim ContractsSk module.
    # Common behaviour shared by public and admin controllers.
    class ApplicationController < Decidim::ApplicationController
      helper Decidim::ContractsSk::ApplicationHelper

      def permission_class_chain
        [Decidim::ContractsSk::Permissions, *super]
      end
    end
  end
end

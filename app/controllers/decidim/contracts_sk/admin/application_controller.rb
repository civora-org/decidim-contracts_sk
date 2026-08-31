# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Base controller for the admin namespace of the ContractsSk module.
      # Requires an authenticated user for all admin actions.
      class ApplicationController < Decidim::ContractsSk::ApplicationController
        before_action :authenticate_user!
      end
    end
  end
end

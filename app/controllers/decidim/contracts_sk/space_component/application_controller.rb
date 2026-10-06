# frozen_string_literal: true

module Decidim
  module ContractsSk
    module SpaceComponent
      # Base controller of the in-space (component) surface (civora-org/
      # civora-platform#89). Inherits Decidim's component base controller,
      # which supplies everything a component page needs: the component and
      # space context (current_component, current_participatory_space), the
      # component settings readers, the space-visibility gate
      # (authorize_participatory_space, redirect_unless_feature_private), the
      # space layout and breadcrumbs, and the permission chain that starts
      # with the manifest's permissions class
      # (decidim-core components/base_controller.rb:8-76).
      class ApplicationController < Decidim::Components::BaseController
        # Formatting helpers shared with the standalone catalogue's views
        # (dates, amounts, provenance), which the in-space views reuse.
        helper Decidim::ContractsSk::ApplicationHelper
      end
    end
  end
end

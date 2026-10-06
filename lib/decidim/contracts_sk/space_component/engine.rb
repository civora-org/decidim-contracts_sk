# frozen_string_literal: true

require "rails/engine"

module Decidim
  module ContractsSk
    # The in-space (component) surface of the engine (civora-org/civora-platform
    # #89). Everything about contracts living INSIDE a Decidim participatory
    # space is namespaced here, apart from the standalone mounted catalogue
    # (Decidim::ContractsSk::Engine, mounted by the host at its own path).
    # Registering the component is purely additive: the standalone engine, its
    # routes and its controllers are untouched, and nothing in this namespace
    # is reachable unless a space admin adds the component to a space.
    module SpaceComponent
      # The engine Decidim mounts for every component instance, under the
      # space's component scope (decidim-participatory_processes
      # engine.rb:33-39 and decidim-assemblies engine.rb:32-38:
      # `mount manifest.engine, at: "/"` inside
      # `scope ".../f/:component_id"`).
      #
      # It is deliberately a SECOND, minimal engine instead of the standalone
      # one mounted again: the standalone engine's route table carries the
      # whole admin namespace and the open-data export, the Atom feed and the
      # sitemap, none of which belong in a participatory space (the admin
      # stays organization-scoped in the standalone engine). The route table
      # below is the complete in-space surface: the list and the detail page,
      # both read-only.
      #
      # Same pattern as the pinned gems' own admin engines
      # (decidim-pages admin_engine.rb:7-21): the engine shares the gem root
      # with the standalone engine, so everything it must not repeat is
      # switched off here (migrations, rake tasks, seeds, and the root
      # config/routes.rb that draws the standalone engine's routes).
      class Engine < ::Rails::Engine
        isolate_namespace Decidim::ContractsSk::SpaceComponent

        paths["db/migrate"] = nil
        paths["lib/tasks"] = nil
        paths["config/routes.rb"] = nil

        # `root` is REQUIRED by Decidim: the space menu and the breadcrumbs
        # link the component through
        # Decidim::EngineRouter.main_proxy(component).root_path
        # (decidim-core component_path_helper.rb:11-14).
        routes do
          root to: "contracts#index"
          resources :contracts, only: :show
        end

        def load_seed
          nil
        end
      end
    end
  end
end

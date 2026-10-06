# frozen_string_literal: true

# Registers the contracts component with Decidim (civora-org/civora-platform
# #89), so a space admin can add "Contracts" to a participatory process or
# assembly. Required from the engine's `decidim_contracts_sk.component`
# initializer (a host has Decidim loaded by then), exactly once.
#
# What the component IS (see docs/decidim-component.md): a presentation lens
# over the organization's published contracts. Contracts carry no component
# or space reference (ADR-009, no decidim_component_id column), so the
# component lists the SAME records as the standalone catalogue; admin CRUD
# stays organization-scoped in the standalone engine.
#
# Manifest attributes deliberately left at Decidim's defaults, and why:
# * admin_engine, exports, imports, stats, seeds, hooks: the component owns no
#   data, so there is nothing to manage per component, export, count, seed or
#   clean up (a destroyed component leaves every contract untouched);
# * query_type: the generic Decidim::Core::ComponentType (no contract data in
#   the GraphQL API);
# * data_portable_entities / newsletter_participant_entities: contracts are
#   organization records, not user-generated content, so there is no personal
#   data to export and no participants to mail;
# * actions: the component has no authorizable action (read-only);
# * component_form_class_name: the stock admin component form.
# `icon` is omitted on purpose: it must name an SVG in the host's compiled
# asset bundle, and a missing entry raises Shakapacker::Manifest::
# MissingEntryError in the admin component list (shakapacker manifest.rb
# lookup!); Decidim falls back to its generic icon when the attribute is
# blank (decidim-core icon_helper.rb:26-31).
Decidim.register_component(:contracts_sk) do |component|
  component.engine = Decidim::ContractsSk::SpaceComponent::Engine
  component.icon_key = "file-text-line"
  component.permissions_class_name = "Decidim::ContractsSk::Permissions"

  # The announcement is the whole settings surface. Both scopes are declared
  # because decidim-core's shared announcement partial reads BOTH
  # `current_settings` (step) and `component_settings` (global)
  # (_component_announcement.html.erb:1): a missing :step schema would raise
  # NoMethodError at render.
  component.settings(:global) do |settings|
    settings.attribute :announcement, type: :text, translated: true, editor: true
  end

  component.settings(:step) do |settings|
    settings.attribute :announcement, type: :text, translated: true, editor: true
  end
end

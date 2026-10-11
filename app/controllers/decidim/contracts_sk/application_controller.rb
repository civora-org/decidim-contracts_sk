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

      # The URL of the current page in another locale: what decidim-core's
      # layout head renders as <link rel="alternate" hreflang> (Decidim 0.32;
      # 0.31 builds those links itself and never calls this) and what
      # Decidim::LocalesController redirects to.
      #
      # Decidim 0.32 answers with a PATH PREFIX (`/sk/zmluvy/5`), which only
      # exists where the host mounted the engine inside `scope "/:locale"`.
      # There the request's SCRIPT_NAME starts with the locale and Decidim's
      # answer is right, so it is kept. Everywhere else (the engine mounted
      # un-prefixed, e.g. `at: "/zmluvy"`, the shape every 0.31 host has) the
      # prefixed URL would be a 404, so the locale goes where this engine
      # reads it: the `locale` query parameter (civora-org/civora-platform#183).
      def canonical_url(desired_url, target_locale = default_locale)
        return super if locale_prefixed_mount? && defined?(super)

        uri = URI(desired_url.to_s)
        params = URI.decode_www_form(uri.query.to_s).reject { |key, _| key == "locale" }
        uri.query = URI.encode_www_form(params << ["locale", target_locale.to_s])
        uri.to_s
      end

      private

      # True when the engine is mounted below a locale segment, i.e. the
      # request's script name starts with an available locale.
      def locale_prefixed_mount?
        first_segment = request.script_name.to_s.split("/").compact_blank.first
        available_locales.map(&:to_s).include?(first_segment)
      end
    end
  end
end

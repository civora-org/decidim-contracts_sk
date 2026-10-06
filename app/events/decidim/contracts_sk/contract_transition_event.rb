# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Thin Decidim event for contract lifecycle notifications
    # (civora-org/civora-platform#94, M03-05-A / #104). A contract is not
    # inside a Decidim component, so the default URL lookup is replaced and
    # the i18n scope is moved under decidim.contracts_sk. All decisions live
    # in TransitionNotification; this class is verified on the host (#107),
    # the offline suite cannot load Decidim::Events::SimpleEvent.
    class ContractTransitionEvent < Decidim::Events::SimpleEvent
      # The mounted-engine route proxy (`decidim_contracts_sk`), the same
      # include Decidim's own events use (e.g. ProposalNoteCreatedEvent).
      # `Rails.application.routes.url_helpers` has no such proxy and would
      # also drop the host's mount prefix.
      include Rails.application.routes.mounted_helpers

      # Engine-owned scope instead of the event name.
      def i18n_scope
        TransitionNotification.i18n_scope(event_name)
      end

      # Recipients are editors/reviewers and unpublished contracts have no
      # public page, so the link targets the admin edit page.
      def resource_path
        @resource_path ||= decidim_contracts_sk.edit_admin_contract_path(resource)
      end

      def resource_url
        @resource_url ||= decidim_contracts_sk.edit_admin_contract_url(resource, host: resource.organization.host)
      end

      # The title is a plain string column. The texts are html_safe, so the
      # value is HTML-escaped here (Decidim's default sanitizes for the same
      # reason).
      def resource_title
        decidim_html_escape(resource.title.to_s)
      end

      # Reference and the reviewer's reason are the only extras (privacy rule
      # of #94: no amounts, parties or document names). The reason is free
      # text typed by a reviewer, hence escaped like the title.
      def i18n_options
        super.merge(
          reference: decidim_html_escape(resource.reference.to_s),
          reason: decidim_html_escape(extra[:reason].to_s)
        )
      end
    end
  end
end

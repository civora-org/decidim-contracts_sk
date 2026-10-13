# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The morning e-mail of the CRZ deadline digest (civora-org/civora-platform
    # #202): to ONE admin or editor of an organization, the contracts that are
    # not yet effective because they are not confirmed as filed in the CRZ and
    # whose deadline is overdue or near (the same set as the admin home's
    # "Lehoty CRZ" group, Contract.crz_attention).
    #
    # Privacy: titles and reference numbers only. Never parties, amounts or
    # any other record data, in case a mailbox is shared. Everything is
    # interpolated with plain ERB (escaped); no `_html` translation and no
    # html_safe on a value that came from a contract.
    #
    # The mailer assumes there is something to say: who sends and when is
    # decided by DeliverCrzDeadlineDigest (nothing due, nothing sent).
    class CrzDeadlineDigestMailer < Decidim::ApplicationMailer
      include Rails.application.routes.mounted_helpers

      helper Decidim::ContractsSk::ApplicationHelper

      # +contracts+ is the (capped) list, most overdue first; +total+ counts
      # all of them.
      def digest(user, organization, contracts, total, today: Date.current)
        I18n.with_locale(user.try(:locale).presence || organization.default_locale) do
          assign(organization, contracts, total, today)
          mail(to: user.email,
               subject: t("decidim.contracts_sk.crz_deadline_digest_mailer.digest.subject",
                          organization: @organization_name))
        end
      end

      private

      def assign(organization, contracts, total, today)
        @organization = organization
        @organization_name = display_name(organization)
        @today = today
        @total = total
        @more = total - contracts.size
        @overdue, @due_soon = contracts.partition { |c| c.crz_deadline_status(today: today) == :overdue }
        @contract_urls = contracts.to_h { |contract| [contract.id, engine_url(:admin_contract_url, contract)] }
        @overview_url = engine_url(:admin_root_url)
      end

      # The organization's name in the current locale (the plain-data twin of
      # Decidim's organization_name helper, so the mailer does not depend on
      # which mailer base class a host's Decidim provides).
      def display_name(organization)
        names = organization.name
        return organization.host.to_s unless names.is_a?(Hash)

        names[I18n.locale.to_s].presence || names[organization.default_locale.to_s].presence ||
          names.values.grep(String).first.to_s
      end

      # Absolute URL on the organization's host, in the recipient's locale.
      def engine_url(helper, *args)
        decidim_contracts_sk.public_send(helper, *args, host: @organization.host, locale: I18n.locale)
      end
    end
  end
end

# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Public catalogue scaffold controller (civora-org/civora-platform#46).
    #
    # Renders localized placeholder responses until the Contract domain
    # model and real views land (M01-02). No model dependency by design.
    class ContractsController < Decidim::ContractsSk::ApplicationController
      def index
        render plain: t("decidim.contracts_sk.contracts.index.title")
      end

      def show
        render plain: t("decidim.contracts_sk.contracts.show.title")
      end
    end
  end
end

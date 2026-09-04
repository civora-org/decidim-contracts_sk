# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for creating and updating contract records
      # (civora-org/civora-platform#58).
      #
      # Deliberately narrow: only the editorial identity fields (title,
      # reference) are exposed. The lifecycle state, provenance metadata,
      # organization and author are set by the command layer / persistence
      # defaults — a form param can never influence them (strong params in
      # the controller mirror this allow-list).
      class ContractForm
        include ActiveModel::Model

        attr_accessor :title, :reference

        validates :title, presence: true, length: { maximum: 255 }
        validates :reference, presence: true, length: { maximum: 255 }
      end
    end
  end
end

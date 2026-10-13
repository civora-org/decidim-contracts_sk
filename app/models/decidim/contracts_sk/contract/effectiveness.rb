# frozen_string_literal: true

module Decidim
  module ContractsSk
    class Contract < ApplicationRecord
      # The effectiveness of a contract that must be published in the CRZ
      # (civora-org/civora-platform#202, § 47a OZ) and the set of contracts
      # whose CRZ deadline needs attention. All derived, nothing stored but
      # the optional +agreed_effective_on+ date; the rule lives in
      # CrzDeadline.effectiveness.
      module Effectiveness
        extend ActiveSupport::Concern

        included do
          # Tracked records whose deadline is overdue or near: the one
          # definition of "needs attention" shared by the admin home and the
          # morning digest e-mail.
          scope :crz_attention, lambda { |today = Date.current|
            crz_overdue(today).or(crz_due_soon(today))
          }
        end

        # :not_applicable, :not_effective ("zatiaľ neúčinná") or :effective.
        def crz_effectiveness(today: Date.current)
          CrzDeadline.effectiveness(self, today: today)
        end

        # The day the contract takes effect; nil until the filing is
        # confirmed.
        def crz_effective_on
          CrzDeadline.effective_on(self)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for a contract's parties
      # (civora-org/civora-platform#76).
      #
      # Deliberately narrow: only the party's role, name, company number
      # (IČO) and address are exposed. The parent contract is never form
      # input — the controller loads it from the tenant scope and the
      # command layer creates through its parties association, so the
      # tenancy cannot be influenced by a form param (strong params in the
      # controller mirror this allow-list).
      #
      # Multiple parties with the same role are legal — a contract may name
      # several contractors (or several objects), so there is deliberately
      # no uniqueness validation on any axis here.
      #
      # Fields are declared through ActiveModel::Attributes so the raw
      # string params cast at the form boundary, mirroring the model's
      # column types (all four are strings). The validations mirror the
      # Party model's exactly, so a rejection surfaces on the form before
      # the command boundary: the role must come from the model's frozen
      # ROLES vocabulary, the name is required (max 255), the IČO is either
      # blank or exactly 8 digits, and the address is capped at 255.
      class PartyForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :role, :string
        attribute :name, :string
        attribute :ico, :string
        attribute :address, :string

        validates :role, presence: true,
                         inclusion: { in: Decidim::ContractsSk::Party::ROLES }
        validates :name, presence: true, length: { maximum: 255 }
        validates :ico, length: { is: 8 },
                        format: { with: /\A\d{8}\z/ },
                        allow_blank: true
        validates :address, length: { maximum: 255 }, allow_nil: true
      end
    end
  end
end

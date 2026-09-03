# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A document attached to a contract record — catalogue copy, CRZ export,
    # annex or other supporting material.
    #
    # Metadata only for now: file_name/content_type/file_size describe the
    # attachment; validated upload handling arrives with M02-05-A
    # (civora-org/civora-platform#64). Like Party, tenancy is derived through
    # the contract's organization.
    class Document < ApplicationRecord
      # Stored-string kind vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      KINDS = %w[contract crz_export annex other].freeze

      # Symbol => stored String mapping for the Rails enum, mirroring
      # Contract's STATE_VALUES style.
      KIND_VALUES = KINDS.to_h { |kind| [kind, kind] }.freeze

      belongs_to :contract

      validates :kind, presence: true,
                       inclusion: { in: KINDS }
      validates :title, presence: true, length: { maximum: 255 }

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). Column and enum agree on the
      # "contract" default.
      enum :kind, KIND_VALUES, default: "contract"
    end
  end
end

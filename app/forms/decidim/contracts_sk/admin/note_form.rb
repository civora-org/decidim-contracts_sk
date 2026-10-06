# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Form for adding an internal review note (civora-org/civora-platform
      # #128). Only the body is form input: the contract comes from the route
      # and the tenant scope, the author from the signed-in user, never from
      # a param. The body is stripped on assignment so surrounding blanks
      # neither count against the cap nor turn an empty note into a valid one.
      class NoteForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :body, :string

        validates :body, presence: true, length: { maximum: Note::MAX_BODY_LENGTH }

        def body=(value)
          super(value.is_a?(String) ? value.strip : value)
        end
      end
    end
  end
end

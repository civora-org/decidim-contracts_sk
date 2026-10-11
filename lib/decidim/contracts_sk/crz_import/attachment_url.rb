# frozen_string_literal: true

module Decidim
  module ContractsSk
    module CrzImport
      # The single place a CRZ attachment link is built
      # (civora-org/civora-platform#189). The engine only LINKS to the
      # official files on crz.gov.sk, it never downloads or stores them.
      #
      # A URL is produced only from a file name that matches a strict
      # allowlist: digits, one dot, a known document extension. Anything else
      # (path separators, query strings, schemes, whitespace, unknown
      # extensions, absent values) yields nil, so an arbitrary payload string
      # can never reach an href. The mapper drops such files at import time
      # and the model re-checks at render time (defense in depth).
      module AttachmentUrl
        BASE_URL = "https://www.crz.gov.sk/data/att/"

        EXTENSIONS = %w[pdf doc docx xls xlsx ppt pptx odt ods odp rtf txt zip jpg jpeg png tif tiff xml].freeze

        # \A..\z, never ^..$: a newline-smuggled second line must not pass.
        FILE_NAME_PATTERN = /\A\d{1,20}\.(?:#{EXTENSIONS.join("|")})\z/i

        # True for a well-formed attachment file name.
        def self.allowed?(file_name)
          file_name.is_a?(String) && FILE_NAME_PATTERN.match?(file_name)
        end

        # The official file URL, or nil when the name is not allowlisted.
        def self.for(file_name)
          allowed?(file_name) ? "#{BASE_URL}#{file_name}" : nil
        end
      end
    end
  end
end

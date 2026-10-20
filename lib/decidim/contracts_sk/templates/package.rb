# frozen_string_literal: true

require "stringio"
require "zip"

module Decidim
  module ContractsSk
    module Templates
      # Bounded, in-memory reader and writer for an OOXML (.docx) zip package
      # (civora-org/civora-platform#211). Everything operates on bytes: nothing
      # is extracted to disk, so entry names are never used as paths.
      #
      # Zip-bomb guard: the input size, the entry count and the uncompressed
      # size (per entry and in total) are capped, and the uncompressed size is
      # counted while reading rather than trusted from the zip header, which an
      # attacker controls.
      module Package
        MAX_INPUT_BYTES = 25 * 1024 * 1024
        MAX_ENTRIES = 1_000
        MAX_ENTRY_BYTES = 32 * 1024 * 1024
        MAX_TOTAL_BYTES = 96 * 1024 * 1024
        CHUNK = 64 * 1024

        # code is one of :not_a_zip, :too_large, :too_many_entries, :entry_too_large, :total_too_large
        class Error < StandardError
          attr_reader :code

          def initialize(code, message = code.to_s)
            @code = code
            super(message)
          end
        end

        module_function

        # Ordered Hash of entry name => binary String. Directory entries are skipped.
        def read(bytes)
          raise Error.new(:not_a_zip, "input is not a byte string") unless bytes.is_a?(String)
          raise Error.new(:too_large, "package exceeds #{MAX_INPUT_BYTES} bytes") if bytes.bytesize > MAX_INPUT_BYTES

          entries = {}
          total = 0
          Zip::File.open_buffer(StringIO.new(bytes.b)) do |zip|
            raise Error.new(:too_many_entries, "more than #{MAX_ENTRIES} entries") if zip.size > MAX_ENTRIES

            zip.each do |entry|
              next if entry.directory?

              data = read_entry(entry)
              total += data.bytesize
              if total > MAX_TOTAL_BYTES
                raise Error.new(:total_too_large,
                                "uncompressed size exceeds #{MAX_TOTAL_BYTES} bytes")
              end

              entries[entry.name] = data
            end
          end
          entries
        rescue Zip::Error, EOFError, SystemCallError, Zlib::Error
          raise Error.new(:not_a_zip, "unreadable zip package")
        end

        # Binary String for a Hash of name => bytes ([Content_Types].xml first,
        # as Word writes it).
        def write(entries)
          ordered = entries.sort_by { |name, _| name == "[Content_Types].xml" ? 0 : 1 }
          io = Zip::OutputStream.write_buffer(StringIO.new(+"".b)) do |zip|
            ordered.each do |name, data|
              zip.put_next_entry(name)
              zip.write(data)
            end
          end
          io.string
        end

        def read_entry(entry)
          out = +"".b
          entry.get_input_stream do |io|
            while (chunk = io.read(CHUNK))
              out << chunk
              if out.bytesize > MAX_ENTRY_BYTES
                raise Error.new(:entry_too_large,
                                "an entry exceeds #{MAX_ENTRY_BYTES} bytes")
              end
            end
          end
          out
        end
      end
    end
  end
end

# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../pdf_converter"

module Decidim
  module ContractsSk
    module Templates
      module PdfConverter
        # The private working directory of one conversion.
        ConversionWorkspace = Struct.new(:dir) do
          def input = File.join(dir, "document.docx")
          def outdir = File.join(dir, "out")
          def output = File.join(outdir, "document.pdf")
          def home = File.join(dir, "home")
          def log = File.join(dir, "soffice.log")
          def profile_url = "file://#{File.join(dir, "lo-profile")}"
        end

        # Converts .docx to PDF with the LibreOffice command line
        # (civora-org/civora-platform#211, spike S1). One process per call:
        #
        # - input and output live in a private (0700) temp directory that also
        #   holds the throwaway LibreOffice profile and HOME, and is removed in
        #   +ensure+;
        # - the child runs with a scrubbed environment (only PATH and HOME), so
        #   database URLs and secrets of the host never reach it;
        # - it runs in its own process group; on timeout the whole group is
        #   killed with SIGKILL, so no soffice.bin is left behind;
        # - input above +max_input_bytes+ is refused before anything starts;
        # - the output is validated as a real PDF (PdfConverter.validate!).
        class LibreOfficeCli
          DEFAULT_TIMEOUT = 60
          DEFAULT_MAX_INPUT_BYTES = 25 * 1024 * 1024
          MAX_OUTPUT_BYTES = 100 * 1024 * 1024
          DEFAULT_PATH = "/usr/local/bin:/usr/bin:/bin"
          POLL_INTERVAL = 0.05

          # +soffice+ is a command name looked up in +path+, or an absolute path.
          def initialize(soffice: "soffice", timeout: DEFAULT_TIMEOUT,
                         max_input_bytes: DEFAULT_MAX_INPUT_BYTES, path: DEFAULT_PATH)
            @soffice = soffice
            @timeout = timeout
            @max_input_bytes = max_input_bytes
            @path = path
          end

          def call(docx_bytes)
            bytes = docx_bytes.to_s.b
            raise PdfConverter::ConversionFailed, "empty input" if bytes.empty?
            if bytes.bytesize > @max_input_bytes
              raise PdfConverter::ConversionFailed, "input exceeds #{@max_input_bytes} bytes"
            end

            executable = resolve_executable
            dir = Dir.mktmpdir("contract-pdf-")
            begin
              convert(executable, bytes, dir)
            ensure
              FileUtils.remove_entry_secure(dir, true)
            end
          end

          private

          def convert(executable, bytes, dir)
            space = ConversionWorkspace.new(dir)
            FileUtils.mkdir_p([space.outdir, space.home], mode: 0o700)
            File.binwrite(space.input, bytes)

            status = wait_or_kill(spawn_soffice(executable, space))
            unless status.success? && File.file?(space.output)
              raise PdfConverter::ConversionFailed, "soffice failed (#{describe(status)})#{log_tail(space.log)}"
            end
            if File.size(space.output) > MAX_OUTPUT_BYTES
              raise PdfConverter::ConversionFailed, "converter output is too large"
            end

            PdfConverter.validate!(File.binread(space.output))
          end

          def spawn_soffice(executable, space)
            Process.spawn({ "PATH" => @path, "HOME" => space.home }, executable, "--headless", "--norestore",
                          "-env:UserInstallation=#{space.profile_url}",
                          "--convert-to", "pdf", "--outdir", space.outdir, space.input,
                          unsetenv_others: true, pgroup: true, chdir: space.home,
                          in: File::NULL, out: space.log, err: [space.log, "a"])
          rescue Errno::ENOENT, Errno::EACCES, Errno::ENOEXEC => e
            raise PdfConverter::ConverterUnavailable,
                  "cannot start #{File.basename(executable)}: #{e.class.name.split("::").last}"
          end

          # Polls instead of blocking, so the deadline can kill the whole group.
          def wait_or_kill(pid)
            deadline = monotonic + @timeout
            finished = false
            loop do
              _, status = Process.wait2(pid, Process::WNOHANG)
              if status
                finished = true
                return status
              end
              raise PdfConverter::ConversionTimeout, "soffice exceeded #{@timeout} s" if monotonic >= deadline

              sleep POLL_INTERVAL
            end
          ensure
            kill_group(pid) unless finished
          end

          # The child leads its own group (pgroup: true), so -pid reaches
          # soffice, oosplash and soffice.bin alike.
          def kill_group(pid)
            Process.kill("KILL", -pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          ensure
            begin
              Process.wait(pid)
            rescue Errno::ECHILD
              nil
            end
          end

          def resolve_executable
            candidates = if @soffice.include?(File::SEPARATOR)
                           [@soffice]
                         else
                           @path.split(File::PATH_SEPARATOR).map { |d| File.join(d, @soffice) }
                         end
            found = candidates.find { |c| File.file?(c) && File.executable?(c) }
            return found if found

            raise PdfConverter::ConverterUnavailable, "#{@soffice} not found in PATH"
          end

          def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          def describe(status)
            status.exitstatus ? "exit #{status.exitstatus}" : "signal #{status.termsig}"
          end

          # soffice's own diagnostics hold no document text; cap them anyway.
          def log_tail(log)
            text = File.file?(log) ? File.binread(log, 200).to_s.scrub.strip : ""
            text.empty? ? "" : ": #{text.gsub(/\s+/, " ")}"
          end
        end
      end
    end
  end
end

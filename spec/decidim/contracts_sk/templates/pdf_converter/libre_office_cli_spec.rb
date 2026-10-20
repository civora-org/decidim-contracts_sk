# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
# The LibreOffice adapter (civora-org/civora-platform#211). Most examples run a
# stub "soffice" shell script, so they need no LibreOffice; the examples tagged
# :libreoffice use the real binary and are skipped where it is absent.
RSpec.describe Decidim::ContractsSk::Templates::PdfConverter::LibreOfficeCli do
  include DocxFixtures

  let(:errors) { Decidim::ContractsSk::Templates::PdfConverter }
  let(:docx) { DocxFixtures.docx(DocxFixtures.para(DocxFixtures.text("Zmluva č. 1"))) }
  let(:sandbox) { Dir.mktmpdir("lo-stub-spec") }
  let(:marker) { File.join(sandbox, "marker") }
  let(:good_pdf) { File.join(sandbox, "good.pdf") }

  before do
    FileUtils.mkdir_p(marker)
    File.binwrite(good_pdf, Decidim::ContractsSk::Templates::MinimalPdf.build(lines: ["Zmluva"]))
  end

  after { FileUtils.remove_entry_secure(sandbox, true) }

  # A stub soffice: records its arguments, environment and pids in +marker+,
  # then runs +body+ with $outdir set to the --outdir argument.
  def stub_soffice(body) # rubocop:disable Metrics/MethodLength
    path = File.join(sandbox, "soffice-stub")
    File.write(path, <<~SH)
      #!/bin/sh
      echo "$$" > #{marker}/pid
      printf '%s\\n' "$@" > #{marker}/args
      env > #{marker}/env
      pwd > #{marker}/pwd
      while [ $# -gt 0 ]; do
        case "$1" in --outdir) outdir="$2";; esac
        shift
      done
      #{body}
    SH
    File.chmod(0o755, path)
    path
  end

  def converter(stub, **) = described_class.new(soffice: stub, **)

  def recorded_args = File.read(File.join(marker, "args")).split("\n")

  def work_dir = File.dirname(recorded_args[recorded_args.index("--outdir") + 1])

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_until_dead(pid, seconds = 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    sleep 0.05 while alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    !alive?(pid)
  end

  describe "a successful conversion (stub)" do
    let(:stub) { stub_soffice(%(cp #{good_pdf} "$outdir/document.pdf")) }

    it "returns the validated PDF bytes" do
      pdf = converter(stub).call(docx)
      expect(pdf).to start_with("%PDF")
      expect(pdf).to eq(File.binread(good_pdf))
    end

    it "passes the documented soffice flags and a per-run profile" do
      converter(stub).call(docx)
      args = recorded_args
      expect(args.first(2)).to eq(%w[--headless --norestore])
      expect(args.grep(%r{\A-env:UserInstallation=file:///.+/contract-pdf-[^/]+/lo-profile\z})).not_to be_empty
      expect(args.each_cons(2).to_a).to include(%w[--convert-to pdf])
      expect(args.last).to end_with("document.docx")
    end

    it "runs with only PATH and HOME in the environment" do
      ENV["CONTRACTS_SK_SECRET_PROBE"] = "must-not-leak"
      ENV["DATABASE_URL"] = "postgres://secret@db/prod"
      converter(stub).call(docx)
      env = File.read(File.join(marker, "env")).split("\n").to_h { |l| l.split("=", 2) }
      expect(env.keys - %w[PATH HOME PWD OLDPWD SHLVL _]).to be_empty
      expect(env).to include("PATH", "HOME")
      expect(File.read(File.join(marker, "env"))).not_to include("must-not-leak", "postgres://")
    ensure
      ENV.delete("CONTRACTS_SK_SECRET_PROBE")
      ENV.delete("DATABASE_URL")
    end

    it "removes the temp directory, profile and home afterwards" do
      converter(stub).call(docx)
      expect(Dir.exist?(work_dir)).to be(false)
    end

    it "uses a private directory" do
      probe = %(stat -c %a "$outdir/.." > #{marker}/mode 2>/dev/null || stat -f %Lp "$outdir/.." > #{marker}/mode)
      stub = stub_soffice("#{probe}; cp #{good_pdf} \"$outdir/document.pdf\"")
      converter(stub).call(docx)
      expect(File.read(File.join(marker, "mode")).strip).to eq("700")
    end
  end

  describe "timeout" do
    let(:stub) { stub_soffice("sleep 300 & echo $! > #{marker}/childpid; wait") }

    it "raises ConversionTimeout, kills the whole process group and removes the temp dir" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { converter(stub, timeout: 0.6).call(docx) }.to raise_error(errors::ConversionTimeout)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5

      pid = File.read(File.join(marker, "pid")).to_i
      child = File.read(File.join(marker, "childpid")).to_i
      expect(pid).to be_positive
      expect(child).to be_positive
      expect(wait_until_dead(pid)).to be(true), "stub soffice is still running"
      expect(wait_until_dead(child)).to be(true), "the stub's child process survived the timeout"
      expect(Dir.exist?(work_dir)).to be(false)
    end
  end

  describe "failures" do
    it "treats a zero exit with a non-PDF file as ConversionFailed (garbage output)" do
      stub = stub_soffice(%(printf 'definitely not a pdf' > "$outdir/document.pdf"))
      expect { converter(stub).call(docx) }.to raise_error(errors::ConversionFailed, /%PDF/)
      expect(Dir.exist?(work_dir)).to be(false)
    end

    it "rejects a %PDF header over an unparseable body" do
      stub = stub_soffice(%(printf '%%PDF-1.4\\ngarbage garbage' > "$outdir/document.pdf"))
      expect { converter(stub).call(docx) }.to raise_error(errors::ConversionFailed, /not a readable PDF/)
    end

    it "rejects a zero exit that wrote no output file" do
      stub = stub_soffice("exit 0")
      expect { converter(stub).call(docx) }.to raise_error(errors::ConversionFailed, /soffice failed/)
    end

    it "reports a non-zero exit and cleans up" do
      stub = stub_soffice("echo boom >&2; exit 3")
      expect { converter(stub).call(docx) }.to raise_error(errors::ConversionFailed, /exit 3.*boom/)
      expect(Dir.exist?(work_dir)).to be(false)
    end

    it "refuses empty input and input above the size cap without starting soffice" do
      stub = stub_soffice("exit 0")
      expect { converter(stub).call("") }.to raise_error(errors::ConversionFailed, /empty/)
      expect { converter(stub, max_input_bytes: 10).call(docx) }.to raise_error(errors::ConversionFailed, /exceeds/)
      expect(File.exist?(File.join(marker, "pid"))).to be(false)
    end

    it "raises ConverterUnavailable when soffice is not installed" do
      expect { described_class.new(soffice: "no-such-soffice-binary").call(docx) }
        .to raise_error(errors::ConverterUnavailable, /not found/)
      expect { described_class.new(soffice: File.join(sandbox, "missing")).call(docx) }
        .to raise_error(errors::ConverterUnavailable)
    end

    it "raises ConverterUnavailable for a file that is not executable" do
      path = File.join(sandbox, "plain")
      File.write(path, "x")
      expect { described_class.new(soffice: path).call(docx) }.to raise_error(errors::ConverterUnavailable)
    end
  end

  describe "real LibreOffice", :libreoffice do
    let(:template_values) do
      { org_nazov: "Obec Vzorová", org_ico: "00000000", org_adresa: "Námestie Vzorové 1",
        cislo_zmluvy: "VZ-2026-001", predmet: "Oprava lavičky", datum_ucinnosti: "1. 1. 2027",
        polozky: [{ nazov: "Materiál", suma: "120,00" }], suma_celkom: "120,00",
        suma_slovom: "stodvadsať eur", priloha: nil,
        kupujuci_meno: "Ján Testovací", kupujuci_adresa: "Ulica Nepravá 99", kupujuci_rc: "000000/0000" }
    end
    let(:filled) do
      Decidim::ContractsSk::Templates::DocxFiller.call(DocxFixtures.synthetic_template, template_values)
    end

    it "converts a filled synthetic template to a readable PDF with the text in it" do
      pdf = described_class.new.call(filled)
      reader = PDF::Reader.new(StringIO.new(pdf))
      text = reader.pages.map(&:text).join
      expect(reader.page_count).to be >= 1
      expect(text).to include("VZ-2026-001")
      expect(text.delete(" ")).to include("Opravalavičky")
    end

    it "leaves no soffice process or temp directory behind" do
      before_dirs = Dir.glob(File.join(Dir.tmpdir, "contract-pdf-*"))
      described_class.new.call(filled)
      expect(Dir.glob(File.join(Dir.tmpdir, "contract-pdf-*")) - before_dirs).to be_empty
    end

    it "does not accept a text file named .docx as a valid conversion silently" do
      # soffice may convert the text to a PDF; the adapter's contract is only
      # that whatever it returns is a real PDF, or it raises.
      result = begin
        described_class.new.call("plain text, not a docx")
      rescue errors::ConversionFailed
        :failed
      end
      expect(result == :failed || result.start_with?("%PDF")).to be(true)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

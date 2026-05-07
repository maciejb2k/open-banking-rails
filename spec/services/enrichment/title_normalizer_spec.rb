# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::TitleNormalizer do
  it "strips a known mBank city prefix and trailing PL/digits to leave the merchant token" do
    expect(described_class.call("RZESZOWLIDL 01PL")).to eq("LIDL")
    expect(described_class.call("RZESZOWJMP S.A. BIEDRONKA 7645PL")).to eq("JMP S A BIEDRONKA")
    expect(described_class.call("RzeszoweLeclercPL")).to eq("ELECLERC")
  end

  it "leaves a title without a city prefix or trailing PL essentially intact (uppercased, digits stripped)" do
    expect(described_class.call("Some Coffee 12")).to eq("SOME COFFEE")
  end

  it "returns an empty string for blank input on .call" do
    expect(described_class.call("")).to eq("")
    expect(described_class.call(nil)).to eq("")
  end

  it "returns nil for blank input on .likely_pattern" do
    expect(described_class.likely_pattern("")).to be_nil
    expect(described_class.likely_pattern(nil)).to be_nil
  end

  it "returns the longest 3+ character token from .likely_pattern after stripping prefix and digits" do
    expect(described_class.likely_pattern("RZESZOWBIEDRONKA 7645PL")).to eq("BIEDRONKA")
  end
end

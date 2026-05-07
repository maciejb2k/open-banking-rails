# frozen_string_literal: true

require "rails_helper"

RSpec.describe StyleguideDemo do
  it "exposes the three ActiveModel attributes the styleguide form renders against" do
    record = described_class.new(name: "Demo", email: "demo@example.test", category_id: "7")

    expect(record.name).to eq("Demo")
    expect(record.email).to eq("demo@example.test")
    expect(record.category_id).to eq(7)
  end

  it "is not an ActiveRecord-backed model and validates as always-valid (no constraints declared)" do
    record = described_class.new

    expect(described_class.ancestors).to include(ActiveModel::Model, ActiveModel::Attributes)
    expect(described_class.ancestors).not_to include(ActiveRecord::Base)
    expect(record).to be_valid
    expect(record.persisted?).to be(false)
  end
end

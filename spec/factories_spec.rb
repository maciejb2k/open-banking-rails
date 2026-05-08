# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FactoryBot" do
  it "lints every defined factory and trait without validation failures" do
    FactoryBot.lint(traits: true)
  end
end

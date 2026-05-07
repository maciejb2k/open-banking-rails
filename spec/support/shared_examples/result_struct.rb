# frozen_string_literal: true

# Shared examples that codify the AGENTS.md service-object Result conventions:
# success?, error, error_messages aggregator, RecordInvalid translation,
# idempotency. Domain spec files use these as one-liners rather than
# duplicating the assertion shape per service.

RSpec.shared_examples "a service returning a Result" do
  it "returns a Result that responds to success? and error" do
    expect(subject).to respond_to(:success?)
    expect(subject).to respond_to(:error)
  end
end

RSpec.shared_examples "a service that wraps RecordInvalid" do
  it "translates ActiveRecord::RecordInvalid into a failed Result with error_messages" do
    expect(subject.success?).to be(false)
    expect(subject.error_messages).to be_a(Array)
    expect(subject.error_messages).not_to be_empty
  end
end

RSpec.shared_examples "an idempotent service" do |snapshot:|
  it "is idempotent (running twice produces the same DB snapshot)" do
    run_service.call
    first  = snapshot.call
    run_service.call
    second = snapshot.call
    expect(second).to eq(first)
  end
end

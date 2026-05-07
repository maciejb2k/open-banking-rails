# frozen_string_literal: true

require "rails_helper"

RSpec.describe OperationRunFinalizer do
  it "marks the run failed with 'No accounts in scope' when summary[:accounts] is empty" do
    user = create(:user)
    run = create(:operation_run, :running, triggered_by_user: user)

    described_class.call(run, { accounts: [] })

    expect(run.reload.status).to eq("failed")
    expect(run.error).to eq("No accounts in scope")
  end

  it "marks the run succeeded when every account in summary[:accounts] succeeded" do
    user = create(:user)
    run = create(:operation_run, :running, triggered_by_user: user)

    described_class.call(run, { accounts: [ { status: "succeeded" }, { status: "succeeded" } ] })

    expect(run.reload.status).to eq("succeeded")
    expect(run.error).to be_nil
  end

  it "marks the run partial when some accounts succeeded and others failed (with a count message)" do
    user = create(:user)
    run = create(:operation_run, :running, triggered_by_user: user)

    described_class.call(run, { accounts: [ { status: "succeeded" }, { status: "failed" }, { status: "failed" } ] })

    run.reload
    expect(run.status).to eq("partial")
    expect(run.error).to eq("2 account(s) failed")
  end

  it "marks the run failed when no accounts succeeded (with a total-failure message)" do
    user = create(:user)
    run = create(:operation_run, :running, triggered_by_user: user)

    described_class.call(run, { accounts: [ { status: "failed" }, { status: "failed" } ] })

    run.reload
    expect(run.status).to eq("failed")
    expect(run.error).to eq("All 2 account(s) failed")
  end

  it "always lands the run in a TERMINAL_STATUSES state — terminal-state invariant (permutation 8)" do
    user = create(:user)
    [
      { accounts: [] },
      { accounts: [ { status: "succeeded" } ] },
      { accounts: [ { status: "succeeded" }, { status: "failed" } ] },
      { accounts: [ { status: "failed" } ] }
    ].each do |summary|
      run = create(:operation_run, :running, triggered_by_user: user)
      described_class.call(run, summary)
      expect(OperationRun::TERMINAL_STATUSES).to include(run.reload.status), "summary=#{summary.inspect}"
      expect(run.finished_at).to be_present
    end
  end
end

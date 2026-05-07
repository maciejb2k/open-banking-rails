# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutoSync::ScheduleUpserter do
  def call(connection:, user:, **input_attrs)
    input = described_class::Input.new(enabled: nil, cadence: nil, preferred_hour: nil, **input_attrs)
    described_class.call(connection: connection, user: user, input: input)
  end

  it "creates a new SyncSchedule on the first call for a connection" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)

    result = call(connection: connection, user: user, enabled: true, cadence: "daily", preferred_hour: 9)

    expect(result.success?).to be(true)
    expect(SyncSchedule.where(bank_connection: connection).count).to eq(1)
    expect(result.schedule.cadence).to eq("daily")
    expect(result.schedule.preferred_hour).to eq(9)
    expect(result.schedule.enabled).to be(true)
    expect(result.schedule.next_run_at).to be_present
  end

  it "preserves the previously planned next_run_at when toggling enabled off without changing other timing" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    initial = call(connection: connection, user: user, enabled: true, cadence: "daily", preferred_hour: 8)
    original_slot = initial.schedule.next_run_at

    disabled = call(connection: connection, user: user, enabled: false, cadence: "daily", preferred_hour: 8)

    expect(disabled.schedule.enabled).to be(false)
    expect(disabled.schedule.next_run_at).to eq(original_slot)
  end

  it "recomputes next_run_at on cadence change" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    initial = call(connection: connection, user: user, enabled: true, cadence: "daily", preferred_hour: 8)
    original_slot = initial.schedule.next_run_at

    travel_to(1.minute.from_now) do
      changed = call(connection: connection, user: user, enabled: true, cadence: "weekly", preferred_hour: 8)
      expect(changed.schedule.cadence).to eq("weekly")
      expect(changed.schedule.next_run_at).not_to eq(original_slot)
    end
  end

  it "recomputes next_run_at when toggling enabled back on after a disable" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)
    initial = call(connection: connection, user: user, enabled: true, cadence: "daily", preferred_hour: 8)
    original_slot = initial.schedule.next_run_at
    call(connection: connection, user: user, enabled: false, cadence: "daily", preferred_hour: 8)

    travel_to(2.hours.from_now) do
      re_enabled = call(connection: connection, user: user, enabled: true, cadence: "daily", preferred_hour: 8)
      expect(re_enabled.schedule.next_run_at).not_to eq(original_slot)
    end
  end

  it "casts boolean-like enabled values via ActiveModel::Type::Boolean" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)

    truthy = call(connection: connection, user: user, enabled: "1", cadence: "daily", preferred_hour: 8)
    expect(truthy.schedule.enabled).to be(true)

    falsy = call(connection: connection, user: user, enabled: "0", cadence: "daily", preferred_hour: 8)
    expect(falsy.schedule.enabled).to be(false)
  end

  it "returns Result(success?: false) carrying validation errors when preferred_hour is out of range" do
    user = create(:user)
    tpp = create(:tpp_credential, user: user)
    connection = create(:bank_connection, tpp_credential: tpp)

    result = call(connection: connection, user: user, enabled: true, cadence: "daily", preferred_hour: 99)

    expect(result.success?).to be(false)
    expect(result.error).to match(/preferred[_ ]hour/i)
  end
end

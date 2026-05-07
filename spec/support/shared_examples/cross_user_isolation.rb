# frozen_string_literal: true

# Shared example verifying that an authenticated request scoped to user A
# cannot reach user B's record under the same path. The scope is asserted
# via the controller's `current_user.<assoc>.find` pattern (per AGENTS.md);
# the result is a 404, not a 403. Used in every controller-area request spec.

RSpec.shared_examples "a cross-user isolated resource" do |verb:, path_for:|
  it "returns 404 when accessing another user's resource" do
    user_a = create(:user)
    user_b = create(:user)
    record_a = build_record.call(user_a)
    record_b = build_record.call(user_b)
    sign_in user_a
    public_send(verb, path_for.call(record_b))
    expect(response.status).to eq(404)
    expect(record_b.class.exists?(record_b.id)).to be(true)
  end

  it "returns 200 when accessing the user's own resource" do
    user_a   = create(:user)
    record_a = build_record.call(user_a)
    sign_in user_a
    public_send(verb, path_for.call(record_a))
    expect(response.status).to be_between(200, 399)
  end
end

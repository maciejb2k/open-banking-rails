# frozen_string_literal: true

# Shared example verifying that an authenticated request scoped to user A
# cannot reach user B's record under the same path. The scope is asserted
# via the controller's `current_user.<assoc>.find` pattern (per AGENTS.md);
# the result is a 404, not a 403, and the foreign record must survive the
# call. Used by request specs whose 404-on-foreign-id assertion has no
# additional shape beyond status + survival.

RSpec.shared_examples "a cross-user isolated resource" do |verb:, path_for:, build_record:|
  it "returns 404 when accessing another user's resource and leaves it intact" do
    user_a = create(:user)
    user_b = create(:user)
    record_b = instance_exec(user_b, &build_record)
    sign_in user_a

    public_send(verb, path_for.call(record_b))

    expect(response).to have_http_status(:not_found)
    expect(record_b.class.exists?(record_b.id)).to be(true)
  end

  it "returns a successful status when the same path is accessed by the record's owner" do
    user_a = create(:user)
    record_a = instance_exec(user_a, &build_record)
    sign_in user_a

    public_send(verb, path_for.call(record_a))

    expect(response.status).to be_between(200, 399)
  end
end

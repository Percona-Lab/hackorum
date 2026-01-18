require "rails_helper"

RSpec.describe "TeamsProfile", type: :request do
  def sign_in(email:, password: "secret")
    post session_path, params: { email: email, password: password }
    expect(response).to redirect_to(root_path)
  end

  def attach_verified_alias(user, email:, primary: true)
    al = create(:alias, user: user, email: email)
    if primary && user.person&.default_alias_id.nil?
      user.person.update!(default_alias_id: al.id)
    end
    Alias.by_email(email).update_all(verified_at: Time.current)
    al
  end

  describe "GET /team/:name" do
    let!(:team) { create(:team, name: "test-team") }
    let!(:admin) { create(:user, password: "secret", password_confirmation: "secret") }
    let!(:member) { create(:user, password: "secret", password_confirmation: "secret") }
    let!(:non_member) { create(:user, password: "secret", password_confirmation: "secret") }

    before do
      create(:team_member, team: team, user: admin, role: "admin")
      create(:team_member, team: team, user: member, role: "member")
    end

    context "with private team (default)" do
      it "redirects guests to sign in" do
        get team_profile_path("test-team")
        expect(response).to redirect_to(new_session_path)
      end

      it "returns 404 for signed-in non-members" do
        attach_verified_alias(non_member, email: "non-member@example.com")
        sign_in(email: "non-member@example.com")

        get team_profile_path("test-team")
        expect(response).to have_http_status(:not_found)
      end

      it "allows signed-in team members" do
        attach_verified_alias(member, email: "member@example.com")
        sign_in(email: "member@example.com")

        get team_profile_path("test-team")
        expect(response).to have_http_status(:success)
      end
    end

    context "with visible team" do
      before { team.update!(visibility: :visible) }

      it "allows guests to view" do
        get team_profile_path("test-team")
        expect(response).to have_http_status(:success)
      end

      it "allows non-members to view" do
        attach_verified_alias(non_member, email: "non-member@example.com")
        sign_in(email: "non-member@example.com")

        get team_profile_path("test-team")
        expect(response).to have_http_status(:success)
      end
    end

    context "with open team" do
      before { team.update!(visibility: :open) }

      it "allows guests to view" do
        get team_profile_path("test-team")
        expect(response).to have_http_status(:success)
      end

      it "allows non-members to view" do
        attach_verified_alias(non_member, email: "non-member@example.com")
        sign_in(email: "non-member@example.com")

        get team_profile_path("test-team")
        expect(response).to have_http_status(:success)
      end
    end

    it "returns 404 for non-existent teams" do
      get team_profile_path("non-existent")
      expect(response).to have_http_status(:not_found)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Team, type: :model do
  let(:user) { create(:user) }
  let(:user2) { create(:user) }
  let(:team) { Team.create!(name: "Team1") }

  before do
    TeamMember.add_member(team: team, user: user, role: :admin)
  end

  it "detects members and admins" do
    expect(team.member?(user)).to be(true)
    expect(team.admin?(user)).to be(true)
    expect(team.member?(user2)).to be(false)
  end
end

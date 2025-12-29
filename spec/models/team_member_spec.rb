# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamMember, type: :model do
  let(:user) { create(:user) }
  let(:team) { Team.create!(name: "Team") }

  it "adds member with enum role" do
    member = described_class.add_member(team:, user:, role: :admin)
    expect(member).to be_admin
  end
end

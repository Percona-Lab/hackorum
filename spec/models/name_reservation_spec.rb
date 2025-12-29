# frozen_string_literal: true

require "rails_helper"

RSpec.describe NameReservation, type: :model do
  let(:user) { create(:user) }
  let(:team) { Team.create!(name: "team1") }

  it "reserves and prevents duplicates across owners" do
    NameReservation.reserve!(name: "test", owner: user)
    expect {
      NameReservation.reserve!(name: "test", owner: team)
    }.to raise_error(ActiveRecord::RecordInvalid)
  end
end

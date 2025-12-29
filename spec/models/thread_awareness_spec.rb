# frozen_string_literal: true

require "rails_helper"

RSpec.describe ThreadAwareness, type: :model do
  let(:user) { create(:user) }
  let(:alias_record) { Alias.create!(name: "Test", email: "test@example.com", user: user, person: user.person) }
  let(:topic) { Topic.create!(title: "Topic", creator: alias_record) }

  describe ".mark_until" do
    it "creates a new awareness marker" do
      marker = described_class.mark_until(user:, topic:, until_message_id: 3)

      expect(marker.aware_until_message_id).to eq(3)
      expect(described_class.count).to eq(1)
    end

    it "extends the existing marker forward" do
      described_class.mark_until(user:, topic:, until_message_id: 5)
      described_class.mark_until(user:, topic:, until_message_id: 10)

      expect(described_class.count).to eq(1)
      merged = described_class.first
      expect(merged.aware_until_message_id).to eq(10)
    end

    it "does not move backward" do
      described_class.mark_until(user:, topic:, until_message_id: 10)
      described_class.mark_until(user:, topic:, until_message_id: 5)

      expect(described_class.first.aware_until_message_id).to eq(10)
    end
  end

  describe ".covering?" do
    before do
      described_class.mark_until(user:, topic:, until_message_id: 6)
    end

    it "returns true when inside aware range" do
      expect(described_class.covering?(user:, topic:, message_id: 4)).to be(true)
    end

    it "returns false when outside aware range" do
      expect(described_class.covering?(user:, topic:, message_id: 10)).to be(false)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageReadRange, type: :model do
  let(:user) { create(:user) }
  let(:alias_record) { Alias.create!(name: "Test", email: "test@example.com", user: user, person: user.person) }
  let(:topic) { Topic.create!(title: "Topic", creator: alias_record) }

  describe ".add_range" do
    it "creates a new range when none overlap" do
      range = described_class.add_range(user:, topic:, start_id: 5, end_id: 10)

      expect(range.range_start_message_id).to eq(5)
      expect(range.range_end_message_id).to eq(10)
      expect(described_class.count).to eq(1)
    end

    it "merges overlapping ranges" do
      described_class.add_range(user:, topic:, start_id: 1, end_id: 5)
      described_class.add_range(user:, topic:, start_id: 4, end_id: 8)

      expect(described_class.count).to eq(1)
      merged = described_class.first
      expect(merged.range_start_message_id).to eq(1)
      expect(merged.range_end_message_id).to eq(8)
    end

    it "merges touching ranges" do
      described_class.add_range(user:, topic:, start_id: 1, end_id: 3)
      described_class.add_range(user:, topic:, start_id: 4, end_id: 6)

      merged = described_class.first
      expect(merged.range_start_message_id).to eq(1)
      expect(merged.range_end_message_id).to eq(6)
    end
  end

  describe ".covering?" do
    before do
      described_class.add_range(user:, topic:, start_id: 10, end_id: 20)
    end

    it "returns true when message id is inside a range" do
      expect(described_class.covering?(user:, topic:, message_id: 15)).to be(true)
    end

    it "returns false when message id is outside ranges" do
      expect(described_class.covering?(user:, topic:, message_id: 25)).to be(false)
    end
  end
end

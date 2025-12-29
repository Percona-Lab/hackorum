require 'rails_helper'

RSpec.describe Alias, type: :model do
  describe '.by_email' do
    it 'matches case-insensitively and trims spaces' do
      create(:alias, email: 'User@Example.com')
      expect(Alias.by_email(' user@example.com ')).to exist
    end
  end

end

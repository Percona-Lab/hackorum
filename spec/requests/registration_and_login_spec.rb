require 'rails_helper'

RSpec.describe 'Registration and Login', type: :request do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs && ActionMailer::Base.deliveries.clear }

  describe 'registration via existing alias' do
    it 'creates a user and attaches aliases on verification' do
      al = create(:alias, email: 'user@example.com', user: nil)

      perform_enqueued_jobs do
        post registration_path, params: { email: 'user@example.com', username: 'newuser', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(root_path)
      end

      raw = extract_raw_token_from_mailer
      get verification_path(token: raw)
      expect(response).to redirect_to(root_path)

      al.reload
      expect(al.user).to be_present
      expect(al.verified_at).to be_present
    end
  end

  describe 'registration via new alias' do
    it 'creates user and alias on verification' do
      perform_enqueued_jobs do
        post registration_path, params: { email: 'new@example.com', name: 'New Person', username: 'newperson', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(root_path)
      end

      raw = extract_raw_token_from_mailer
      get verification_path(token: raw)
      expect(response).to redirect_to(root_path)

      user = User.order(:created_at).last
      al = user.aliases.first
      expect(al).to be_present
      expect(al.email).to eq('new@example.com')
      expect(user.person.default_alias_id).to eq(al.id)
      expect(al.verified_at).to be_present
    end

    it 'reserves username during registration request' do
      perform_enqueued_jobs do
        post registration_path, params: { email: 'new@example.com', name: 'New Person', username: 'reserved', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(root_path)
      end

      # Username should be reserved for the token
      token = UserToken.order(:created_at).last
      reservation = NameReservation.find_by(name: 'reserved')
      expect(reservation).to be_present
      expect(reservation.owner_type).to eq('UserToken')
      expect(reservation.owner_id).to eq(token.id)
    end

    it 'transfers username reservation to user on verification' do
      perform_enqueued_jobs do
        post registration_path, params: { email: 'new@example.com', name: 'New Person', username: 'transfer', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(root_path)
      end

      raw = extract_raw_token_from_mailer
      get verification_path(token: raw)
      expect(response).to redirect_to(root_path)

      user = User.order(:created_at).last
      reservation = NameReservation.find_by(name: 'transfer')
      expect(reservation).to be_present
      expect(reservation.owner_type).to eq('User')
      expect(reservation.owner_id).to eq(user.id)
    end

    it 'prevents race condition where username is taken during verification' do
      perform_enqueued_jobs do
        post registration_path, params: { email: 'first@example.com', username: 'racetest', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(root_path)
      end

      # Try to register with same username from different email - should fail
      perform_enqueued_jobs do
        post registration_path, params: { email: 'second@example.com', username: 'racetest', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(registration_path)
        expect(flash[:alert]).to match(/already taken/i)
      end
    end

    it 'releases username reservation when token is destroyed' do
      perform_enqueued_jobs do
        post registration_path, params: { email: 'cleanup@example.com', username: 'cleanup', password: 'secret', password_confirmation: 'secret' }
        expect(response).to redirect_to(root_path)
      end

      token = UserToken.order(:created_at).last
      expect(NameReservation.find_by(name: 'cleanup')).to be_present

      token.destroy
      expect(NameReservation.find_by(name: 'cleanup')).to be_nil
    end
  end

  describe 'password login' do
    it 'signs in with verified alias and password' do
      user = create(:user, password: 'secret', password_confirmation: 'secret')
      al = create(:alias, user: user, email: 'login@example.com')
      user.person.update!(default_alias_id: al.id) if user.person.default_alias_id.nil?
      Alias.by_email('login@example.com').update_all(verified_at: Time.current)

      post session_path, params: { email: 'login@example.com', password: 'secret' }
      expect(response).to redirect_to(root_path)
    end
  end

  def extract_raw_token_from_mailer
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    url = mail.body.encoded[%r{https?://[^\s]+}]
    Rack::Utils.parse_query(URI.parse(url).query)['token']
  end
end

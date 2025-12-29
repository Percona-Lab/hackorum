require 'rails_helper'

RSpec.describe 'Password reset', type: :request do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs && ActionMailer::Base.deliveries.clear }

  it 'resets password via emailed token' do
    user = create(:user, password: 'oldsecret', password_confirmation: 'oldsecret')
    al = create(:alias, user: user, email: 'reset@example.com')
    user.person.update!(default_alias_id: al.id) if user.person.default_alias_id.nil?
    Alias.by_email('reset@example.com').update_all(verified_at: Time.current)

    perform_enqueued_jobs do
      post password_path, params: { email: 'reset@example.com' }
      expect(response).to redirect_to(new_session_path)
    end

    raw = extract_raw_token_from_mailer
    get edit_password_path(token: raw)
    expect(response).to have_http_status(:ok)

    patch password_path, params: { token: raw, password: 'newsecret', password_confirmation: 'newsecret' }
    expect(response).to redirect_to(new_session_path)

    post session_path, params: { email: 'reset@example.com', password: 'newsecret' }
    expect(response).to redirect_to(root_path)
  end

  def extract_raw_token_from_mailer
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    url = mail.body.encoded[%r{https?://[^\s]+}]
    Rack::Utils.parse_query(URI.parse(url).query)['token']
  end
end

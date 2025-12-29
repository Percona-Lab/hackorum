class EmailsController < ApplicationController
  before_action :require_authentication

  def index
    @aliases = current_user.person&.aliases&.order(:email) || []
  end

  def create
    email = EmailNormalizer.normalize(params[:email])
    # Block if email belongs to another active user
    if Alias.by_email(email).where.not(user_id: [nil, current_user.id]).exists?
      return redirect_to settings_path, alert: 'Email is linked to another account. Delete that account first to release it.'
    end
    token, raw = UserToken.issue!(purpose: 'add_alias', user: current_user, email: email, ttl: 1.hour)
    UserMailer.verification_email(token, raw).deliver_later
    redirect_to settings_path, notice: 'Verification email sent.'
  end

  def destroy
    al = current_user.person.aliases.find(params[:id])
    if current_user.person&.default_alias_id == al.id
      redirect_to settings_path, alert: 'Cannot remove primary alias.'
    else
      new_person = Person.create!(default_alias_id: al.id)
      al.update!(user_id: nil, verified_at: nil, person_id: new_person.id)
      redirect_to settings_path, notice: 'Email removed.'
    end
  end

  def primary
    al = current_user.person.aliases.find(params[:id])
    current_user.person&.update!(default_alias_id: al.id)
    redirect_to settings_path, notice: 'Primary email updated.'
  end
end

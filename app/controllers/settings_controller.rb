# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_authentication

  def show
    @aliases = current_user.aliases.order(:email)
    @identities = current_user.identities.order(:provider, :email, :uid)
  end
end

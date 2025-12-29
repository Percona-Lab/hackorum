# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_authentication

  def show
    @aliases = current_user.person&.aliases&.order(:email) || []
    @identities = current_user.identities.order(:provider, :email, :uid)
    @default_alias_id = current_user.person&.default_alias_id
  end
end

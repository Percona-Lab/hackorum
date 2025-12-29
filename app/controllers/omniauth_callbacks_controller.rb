class OmniauthCallbacksController < ApplicationController
  def google_oauth2
    auth = request.env['omniauth.auth']
    provider = auth['provider']
    uid = auth['uid']
    info = auth['info'] || {}
    email = info['email']
    omniauth_params = request.env['omniauth.params'] || {}
    linking = omniauth_params['link'].present?

    identity = Identity.find_by(provider: provider, uid: uid)

    if linking && current_user
      if identity
        if identity.user_id != current_user.id
          return redirect_to settings_path, alert: 'That Google account is already linked to another user.'
        end
        return redirect_to settings_path, notice: 'That Google account is already linked to your account.'
      else
        if Alias.by_email(email).where.not(user_id: [nil, current_user.id]).exists?
          return redirect_to settings_path, alert: 'Email is linked to another account. Delete that account first to release it.'
        end

        aliases = Alias.by_email(email).where(user_id: [nil, current_user.id])
        if aliases.exists?
          aliases.update_all(user_id: current_user.id, verified_at: Time.current)
          if current_user.primary_alias.nil?
            primary = aliases.find_by(primary_alias: true) || aliases.first
            primary.update!(primary_alias: true) if primary
          end
        else
          name = info['name'].presence || email
          Alias.create!(
            user: current_user,
            name: name,
            email: email,
            primary_alias: current_user.primary_alias.nil?,
            verified_at: Time.current
          )
        end

        identity = Identity.create!(user: current_user, provider: provider, uid: uid, email: email, raw_info: auth.to_json, last_used_at: Time.current)
      end

      identity.update!(last_used_at: Time.current, email: email, raw_info: auth.to_json)
      return redirect_to settings_path, notice: 'Google account linked.'
    end

    if identity
      user = identity.user
    else
      # Do not attach to existing users from the login flow.
      alias_user = Alias.by_email(email).where.not(user_id: nil).includes(:user).first&.user
      if alias_user
        return redirect_to new_session_path, alert: 'That Google account is already associated with an existing user. Link it from Settings instead.'
      end
      user = User.create!

      # If no aliases exist for this email, create one
      aliases = Alias.by_email(email).where(user_id: [nil, user.id])
      if aliases.exists?
        aliases.update_all(user_id: user.id, verified_at: Time.current)
        if user.primary_alias.nil?
          primary = aliases.find_by(primary_alias: true) || aliases.first
          primary.update!(primary_alias: true) if primary
        end
      else
        name = info['name'].presence || email
        Alias.create!(user: user, name: name, email: email, primary_alias: user.primary_alias.nil?, verified_at: Time.current)
      end

      identity = Identity.create!(user: user, provider: provider, uid: uid, email: email, raw_info: auth.to_json, last_used_at: Time.current)
    end

    identity.update!(last_used_at: Time.current)

    reset_session
    session[:user_id] = identity.user_id
    redirect_to root_path, notice: 'Signed in with Google'
  rescue => e
    Rails.logger.error("OIDC error: #{e.class}: #{e.message}")
    redirect_to new_session_path, alert: 'Could not sign in with Google.'
  end
end

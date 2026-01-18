module ProfileHelper
  def profile_filter_url(profile_routes, activity_period)
    return profile_routes[:default] if activity_period.nil?

    case activity_period[:type]
    when :day
      profile_routes[:daily].call(activity_period[:date].iso8601)
    when :week
      profile_routes[:weekly].call(activity_period[:year], activity_period[:week])
    when :month
      profile_routes[:monthly].call(activity_period[:year], activity_period[:month])
    else
      profile_routes[:default]
    end
  end

  def person_profile_routes(email)
    {
      default: person_path(email),
      daily: ->(date) { person_activity_path(email, date) },
      weekly: ->(year, week) { person_weekly_activity_path(email, year, week) },
      monthly: ->(year, month) { person_monthly_activity_path(email, year, month) },
      contributions: ->(year) { person_contributions_path(email, year: year) }
    }
  end

  def team_profile_routes(name)
    {
      default: team_profile_path(name),
      daily: ->(date) { team_activity_path(name, date) },
      weekly: ->(year, week) { team_weekly_activity_path(name, year, week) },
      monthly: ->(year, month) { team_monthly_activity_path(name, year, month) },
      contributions: ->(year) { team_contributions_path(name, year: year) }
    }
  end
end

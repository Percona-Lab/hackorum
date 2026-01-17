class PeopleController < ApplicationController
  before_action :load_person

  def show
    @first_message_at = Message.where(sender_person_id: @person.id).minimum(:created_at)
    @last_message_at = Message.where(sender_person_id: @person.id).maximum(:created_at)
    @activity_entries = build_activity_entries
    @contribution_years = contribution_years
    @contribution_year = select_contribution_year(@contribution_years)
    @contribution_weeks, @contribution_month_spans = build_contribution_weeks(@contribution_year)
    @profile_email = profile_email
  end

  def contributions
    @contribution_years = contribution_years
    @contribution_year = select_contribution_year(@contribution_years)
    @contribution_weeks, @contribution_month_spans = build_contribution_weeks(@contribution_year)
    @profile_email = profile_email

    render :contributions
  end

  def daily_activity
    date = parse_activity_date
    messages_scope = Message.where(sender_person_id: @person.id, created_at: date.beginning_of_day..date.end_of_day)
    @activity_entries = build_activity_entries(scope: messages_scope)
    @activity_date = date

    render :recent_threads
  end

  private

  def load_person
    @person = find_person
    @primary_alias = @person.default_alias
    @aliases = @person.aliases.with_sent_messages.order(:email)
  end

  def find_person
    email_param = params[:email].to_s
    person = Person.find_by_email(email_param)
    return Person.includes(:aliases, :default_alias).find(person.id) if person

    if email_param.match?(/\A\d+\z/)
      return Person.includes(:aliases, :default_alias).find(email_param)
    end

    raise ActiveRecord::RecordNotFound
  end

  def profile_email
    @primary_alias&.email || @aliases.first&.email || params[:email].to_s
  end

  def build_activity_entries(scope: nil)
    scope ||= Message.where(sender_person_id: @person.id)
    topic_rows = scope.group(:topic_id)
                      .select('topic_id, MAX(created_at) AS last_at')
                      .order('last_at DESC')
                      .limit(10)

    topic_ids = topic_rows.map(&:topic_id)
    return [] if topic_ids.empty?

    topics = Topic.where(id: topic_ids).index_by(&:id)
    started_ids = Topic.where(id: topic_ids, creator_person_id: @person.id).pluck(:id)
    patch_ids = scope.joins(:attachments).distinct.pluck(:topic_id)

    topic_rows.map do |row|
      topic = topics[row.topic_id]
      next unless topic

      {
        topic: topic,
        last_at: row.read_attribute(:last_at),
        started: started_ids.include?(row.topic_id),
        has_patch: patch_ids.include?(row.topic_id)
      }
    end.compact
  end

  def build_contribution_weeks(year)
    year = year.to_i
    start_date = Date.new(year, 1, 1)
    end_date = Date.new(year, 12, 31)
    start_date -= start_date.wday
    end_date += (6 - end_date.wday)
    counts = Message.where(sender_person_id: @person.id, created_at: start_date.beginning_of_day..end_date.end_of_day)
                    .group(Arel.sql("DATE(messages.created_at)"))
                    .count

    total_days = (end_date - start_date).to_i + 1
    days = (0...total_days).map do |idx|
      date = start_date + idx.days
      count = counts[date] || 0
      {
        date: date,
        count: count,
        level: contribution_level(count)
      }
    end

    weeks = days.each_slice(7).to_a
    weeks.each do |week|
      next if week.length == 7
      missing = 7 - week.length
      missing.times do |idx|
        date = week.last[:date] + (idx + 1).days
        week << { date: date, count: 0, level: 0 }
      end
    end
    month_spans = []
    current_label = nil
    current_span = 0
    weeks.each do |week|
      label = week.first[:date].strftime('%b')
      if current_label != label
        month_spans << { label: current_label, span: current_span } if current_label
        current_label = label
        current_span = 1
      else
        current_span += 1
      end
    end
    month_spans << { label: current_label, span: current_span } if current_label

    [weeks, month_spans]
  end

  def parse_activity_date
    Date.iso8601(params[:date])
  rescue ArgumentError
    Date.current
  end

  def contribution_years
    Message.where(sender_person_id: @person.id)
           .distinct
           .pluck(Arel.sql("EXTRACT(YEAR FROM messages.created_at)"))
           .map(&:to_i)
           .sort
           .reverse
  end

  def select_contribution_year(years)
    year_param = params[:year].presence&.to_i
    return year_param if year_param && years.include?(year_param)
    return years.first if years.any?

    Date.current.year
  end

  def contribution_level(count)
    return 0 if count.zero?
    return 1 if count < 3
    return 2 if count < 6
    return 3 if count < 10
    4
  end
end

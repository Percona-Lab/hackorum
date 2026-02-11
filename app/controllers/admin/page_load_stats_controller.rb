# frozen_string_literal: true

class Admin::PageLoadStatsController < Admin::BaseController
  def active_admin_section
    :page_load_stats
  end

  def index
    @to = parse_date(params[:to]) || Date.current
    @from = parse_date(params[:from]) || @to - 6.days

    @overall = PageLoadStat.overall_stats(@from, @to)
    @per_action = PageLoadStat.per_action_stats(@from, @to)
    @total_count = @overall.values.sum { |v| v[:count] }
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end

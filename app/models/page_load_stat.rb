class PageLoadStat < ApplicationRecord
  HISTOGRAM_BINS = [
    { index: 0, label: "0-50ms",   min: 0,    max: 50 },
    { index: 1, label: "50-100ms", min: 50,   max: 100 },
    { index: 2, label: "100-200ms", min: 100, max: 200 },
    { index: 3, label: "200-500ms", min: 200, max: 500 },
    { index: 4, label: "500ms-1s",  min: 500, max: 1000 },
    { index: 5, label: "1s+",       min: 1000, max: nil }
  ].freeze

  scope :in_range, ->(from, to) { where(created_at: from.beginning_of_day..to.end_of_day) }

  def self.overall_stats(from, to)
    rows = in_range(from, to)
      .select(
        "is_turbo",
        "COUNT(*) AS request_count",
        "percentile_cont(0.95) WITHIN GROUP (ORDER BY render_time) AS p95",
        "percentile_cont(0.99) WITHIN GROUP (ORDER BY render_time) AS p99",
        histogram_case_sql("bin")
      )
      .group("is_turbo", "bin")
      .order("is_turbo", "bin")

    grouped = { false => { p95: 0, p99: 0, count: 0, histogram: empty_histogram },
                true  => { p95: 0, p99: 0, count: 0, histogram: empty_histogram } }

    rows.each do |row|
      turbo = row.is_turbo
      bin = row[:bin].to_i
      grouped[turbo][:p95] = row[:p95].to_f
      grouped[turbo][:p99] = row[:p99].to_f
      grouped[turbo][:count] += row[:request_count].to_i
      grouped[turbo][:histogram][bin] = row[:request_count].to_i
    end

    grouped
  end

  def self.per_action_stats(from, to)
    in_range(from, to)
      .select(
        "controller",
        "action",
        "COUNT(*) AS request_count",
        "percentile_cont(0.95) WITHIN GROUP (ORDER BY render_time) AS p95",
        "percentile_cont(0.99) WITHIN GROUP (ORDER BY render_time) AS p99",
        "stddev(render_time) AS stddev"
      )
      .group("controller", "action")
      .order(Arel.sql("percentile_cont(0.95) WITHIN GROUP (ORDER BY render_time) DESC"))
  end

  def self.histogram_case_sql(as_name)
    Arel.sql(<<~SQL.squish)
      CASE
        WHEN render_time >= 0    AND render_time < 50   THEN 0
        WHEN render_time >= 50   AND render_time < 100  THEN 1
        WHEN render_time >= 100  AND render_time < 200  THEN 2
        WHEN render_time >= 200  AND render_time < 500  THEN 3
        WHEN render_time >= 500  AND render_time < 1000 THEN 4
        ELSE 5
      END AS #{as_name}
    SQL
  end

  def self.empty_histogram
    HISTOGRAM_BINS.each_with_object({}) { |bin, h| h[bin[:index]] = 0 }
  end
end

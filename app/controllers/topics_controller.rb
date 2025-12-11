class TopicsController < ApplicationController
  before_action :set_topic, only: [:show, :aware, :read_all]
  before_action :require_authentication, only: [:aware, :aware_bulk, :aware_all, :read_all]

  def index
    @search_query = nil
    base_query = Topic.includes(:creator)
    base_query = apply_filters(base_query)

    apply_cursor_pagination(base_query)

    preload_topic_states if user_signed_in?
    preload_note_counts if user_signed_in?
    load_visible_tags if user_signed_in?
    preload_participation_flags if user_signed_in?

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    messages_scope = @topic.messages.includes(:sender, reply_to: :sender)

    @view_mode = 'flat'
    @sort_order = :asc
    @messages = messages_scope.order(created_at: @sort_order)
    @message_numbers = @messages.each_with_index.to_h { |msg, idx| [msg.id, idx + 1] }
    preload_read_state!
    auto_mark_aware!

    build_participants_sidebar_data(messages_scope)
    build_thread_outline(messages_scope)
    load_notes if user_signed_in?
  end

  def aware
    last_id = params[:up_to_message_id].presence&.to_i || @topic.messages.maximum(:id)
    ThreadAwareness.mark_until(user: current_user, topic: @topic, until_message_id: last_id) if last_id
    respond_to do |format|
      format.json { render json: { status: "ok" } }
      format.html { head :ok }
    end
  end

  def aware_bulk
    topics_param = params[:topics]
    return render json: { error: "topics required" }, status: :unprocessable_entity unless topics_param.is_a?(Array)

    topics_param.each do |entry|
      topic = Topic.find_by(id: entry[:topic_id] || entry["topic_id"])
      next unless topic
      up_to = (entry[:up_to_message_id] || entry["up_to_message_id"]).to_i
      up_to = topic.messages.maximum(:id) if up_to.zero?
      ThreadAwareness.mark_until(user: current_user, topic:, until_message_id: up_to) if up_to
    end

    render json: { status: "ok" }
  end

  def aware_all
    timestamp = params[:before].present? ? Time.zone.parse(params[:before]) : Time.current
    current_user.update!(aware_before: [current_user.aware_before, timestamp].compact.max)

    render json: { status: "ok", aware_before: current_user.aware_before }
  end

  def read_all
    first_id = @topic.messages.minimum(:id)
    last_id = @topic.messages.maximum(:id)
    if first_id && last_id
      MessageReadRange.add_range(user: current_user, topic: @topic, start_id: first_id, end_id: last_id)
      ThreadAwareness.mark_until(user: current_user, topic: @topic, until_message_id: last_id)
    end

    respond_to do |format|
      format.json { render json: { status: "ok" } }
      format.html { redirect_to topic_path(@topic) }
    end
  end

  def search
    @search_query = params[:q].to_s.strip

    base_query = if @search_query.present?
                   Topic.joins(:messages)
                        .where("topics.title ILIKE ? OR messages.body ILIKE ?", "%#{@search_query}%", "%#{@search_query}%")
                        .distinct
                        .includes(:creator)
                 else
                   Topic.none
                 end

    apply_cursor_pagination(base_query)

    preload_participation_flags if user_signed_in?

    respond_to do |format|
      format.html
      format.turbo_stream { render :index }
    end
  end

  private

  def set_topic
    @topic = Topic.find(params[:id])
  end

  def build_participants_sidebar_data(messages_scope)
    participant_map = {}

    messages_scope.order(:created_at).each do |message|
      sender_id = message.sender_id
      entry = (participant_map[sender_id] ||= {
        alias: message.sender,
        message_count: 0,
        first_at: message.created_at,
        last_at: message.created_at
      })
      entry[:message_count] += 1
      entry[:first_at] = [entry[:first_at], message.created_at].min
      entry[:last_at] = [entry[:last_at], message.created_at].max
    end

    @participants = participant_map.values
                                   .sort_by { |entry| [-entry[:message_count], entry[:first_at]] }
  end

  def build_thread_outline(messages_scope)
    ordered_messages = messages_scope.order(:created_at)
    children = Hash.new { |h, k| h[k] = [] }
    ordered_messages.each do |msg|
      children[msg.reply_to_id] << msg
    end

    @thread_outline = []
    traverse_thread(children, children[nil], 0, 0, @thread_outline)

    # Assign branch colors based on visual sequence: keep color if replying to previous item, otherwise rotate.
    current_color = 0
    @thread_outline.each_with_index do |entry, idx|
      if idx.zero?
        entry[:branch_index] = current_color
        next
      end

      if entry[:branching_point]
        current_color = (current_color + 1) % 6
      end

      entry[:branch_index] = current_color
    end

    assign_branch_segments!
    @has_multiple_branches = @thread_outline.map { |entry| entry[:branch_segment_index] }.uniq.size > 1
  end

  def preload_read_state!
    return unless user_signed_in?

    ranges = MessageReadRange.where(user: current_user, topic: @topic)
                             .order(:range_start_message_id)
                             .pluck(:range_start_message_id, :range_end_message_id)
    @read_message_ids = {}
    return if ranges.empty?

    @messages.each do |msg|
      @read_message_ids[msg.id] = ranges.any? { |(s, e)| s <= msg.id && msg.id <= e }
    end
  end

  def auto_mark_aware!
    return unless user_signed_in?
    last_id = @messages.last&.id
    ThreadAwareness.mark_until(user: current_user, topic: @topic, until_message_id: last_id) if last_id
  end

  def traverse_thread(children, parent_nodes, depth, branch_depth, outline)
    return if parent_nodes.nil?

    branching_point = parent_nodes.size > 1

    parent_nodes.each do |node|
      has_multiple_children = children[node.id].size > 1
      outline << { message: node, depth: depth, branch_depth: branch_depth, branching_point: branching_point }
      child_branch_depth = branch_depth + (has_multiple_children ? 1 : 0)
      traverse_thread(children, children[node.id], depth + 1, child_branch_depth, outline)
    end
  end

  def assign_branch_segments!
    segment_index = 0
    idx = 0
    message_numbers = @message_numbers || {}

    while idx < @thread_outline.size
      start_idx = idx
      branch_id = @thread_outline[start_idx][:branch_index]

      idx += 1
      idx += 1 while idx < @thread_outline.size && @thread_outline[idx][:branch_index] == branch_id

      segment_size = idx - start_idx
      segment_entries = @thread_outline[start_idx...idx]

      segment_entries.each_with_index do |entry, relative_idx|
        entry[:branch_segment_index] = segment_index
        entry[:branch_start] = relative_idx.zero?
        entry[:branch_end] = relative_idx == segment_size - 1
        entry[:branch_size] = segment_size
        entry[:message_number] = message_numbers[entry[:message].id]
      end

      segment_index += 1
    end
  end

  def apply_cursor_pagination(base_query)
    @viewing_since = if params[:viewing_since].present?
                       Time.zone.parse(params[:viewing_since])
                     else
                       Time.current
                     end

    query_with_window = base_query.joins(:messages)
                                   .group('topics.id')
                                   .having('MAX(messages.created_at) <= ?', @viewing_since)
                                   .select('topics.*, MAX(messages.created_at) as last_activity')

    if params[:cursor].present?
      cursor_time, cursor_id = params[:cursor].split('_')
      @topics = query_with_window.having('(MAX(messages.created_at), topics.id) < (?, ?)',
                                          Time.zone.parse(cursor_time), cursor_id.to_i)
    else
      @topics = query_with_window
    end

    @topics = @topics.order('MAX(messages.created_at) DESC, topics.id DESC')
                     .limit(25)

    @new_topics_count = base_query.joins(:messages)
                                   .group('topics.id')
                                   .having('MAX(messages.created_at) > ?', @viewing_since)
                                   .count
                                   .size
  end

  def preload_topic_states
    topic_ids = @topics.map(&:id)
    return if topic_ids.empty?

    last_ids = Message.where(topic_id: topic_ids).group(:topic_id).maximum(:id)
    last_times = Message.where(topic_id: topic_ids).group(:topic_id).maximum(:created_at)
    total_counts = Message.where(topic_id: topic_ids).group(:topic_id).count

    if user_signed_in?
      aware_map = ThreadAwareness.where(user: current_user, topic_id: topic_ids)
                                 .pluck(:topic_id, :aware_until_message_id)
                                 .to_h
      read_rows = MessageReadRange.where(user: current_user, topic_id: topic_ids)
                                  .pluck(:topic_id, :range_start_message_id, :range_end_message_id)
      read_ranges = read_rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(tid, s, e), acc|
        acc[tid] << [s, e]
      end
      global_aware_before = current_user.aware_before

      team_readers = preload_team_reader_states(topic_ids, last_ids)
    end

    @topic_states = {}
    @topics.each do |topic|
      last_id = last_ids[topic.id]
      last_time = last_times[topic.id]
    if user_signed_in?
      aware_until = aware_map[topic.id]
      total = total_counts[topic.id].to_i
      ranges = read_ranges[topic.id] || []
      read_count = ranges.sum do |(s, e)|
        next 0 unless s && e
        (e - s + 1)
      end
      status = compute_topic_status(total:, last_time:, aware_until:, read_count:, global_aware_before:)
      progress = compute_progress(total:, read_count:)
    else
      status = :new
    end
      @topic_states[topic.id] = { status:, aware_until:, read_count:, last_id:, last_time:, progress:, team_readers: team_readers[topic.id] || [] }
    end
  end

  def preload_note_counts
    topic_ids = @topics.map(&:id)
    return if topic_ids.empty?

    @topic_note_counts = Note.visible_to(current_user)
                              .where(topic_id: topic_ids)
                              .active
                              .group(:topic_id)
                              .count
  end

  def load_visible_tags
    @available_note_tags = NoteTag.joins(:note)
                                  .merge(Note.active.visible_to(current_user))
                                  .group(:tag)
                                  .order(Arel.sql("COUNT(*) DESC"))
                                  .limit(20)
                                  .count
  end

  def preload_participation_flags
    topic_ids = @topics.map(&:id)
    return if topic_ids.empty?

    my_alias_ids = Alias.where(user_id: current_user.id).pluck(:id)

    team_ids = TeamMember.where(user_id: current_user.id).pluck(:team_id)
    teammate_user_ids = if team_ids.any?
                          TeamMember.where(team_id: team_ids).pluck(:user_id).uniq
                        else
                          [current_user.id]
                        end
    teammate_alias_ids = Alias.where(user_id: teammate_user_ids).pluck(:id)

    rows = Message.where(topic_id: topic_ids, sender_id: teammate_alias_ids)
                  .select(:topic_id, :sender_id)
                  .distinct

    alias_map = Alias.includes(:contributors).where(id: teammate_alias_ids).index_by(&:id)

    @participation_flags = Hash.new { |h, k| h[k] = { mine: false, team: false, aliases: [] } }

    rows.each do |row|
      entry = @participation_flags[row.topic_id]
      alias_record = alias_map[row.sender_id]
      next unless alias_record

      entry[:aliases] << alias_record
      entry[:mine] ||= my_alias_ids.include?(row.sender_id)
      entry[:team] = true
    end

    @participation_flags.transform_values! do |v|
      v[:aliases] = v[:aliases].uniq { |a| a.id }
      v
    end
  end

  def compute_topic_status(total:, last_time:, aware_until:, read_count:, global_aware_before:)
    return :new unless aware_until || read_count.positive? || global_aware_before
    return :read if total.positive? && read_count >= total
    return :reading if read_count.positive?

    if global_aware_before && last_time && last_time <= global_aware_before
      return :aware
    end

    return :aware if aware_until
    :new
  end

  def compute_progress(total:, read_count:)
    return 0 unless total.positive?
    return 1.0 if read_count >= total

    ratio = read_count.to_f / total.to_f
    [[ratio, 0].max, 1].min
  end

  def preload_team_reader_states(topic_ids, last_ids)
    return {} unless user_signed_in?

    team_ids = TeamMember.where(user_id: current_user.id).pluck(:team_id)
    return {} if team_ids.empty?

    memberships = TeamMember.where(team_id: team_ids).pluck(:user_id, :team_id)
    return {} if memberships.empty?

    team_users = User.includes(:aliases).where(id: memberships.map(&:first)).index_by(&:id)

    rows = MessageReadRange.where(user_id: memberships.map(&:first), topic_id: topic_ids)
                           .select(:topic_id, :user_id, "MAX(range_end_message_id) AS max_end")
                           .group(:topic_id, :user_id)

    result = Hash.new { |h, k| h[k] = [] }

    rows.each do |row|
      last_id = last_ids[row.topic_id]
      next unless last_id
      max_end = row.read_attribute(:max_end).to_i
      status = if max_end >= last_id
                 :read
               elsif max_end.positive?
                 :reading
               end
      next unless status
      user = team_users[row.user_id]
      next unless user
      reader_team_ids = memberships.select { |uid, _tid| uid == row.user_id }.map(&:second)
      result[row.topic_id] << { user: user, status: status, team_ids: reader_team_ids }
    end

    result
  end

  def apply_filters(base_query)
    filter = params[:filter].to_s
    team_id = params[:team_id].presence&.to_i
    current_user_id = current_user&.id
    tag_filter = params[:note_tag].to_s.strip.downcase

    if tag_filter.present? && user_signed_in?
      visible_notes = Note.active.visible_to(current_user)
      tagged_notes = visible_notes.joins(:note_tags).where(note_tags: { tag: tag_filter })
      note_topics = tagged_notes.select(:topic_id).distinct

      base_query = base_query.joins("INNER JOIN (#{note_topics.to_sql}) tagged_notes ON tagged_notes.topic_id = topics.id")
      @active_note_tag = tag_filter
    end

    case filter
    when "no_contrib_replies"
      base_query = base_query.joins(:messages)
                             .left_joins(messages: { sender: :contributors })
                             .group('topics.id')
                             .having('COUNT(contributors.id) = 0')
    when "patch_no_replies"
      base_query = base_query.joins(messages: :attachments)
                             .group('topics.id')
                             .having('COUNT(messages.id) = 1')
                             .where("attachments.file_name ILIKE ? OR attachments.file_name ILIKE ?", "%.patch", "%.diff")
    when "reading_incomplete"
      if current_user_id
        base_query = base_query.joins(:messages)
                               .joins("LEFT JOIN message_read_ranges mrr ON mrr.topic_id = topics.id AND mrr.user_id = #{current_user_id}")
                               .group('topics.id')
                               .having("COALESCE(MAX(mrr.range_end_message_id), 0) > 0")
                               .having("COALESCE(MAX(mrr.range_end_message_id), 0) < MAX(messages.id)")
      end
    when "new_for_me"
      if current_user_id
        aware_before = current_user&.aware_before || Time.at(0)
        base_query = base_query.joins(:messages)
                               .joins("LEFT JOIN message_read_ranges mrr ON mrr.topic_id = topics.id AND mrr.user_id = #{current_user_id}")
                               .group('topics.id')
                               .having("MAX(messages.created_at) > ?", aware_before)
                               .having("COALESCE(MAX(mrr.range_end_message_id), 0) < MAX(messages.id)")
      end
    when "team_unread"
      if team_id && current_user_id
        member_ids = TeamMember.where(team_id: team_id).select(:user_id)
        base_query = base_query.joins(:messages)
                               .where.not(id: MessageReadRange.where(user_id: member_ids).select(:topic_id))
                               .group('topics.id')
      end
    when "team_reading_others"
      if team_id && current_user_id
        teammate_ids = TeamMember.where(team_id: team_id).where.not(user_id: current_user_id).select(:user_id)
        base_query = base_query.joins(:messages)
                               .joins("LEFT JOIN message_read_ranges mrr_self ON mrr_self.topic_id = topics.id AND mrr_self.user_id = #{current_user_id}")
                               .joins("INNER JOIN message_read_ranges mrr_team ON mrr_team.topic_id = topics.id AND mrr_team.user_id IN (#{teammate_ids.to_sql})")
                               .group('topics.id')
                               .having("COALESCE(MAX(mrr_self.range_end_message_id), 0) < MAX(messages.id)")
      end
    when "team_reading_any"
      if team_id && current_user_id
        member_ids = TeamMember.where(team_id: team_id).select(:user_id)
        base_query = base_query.joins(:messages)
                               .joins("INNER JOIN message_read_ranges mrr_team ON mrr_team.topic_id = topics.id AND mrr_team.user_id IN (#{member_ids.to_sql})")
                               .group('topics.id')
      end
    when "started_by_me"
      if current_user_id
        my_alias_ids = Alias.where(user_id: current_user_id).select(:id)
        base_query = base_query.where(creator_id: my_alias_ids)
      end
    when "messaged_by_me"
      if current_user_id
        my_alias_ids = Alias.where(user_id: current_user_id).select(:id)
        base_query = base_query.joins(:messages).where(messages: { sender_id: my_alias_ids }).distinct
      end
    when "team_started"
      if team_id
        member_alias_ids = Alias.joins(user: :team_members).where(team_members: { team_id: team_id }).select(:id)
        base_query = base_query.where(creator_id: member_alias_ids)
      end
    when "team_messaged"
      if team_id
        member_alias_ids = Alias.joins(user: :team_members).where(team_members: { team_id: team_id }).select(:id)
        base_query = base_query.joins(:messages).where(messages: { sender_id: member_alias_ids }).distinct
      end
    end
    base_query
  end

  def apply_state_filters
    filter = params[:filter].to_s
    return if filter.blank?
    return unless @topic_states
    team_id = params[:team_id].presence&.to_i

    case filter
    when "reading_incomplete"
      @topics = @topics.select { |t| @topic_states.dig(t.id, :status) == :reading }
    when "new_for_me"
      aware_before = current_user.aware_before
      @topics = @topics.select do |t|
        state = @topic_states[t.id] || {}
        last_time = state[:last_time]
        last_id = state[:last_id]
        aware_until = state[:aware_until]
        status = state[:status]

        newer_than_global = aware_before.nil? || (last_time && last_time > aware_before)
        missing_latest = last_id && (!aware_until || aware_until < last_id)
        not_read = status != :read

        newer_than_global && missing_latest && not_read
      end
    when "team_unread"
      @topics = @topics.select do |t|
        team_readers = filter_team_readers(t, team_id: team_id)
        team_readers.empty?
      end
    when "team_reading_others"
      @topics = @topics.select do |t|
        state = @topic_states[t.id] || {}
        my_status = state[:status]
        team_readers = filter_team_readers(t, team_id: team_id)
        team_readers.any? && my_status != :read && my_status != :reading
      end
    when "team_reading_any"
      @topics = @topics.select do |t|
        team_readers = filter_team_readers(t, team_id: team_id)
        team_readers.any?
      end
    end

    topic_ids = @topics.map(&:id)
    @topic_states.slice!(*topic_ids) if topic_ids.any?
  end

  def filter_team_readers(topic, team_id:)
    readers = @topic_states.dig(topic.id, :team_readers) || []
    return readers unless team_id
    readers.select { |r| r[:team_id] == team_id }
  end

  def load_notes
    notes = Note.active.visible_to(current_user)
                .where(topic: @topic)
                .includes(:author, :note_tags, note_mentions: :mentionable)
                .order(:created_at)

    @notes_by_message = Hash.new { |h, k| h[k] = [] }
    notes.each do |note|
      key = note.message_id || :thread
      @notes_by_message[key] << note
    end
  end
end

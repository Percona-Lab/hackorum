class Alias < ApplicationRecord
  belongs_to :person
  belongs_to :user, optional: true
  has_many :topics, class_name: 'Topic', foreign_key: "creator_id", inverse_of: :creator
  has_many :messages, class_name: 'Message', foreign_key: "sender_id", inverse_of: :sender
  has_many :attachments, through: :messages

  validates :name, presence: true
  validates :email, presence: true
  validates :name, uniqueness: { scope: :email }


  scope :by_email, ->(email) {
    where("lower(trim(email)) = lower(trim(?))", email)
  }

  def gravatar_url(size: 80)
    require 'digest/md5'
    hash = Digest::MD5.hexdigest(email.downcase.strip)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end

  def contributor
    person
  end

  CONTRIBUTOR_RANK = {
    'core_team' => 1,
    'committer' => 2,
    'major_contributor' => 3,
    'significant_contributor' => 4,
    'past_major_contributor' => 5,
    'past_significant_contributor' => 6
  }.freeze

  def contributor?
    person&.contributor_memberships&.exists?
  end

  def contributor_type
    return nil unless person
    types = person.contributor_memberships.pluck(:contributor_type)
    types.min_by { |t| CONTRIBUTOR_RANK[t] || 99 }
  end

  def core_team?
    person&.contributor_memberships&.core_team&.exists?
  end

  def committer?
    person&.contributor_memberships&.committer&.exists?
  end

  def past_contributor?
    person&.contributor_memberships&.where(contributor_type: %w[past_major_contributor past_significant_contributor])&.exists?
  end

  def current_contributor?
    contributor? && !past_contributor?
  end

  def major_contributor?
    person&.contributor_memberships&.major_contributor&.exists?
  end

  def significant_contributor?
    person&.contributor_memberships&.significant_contributor&.exists?
  end

  def contributor_badge
    return nil unless contributor?

    case contributor_type
    when 'core_team' then 'Core Team'
    when 'committer' then 'Committer'
    when 'major_contributor' then 'Major Contributor'
    when 'significant_contributor' then 'Contributor'
    when 'past_major_contributor' then 'Past Contributor'
    when 'past_significant_contributor' then 'Past Contributor'
    end
  end

end

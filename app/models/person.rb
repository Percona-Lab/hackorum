class Person < ApplicationRecord
  has_one :user
  has_many :aliases
  has_many :contributor_memberships, dependent: :destroy

  belongs_to :default_alias, class_name: 'Alias', optional: true

  def display_name
    default_alias&.name || aliases.order(:created_at).first&.name || "Unknown"
  end

  def contributor_type
    return nil unless contributor_memberships.exists?
    types = contributor_memberships.pluck(:contributor_type)
    types.min_by { |t| Alias::CONTRIBUTOR_RANK[t] || 99 }
  end

  def contributor_badge
    case contributor_type
    when 'core_team' then 'Core Team'
    when 'committer' then 'Committer'
    when 'major_contributor' then 'Major Contributor'
    when 'significant_contributor' then 'Contributor'
    when 'past_major_contributor' then 'Past Contributor'
    when 'past_significant_contributor' then 'Past Contributor'
    end
  end

  def self.find_by_email(email)
    Alias.by_email(email).where.not(person_id: nil).includes(:person).first&.person
  end

  def self.find_or_create_by_email(email)
    find_by_email(email) || create!
  end

  def self.attach_alias_group!(email, person:, user: nil)
    scope = Alias.by_email(email)
    scope = scope.where(user_id: [nil, user.id]) if user
    scope.update_all(person_id: person.id)
  end

  def attach_alias!(alias_record, user: nil)
    old_person = alias_record.person
    alias_record.update!(person_id: id, user_id: user&.id || alias_record.user_id)
    if old_person && old_person.id != id
      merge_contributor_memberships_from(old_person)
      cleanup_orphaned_person(old_person)
    end
  end

  def cleanup_orphaned_person(person)
    return if person.user.present?
    return if Alias.where(person_id: person.id).exists?
    person.destroy!
  end

  def merge_contributor_memberships_from(other_person)
    other_person.contributor_memberships.find_each do |membership|
      ContributorMembership.find_or_create_by!(person_id: id, contributor_type: membership.contributor_type) do |record|
        record.description = membership.description
      end
    end
  end
end

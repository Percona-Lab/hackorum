class Message < ApplicationRecord
  belongs_to :topic
  belongs_to :sender, class_name: 'Alias', inverse_of: :messages, counter_cache: :sender_count
  belongs_to :sender_person, class_name: 'Person'
  belongs_to :reply_to, class_name: 'Message', inverse_of: :replies, optional: true

  has_many :replies, class_name: 'Message', foreign_key: "reply_to_id", inverse_of: :reply_to
  has_many :attachments

  has_many :mentions
  has_many :mentioned_aliases, through: :mentions, source: :alias
  has_many :notes

  validates :subject, presence: true
  # Body may be blank for some historical imports; allow blank but keep presence on subject.
  validates :body, presence: true, allow_blank: true
  validates :message_id, uniqueness: true, allow_nil: true

  def sender_display_alias
    sender_person&.default_alias || sender
  end
end

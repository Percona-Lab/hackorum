class AddTrigramIndexesForSearch < ActiveRecord::Migration[8.0]
  def up
    # Enable pg_trgm extension for trigram-based text search
    enable_extension 'pg_trgm'

    # Add GIN trigram indexes for efficient ILIKE searches
    add_index :topics, :title, using: :gin, opclass: :gin_trgm_ops, name: 'index_topics_on_title_trgm'
    add_index :messages, :body, using: :gin, opclass: :gin_trgm_ops, name: 'index_messages_on_body_trgm'
  end

  def down
    remove_index :topics, name: 'index_topics_on_title_trgm'
    remove_index :messages, name: 'index_messages_on_body_trgm'
    # Note: Not disabling pg_trgm extension as it might be used elsewhere
  end
end

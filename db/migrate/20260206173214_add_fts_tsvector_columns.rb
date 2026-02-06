# frozen_string_literal: true

class AddFtsTsvectorColumns < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Add generated tsvector column for topics.title
    execute <<-SQL
      ALTER TABLE topics
      ADD COLUMN title_tsv tsvector
      GENERATED ALWAYS AS (to_tsvector('english', COALESCE(title, ''))) STORED;
    SQL

    # Create GIN index on topics.title_tsv (CONCURRENTLY to avoid locking)
    execute <<-SQL
      CREATE INDEX CONCURRENTLY index_topics_on_title_tsv
      ON topics USING gin(title_tsv);
    SQL

    # Add generated tsvector column for messages.body
    execute <<-SQL
      ALTER TABLE messages
      ADD COLUMN body_tsv tsvector
      GENERATED ALWAYS AS (to_tsvector('english', COALESCE(body, ''))) STORED;
    SQL

    # Create GIN index on messages.body_tsv (CONCURRENTLY to avoid locking)
    execute <<-SQL
      CREATE INDEX CONCURRENTLY index_messages_on_body_tsv
      ON messages USING gin(body_tsv);
    SQL
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS index_messages_on_body_tsv"
    execute "ALTER TABLE messages DROP COLUMN IF EXISTS body_tsv"

    execute "DROP INDEX CONCURRENTLY IF EXISTS index_topics_on_title_tsv"
    execute "ALTER TABLE topics DROP COLUMN IF EXISTS title_tsv"
  end
end

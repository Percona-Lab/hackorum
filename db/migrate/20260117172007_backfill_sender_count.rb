class BackfillSenderCount < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      UPDATE aliases
      SET sender_count = (
        SELECT COUNT(*)
        FROM messages
        WHERE messages.sender_id = aliases.id
      )
    SQL
  end

  def down
    # sender_count will be recalculated if needed
    execute "UPDATE aliases SET sender_count = 0"
  end
end

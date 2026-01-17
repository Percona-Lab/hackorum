class AddSenderCountToAliases < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :aliases, :sender_count, :integer, default: 0, null: false
    add_index :aliases, :sender_count, algorithm: :concurrently
  end
end

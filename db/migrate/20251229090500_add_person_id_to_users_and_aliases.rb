class AddPersonIdToUsersAndAliases < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :person_id, :bigint
    add_column :aliases, :person_id, :bigint

    add_index :users, :person_id
    add_index :aliases, :person_id
    add_foreign_key :users, :people
    add_foreign_key :aliases, :people
    add_foreign_key :people, :aliases, column: :default_alias_id
  end
end

class CreatePeople < ActiveRecord::Migration[8.0]
  def change
    create_table :people do |t|
      t.bigint :default_alias_id

      t.timestamps
    end

    add_index :people, :default_alias_id
  end
end

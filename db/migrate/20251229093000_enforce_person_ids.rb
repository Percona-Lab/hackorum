class EnforcePersonIds < ActiveRecord::Migration[8.0]
  def change
    change_column_null :users, :person_id, false
    change_column_null :aliases, :person_id, false
  end
end

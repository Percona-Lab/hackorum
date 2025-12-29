class DropContributorModels < ActiveRecord::Migration[8.0]
  def change
    drop_table :aliases_contributors, if_exists: true
    drop_table :contributors, if_exists: true
  end
end

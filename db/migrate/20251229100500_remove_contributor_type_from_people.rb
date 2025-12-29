class RemoveContributorTypeFromPeople < ActiveRecord::Migration[8.0]
  def change
    remove_column :people, :contributor_type, :contributor_type, if_exists: true
  end
end

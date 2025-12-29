class AddDetailsToContributorMemberships < ActiveRecord::Migration[8.0]
  def change
    change_column_null :contributor_memberships, :person_id, true
    add_column :contributor_memberships, :name, :string
    add_column :contributor_memberships, :email, :string
    add_column :contributor_memberships, :company, :string
  end
end

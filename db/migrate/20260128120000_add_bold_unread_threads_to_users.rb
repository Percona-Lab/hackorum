# frozen_string_literal: true

class AddBoldUnreadThreadsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :bold_unread_threads, :boolean, default: false, null: false
  end
end

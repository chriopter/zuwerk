class AddPromptSnapshotToBoardPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :board_posts, :prompt_snapshot, :text, null: false, default: ""
    change_column_default :board_posts, :prompt_snapshot, from: "", to: nil
  end
end

class CreateTodosAndTodoComments < ActiveRecord::Migration[8.1]
  def change
    create_table :todos do |t|
      t.references :project, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    create_table :todo_comments do |t|
      t.references :todo, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end

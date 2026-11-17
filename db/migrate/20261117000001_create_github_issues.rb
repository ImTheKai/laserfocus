class CreateGithubIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :github_issues do |t|
      t.string :repo, null: false
      t.integer :number, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.string :author
      t.string :author_association
      t.datetime :opened_at, null: false
      t.datetime :github_updated_at
      t.json :labels, default: []
      t.json :assignees, default: []
      # The last comments, oldest first: { "login", "team", "at" }. Bots left out.
      t.json :comments, default: []
      t.integer :comment_count, default: 0, null: false
      t.json :people_names, default: {}
      t.string :stage, null: false
      t.string :waiting_on, null: false
      t.datetime :waiting_since, null: false
      t.timestamps
    end
    add_index :github_issues, [ :repo, :number ], unique: true

    # One table of GitHub sync runs, told apart by what they read.
    add_column :review_sync_runs, :kind, :string, default: "pulls", null: false
  end
end

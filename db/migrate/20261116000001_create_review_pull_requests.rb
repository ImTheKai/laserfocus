class CreateReviewPullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :review_pull_requests do |t|
      t.string :repo, null: false
      t.integer :number, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.string :author
      t.string :author_association
      t.string :head_ref
      t.datetime :opened_at, null: false
      t.datetime :ready_at
      t.datetime :last_push_at
      t.datetime :github_updated_at
      t.string :review_decision
      t.string :ci_state
      t.integer :additions, default: 0, null: false
      t.integer :deletions, default: 0, null: false
      t.json :labels, default: []
      t.json :reviews, default: []
      t.json :requested_reviewers, default: []
      t.json :jira_keys, default: []
      t.string :stage, null: false
      t.string :waiting_on, null: false
      t.datetime :waiting_since, null: false
      t.timestamps
    end
    add_index :review_pull_requests, [ :repo, :number ], unique: true

    create_table :review_sync_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.boolean :ok, default: false, null: false
      t.integer :fetched_count, default: 0, null: false
      t.text :error_message
      t.timestamps
    end
  end
end

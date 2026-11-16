class AddPeopleNamesToReviewPullRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :review_pull_requests, :people_names, :json, default: {}
  end
end

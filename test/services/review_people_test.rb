require "test_helper"

class ReviewPeopleTest < ActiveSupport::TestCase
  def users = [
    OpenStruct.new(display_name: "Zsolt Parragi"),
    OpenStruct.new(display_name: "Andreas Karlsson", github: "jeltz"),
    OpenStruct.new(display_name: "José Núñez")
  ]

  def people(**kw) = ReviewPeople.new(names: { "dutow" => "Zsolt  Parragi", "JN" => "jose nunez", "geoHeil" => "Georg Heiler" }, users: users, **kw)

  test "links a login to a team member by the GitHub profile name" do
    assert_equal "Zsolt Parragi", people.member("Dutow").display_name
    assert_equal "José Núñez", people.member("jn").display_name
  end

  test "a github override wins, even without a profile name" do
    assert_equal "Andreas Karlsson", people.member("jeltz").display_name
  end

  test "shows Jira names for the team, GitHub names or logins for others" do
    assert_equal "Zsolt Parragi", people.display("dutow")
    assert_equal "Georg Heiler", people.display("geoHeil")
    assert_equal "someone", people.display("someone")
    assert_not people.team?("geoHeil")
  end

  test "lists team members no login linked to" do
    assert_equal [ "José Núñez" ], people.unmatched_members(%w[dutow jeltz]).map(&:display_name)
  end

  test "recognises the viewer by name or by github override" do
    assert people(viewer_name: "zsolt parragi").me?("dutow")
    assert people(viewer_github: "JELTZ").me?("jeltz")
    assert_not people(viewer_name: "Zsolt Parragi").me?("geoHeil")
    assert_not people.viewer?
  end
end

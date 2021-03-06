require "test_helper"

class GithubAccountTest < ActiveSupport::TestCase
  should validate_presence_of(:name)
  should validate_uniqueness_of(:name)
  should have_many(:projects)
end

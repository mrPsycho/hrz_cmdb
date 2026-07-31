#-------------------------------------------------------------------------------------------#
# Redmine CMDB plugin: Configuration Management DataBase                                    #
# Copyright (C) 2025 Franz Apeltauer                                                        #
#                                                                                           #
# This program is free software: you can redistribute it and/or modify it under the terms   #
# of the GNU Affero General Public License as published by the Free Software Foundation,    #
# either version 3 of the License, or (at your option) any later version.                   #
#                                                                                           #
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; #
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. #
# See the GNU Affero General Public License for more details.                               #
#                                                                                           #
# You should have received a copy of the GNU Affero General Public License                  #
# along with this program.  If not, see <https://www.gnu.org/licenses/>.                    #
#-------------------------------------------------------------------------------------eohdr-#
# Purpose: Integration tests for the REST API that links configuration items to Redmine issues.

require File.expand_path('../../../test_helper', __FILE__)

class Redmine::ApiTest::IssueCisApiTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :enabled_modules, :issues, :issue_statuses, :trackers, :projects_trackers,
           :enumerations,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class,
           :hrzcm_lifecycle_status, :hrzcm_ci

  # Enables the REST API, activates the cmdb module for project 1 and grants both CI
  # permissions to the Manager role, which user jsmith holds in that project.
  def setup
    super
    @project = Project.find(1)
    @project.enable_module!('cmdb')
    Role.find(1).add_permission!(:view_issue_cis, :manage_issue_cis)
    @jsmith = credentials('jsmith')
  end

  # Removes the permissions again so that they do not leak into other test cases.
  def teardown
    Role.find(1).remove_permission!(:view_issue_cis, :manage_issue_cis)
    super
  end

  test "should reject anonymous request for issue cis" do
    get '/issues/1/cis.json'
    assert_response :unauthorized
  end

  test "should reject request of user without view_issue_cis permission" do
    Role.find(1).remove_permission!(:view_issue_cis, :manage_issue_cis)
    get '/issues/1/cis.json', :headers => @jsmith
    assert_response :forbidden
  end

  test "should return 404 for an issue the user must not see" do
    Issue.find(1).update_columns(:is_private => true)
    get '/issues/1/cis.json', :headers => credentials('dlopper')
    assert_response :not_found
  end

  test "should index cis of an issue" do
    HrzcmCiIssue.create!(:ci_id => 1, :issue_id => 1)

    get '/issues/1/cis.json', :headers => @jsmith
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['total_count']
    assert_equal 1, json['hrzcm_cis'].first['id']
  end

  test "should link a ci to an issue" do
    assert_difference 'HrzcmCiIssue.count' do
      post '/issues/1/cis.json', :params => { :ci_id => 2 }, :headers => @jsmith
    end
    assert_response :created

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['hrzcm_ci']['id']
  end

  test "should not link the same ci twice" do
    HrzcmCiIssue.create!(:ci_id => 2, :issue_id => 1)

    assert_no_difference 'HrzcmCiIssue.count' do
      post '/issues/1/cis.json', :params => { :ci_id => 2 }, :headers => @jsmith
    end
    assert_response :unprocessable_entity
  end

  test "should return 404 when linking an unknown ci" do
    assert_no_difference 'HrzcmCiIssue.count' do
      post '/issues/1/cis.json', :params => { :ci_id => 999999 }, :headers => @jsmith
    end
    assert_response :not_found
  end

  test "should unlink a ci from an issue" do
    HrzcmCiIssue.create!(:ci_id => 2, :issue_id => 1)

    assert_difference 'HrzcmCiIssue.count', -1 do
      delete '/issues/1/cis/2.json', :headers => @jsmith
    end
    assert_response :no_content
  end

  test "should return 404 when unlinking a ci that is not linked" do
    delete '/issues/1/cis/3.json', :headers => @jsmith
    assert_response :not_found
  end
end

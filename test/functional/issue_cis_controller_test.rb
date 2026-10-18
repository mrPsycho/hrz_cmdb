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
# Purpose: Functional tests for IssueCisController covering the browser (non-API) paths:
#          linking/unlinking CIs to issues, the issue journal those actions write,
#          the CI selection tree (available_cis) and all permission/visibility checks.
#          Requests are sent like the plugin's own AJAX calls: xhr, Accept: application/json and
#          no .json format extension, so that api_request? is false and the session login applies.

require File.expand_path('../../test_helper', __FILE__)

class IssueCisControllerTest < ActionController::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :enabled_modules, :issues, :issue_statuses, :trackers, :projects_trackers,
           :enumerations, :journals, :journal_details,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class,
           :hrzcm_lifecycle_status, :hrzcm_ci

  # Activates the cmdb module for project 1, grants both CI permissions to the Manager role,
  # which user jsmith (id 2) holds in that project, logs jsmith in and sends the requests
  # with the Accept header of the plugin's AJAX calls.
  # Side effects: writes enabled_modules and roles (rolled back by the test transaction)
  def setup
    @project = Project.find(1)
    @project.enable_module!('cmdb')
    Role.find(1).add_permission!(:view_issue_cis, :manage_issue_cis)
    @issue = Issue.find(1)
    @request.session[:user_id] = 2
    @request.headers['Accept'] = 'application/json'
  end

  # Removes the permissions and plugin settings again so that they do not leak into other
  # test cases.
  def teardown
    Role.find(1).remove_permission!(:view_issue_cis, :manage_issue_cis)
    Setting.plugin_hrz_cmdb = {}
  end

  # Returns the journals of issue 1, newest last.
  # Returns: ActiveRecord::Relation of Journal
  def issue_journals
    Journal.where(:journalized_type => 'Issue', :journalized_id => @issue.id).order(:id)
  end

  test "should link ci and return ui json envelope" do
    assert_difference 'HrzcmCiIssue.count', 1 do
      post :create, params: { issue_id: @issue.id, ci_id: 2 }, xhr: true
    end
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal true, json['success']
    assert json['html'].is_a?(String)
    assert json['html'].present?
    assert_equal I18n.t(:notice_ci_added, :locale => :en), json['notice']
    assert HrzcmCiIssue.exists?(ci_id: 2, issue_id: @issue.id)
  end

  test "should journal linking without notes and with a ci relation detail" do
    assert_difference 'Journal.count', 1 do
      assert_difference 'JournalDetail.count', 1 do
        post :create, params: { issue_id: @issue.id, ci_id: 2 }, xhr: true
      end
    end
    assert_response :success

    journal = issue_journals.last
    assert journal.notes.blank?, "journal notes must be blank, got #{journal.notes.inspect}"
    assert_equal 2, journal.user_id
    assert_equal 1, journal.details.size

    detail = journal.details.first
    assert_equal 'relation', detail.property
    assert_equal 'ci', detail.prop_key
    assert_equal '2', detail.value.to_s
    assert_nil detail.old_value
  end

  test "should not link the same ci twice" do
    HrzcmCiIssue.create!(ci_id: 2, issue_id: @issue.id)

    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      post :create, params: { issue_id: @issue.id, ci_id: 2 }, xhr: true
    end
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal false, json['success']
    assert json['errors'].any?
  end

  test "should return 404 when linking an unknown ci" do
    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      post :create, params: { issue_id: @issue.id, ci_id: 999999 }, xhr: true
    end
    assert_response :not_found
  end

  test "should unlink ci and return ui json envelope" do
    HrzcmCiIssue.create!(ci_id: 2, issue_id: @issue.id)

    assert_difference 'HrzcmCiIssue.count', -1 do
      delete :destroy, params: { issue_id: @issue.id, id: 2 }, xhr: true
    end
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal true, json['success']
    assert_equal I18n.t(:notice_ci_removed, :locale => :en), json['notice']
    assert_not HrzcmCiIssue.exists?(ci_id: 2, issue_id: @issue.id)
  end

  test "should journal unlinking without notes and with a ci relation detail" do
    HrzcmCiIssue.create!(ci_id: 2, issue_id: @issue.id)

    assert_difference 'Journal.count', 1 do
      assert_difference 'JournalDetail.count', 1 do
        delete :destroy, params: { issue_id: @issue.id, id: 2 }, xhr: true
      end
    end
    assert_response :success

    journal = issue_journals.last
    assert journal.notes.blank?, "journal notes must be blank, got #{journal.notes.inspect}"
    assert_equal 1, journal.details.size

    detail = journal.details.first
    assert_equal 'relation', detail.property
    assert_equal 'ci', detail.prop_key
    assert_equal '2', detail.old_value.to_s
    assert_nil detail.value
  end

  test "should answer success false when unlinking a ci that is not linked" do
    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      delete :destroy, params: { issue_id: @issue.id, id: 3 }, xhr: true
    end
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal false, json['success']
    assert json['errors'].any?
  end

  test "should deny linking without manage_issue_cis permission" do
    Role.find(1).remove_permission!(:manage_issue_cis)

    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      post :create, params: { issue_id: @issue.id, ci_id: 2 }, xhr: true
    end
    assert_response :forbidden
  end

  test "should deny unlinking without manage_issue_cis permission" do
    HrzcmCiIssue.create!(ci_id: 2, issue_id: @issue.id)
    Role.find(1).remove_permission!(:manage_issue_cis)

    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      delete :destroy, params: { issue_id: @issue.id, id: 2 }, xhr: true
    end
    assert_response :forbidden
  end

  test "should deny linking when the cmdb module is disabled" do
    @project.disable_module!('cmdb')

    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      post :create, params: { issue_id: @issue.id, ci_id: 2 }, xhr: true
    end
    assert_response :forbidden
  end

  test "should deny available_cis when the cmdb module is disabled" do
    @project.disable_module!('cmdb')

    get :available_cis, params: { issue_id: @issue.id }, xhr: true
    assert_response :forbidden
  end

  test "should return 404 for an issue the user must not see" do
    @issue.update_columns(:is_private => true)
    @request.session[:user_id] = 3

    assert_no_difference ['HrzcmCiIssue.count', 'Journal.count'] do
      post :create, params: { issue_id: @issue.id, ci_id: 2 }, xhr: true
    end
    assert_response :not_found
  end

  test "should get available_cis root level for permitted user" do
    get :available_cis, params: { issue_id: @issue.id }, xhr: true
    assert_response :success

    json = JSON.parse(response.body)
    assert json.is_a?(Array)
    assert json.any? { |node| node['id'] == 'ci_class_1' && node['type'] == 'ci_class' }
  end

  test "should get available_cis of a ci class without already linked cis" do
    HrzcmCiIssue.create!(ci_id: 1, issue_id: @issue.id)

    get :available_cis, params: { issue_id: @issue.id, parent_id: 'ci_class_2' }, xhr: true
    assert_response :success

    json = JSON.parse(response.body)
    ci_ids = json.select { |node| node['type'] == 'ci' }.map { |node| node['id'] }
    assert_includes ci_ids, 2
    assert_not_includes ci_ids, 1
  end

  test "should allow available_cis with view_issue_cis permission only" do
    Role.find(1).remove_permission!(:manage_issue_cis)

    get :available_cis, params: { issue_id: @issue.id }, xhr: true
    assert_response :success
  end

  test "should deny available_cis without view_issue_cis permission" do
    Role.find(1).remove_permission!(:view_issue_cis, :manage_issue_cis)

    get :available_cis, params: { issue_id: @issue.id }, xhr: true
    assert_response :forbidden
  end
end

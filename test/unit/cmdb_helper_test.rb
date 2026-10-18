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
# Purpose: Unit tests for the CI change history helpers in CmdbHelper (action labels and the
#          formatting of stored changes, issue links and legacy entries).

require File.expand_path('../../test_helper', __FILE__)

class CmdbHelperTest < Redmine::HelperTest
  include ApplicationHelper
  include CmdbHelper
  include ERB::Util
  include Rails.application.routes.url_helpers

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :issue_statuses, :enumerations, :issues,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class, :hrzcm_lifecycle_status,
           :hrzcm_ci, :hrzcm_ci_history

  # Builds an unsaved history entry for formatting tests.
  # Parameter action: String b_action
  # Parameter details: Hash serialised to JSON, or String stored as it is
  # Returns: HrzcmCiHistory instance
  def history_entry(action, details)
    HrzcmCiHistory.new(j_ci_id: 1, b_action: action,
                       b_details: details.is_a?(Hash) ? details.to_json : details)
  end

  test "ci_history_action_label should translate known actions" do
    assert_equal 'Created', ci_history_action_label(history_entry('created', nil))
    assert_equal 'Updated', ci_history_action_label(history_entry('updated', nil))
    assert_equal 'Linked to issue', ci_history_action_label(history_entry('issue_linked', nil))
    assert_equal 'Unlinked from issue', ci_history_action_label(history_entry('issue_unlinked', nil))
  end

  test "ci_history_action_label should fall back for blank and unknown actions" do
    assert_equal 'Updated', ci_history_action_label(history_entry('', nil))
    assert_equal 'imported', ci_history_action_label(history_entry('imported', nil))
  end

  test "format_ci_history_details should show old and new values of a change" do
    entry = history_entry('updated', 'changes' => [
      { 'field' => 'j_assigned_user_id', 'old' => 'John Smith', 'new' => 'Dave Lopper' }
    ])
    assert_equal '<strong>Assigned user</strong> changed from <i>John Smith</i> to <i>Dave Lopper</i>',
                 format_ci_history_details(entry)
  end

  test "format_ci_history_details should show set and removed values on separate lines" do
    entry = history_entry('updated', 'changes' => [
      { 'field' => 'j_location_id', 'old' => nil, 'new' => 'RM: 101' },
      { 'field' => 'j_assigned_user_id', 'old' => 'John Smith', 'new' => nil },
      { 'field' => 'b_comment' }
    ])
    html = format_ci_history_details(entry)

    assert_equal 3, html.split('<br>').size
    assert_includes html, '<strong>Location</strong> set to <i>RM: 101</i>'
    assert_includes html, '<strong>Assigned user</strong> deleted (<i>John Smith</i>)'
    assert_includes html, '<strong>Comment</strong> updated'
  end

  test "format_ci_history_details should list initial values of a created entry" do
    entry = history_entry('created', 'changes' => [{ 'field' => 'j_location_id', 'new' => 'RM: 101' }])
    assert_equal '<strong>Location</strong> set to <i>RM: 101</i>', format_ci_history_details(entry)
  end

  test "format_ci_history_details should escape stored values" do
    entry = history_entry('updated', 'changes' => [
      { 'field' => 'b_model', 'old' => '<b>old</b>', 'new' => '<script>alert(1)</script>' }
    ])
    html = format_ci_history_details(entry)

    assert html.html_safe?
    assert_not_includes html, '<script>'
    assert_includes html, '&lt;script&gt;alert(1)&lt;/script&gt;'
  end

  test "format_ci_history_details should link a visible issue" do
    User.current = User.find(1)
    html = format_ci_history_details(history_entry('issue_linked', 'issue_id' => 1))
    assert_includes html, 'href="/issues/1"'
  end

  test "format_ci_history_details should not reveal an issue the user cannot see" do
    Issue.find(1).update_columns(is_private: true)
    User.current = User.anonymous
    html = format_ci_history_details(history_entry('issue_unlinked', 'issue_id' => 1))

    assert_equal '#1', html
    assert_not_includes html, Issue.find(1).subject
  end

  test "format_ci_history_details should translate legacy column lists" do
    assert_equal 'Full name, Location', format_ci_history_details(HrzcmCiHistory.find(1))
  end

  test "format_ci_history_details should hide legacy default texts" do
    assert_equal '', format_ci_history_details(history_entry('created', 'Asset created'))
    assert_equal '', format_ci_history_details(history_entry('updated', 'Asset updated'))
    assert_equal '', format_ci_history_details(history_entry('updated', nil))
  end

  test "ci_history_field_label should keep unknown column names" do
    assert_equal 'Location', ci_history_field_label('j_location_id')
    assert_equal 'no_such_column', ci_history_field_label('no_such_column')
  end
end

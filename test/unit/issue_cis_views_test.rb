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
# Purpose: View tests for the CI section on issue pages (_issue_cis_section and _ci_row partials):
#          CMDB deep link vs. plain text depending on view_cmdb, full location path, assigned user
#          column, matching column counts and the always rendered, translated table skeleton.

require File.expand_path('../../test_helper', __FILE__)

class IssueCisViewsTest < Redmine::HelperTest
  include ApplicationHelper
  # The partials use Redmine's view helpers (link_to_user, l, ...).
  helper ApplicationHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :issue_statuses, :enumerations, :issues,
           :enabled_modules,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class, :hrzcm_lifecycle_status,
           :hrzcm_ci, :hrzcm_ci_history

  # Prepares issue 1 (project 1 with the CMDB module) and CI 1 (WEB01 in MB › 1F › 101).
  def setup
    super
    @project = Project.find(1)
    @project.enable_module!('cmdb')
    @issue = Issue.find(1)
    @ci = HrzcmCi.find(1)
  end

  # Renders the CI row partial for @ci and @issue inside a table, because an HTML parser drops
  # a <tr> that has no table context.
  # Returns: String HTML "<table><tbody><tr class=\"ci-row\">...</tr></tbody></table>"
  def render_row
    "<table><tbody>#{render(partial: 'issue_cis/ci_row', locals: { ci: @ci, issue: @issue })}</tbody></table>"
  end

  # Renders the CI section partial for @issue.
  # Returns: String HTML of the section
  def render_section
    render(partial: 'issue_cis/issue_cis_section')
  end

  test "ci_row should link the CI name to the CMDB deep link for users with view_cmdb" do
    User.current = user_with_cmdb_permission('view_cmdb')
    html = render_row

    assert_includes html, 'href="/cmdb?ci_id=1"'
    assert_not_includes html, 'show_ci'
    assert_select_in html, 'td.ci-name a.ci-link', text: 'WEB01'
  end

  test "ci_row should show the CI name as plain text without view_cmdb" do
    User.current = user_without_cmdb_permission
    html = render_row

    assert_not_includes html, '/cmdb?ci_id='
    assert_select_in html, 'td.ci-name a', 0
    assert_select_in html, 'td.ci-name', text: 'WEB01'
  end

  test "ci_row should escape the CI name shown as plain text" do
    User.current = user_without_cmdb_permission
    @ci.b_name_abbr = '<b>X</b>'
    html = render_row

    assert_not_includes html, '<b>X</b>'
    assert_includes html, '&lt;b&gt;X&lt;/b&gt;'
  end

  test "ci_row should show the full location path" do
    User.current = User.find(1)
    assert_select_in render_row, 'td.ci-location', text: 'MB › 1F › 101'
  end

  test "ci_row should show a dash without location" do
    User.current = User.find(1)
    @ci.j_location_id = nil
    assert_select_in render_row, 'td.ci-location', text: '-'
  end

  test "ci_row should link the assigned user" do
    User.current = User.find(1)
    @ci.update_columns(j_assigned_user_id: 3)
    @ci.reload
    html = render_row

    assert_select_in html, 'td.ci-holder a[href="/users/3"]', text: User.find(3).name
  end

  test "ci_row should show a dash without assigned user" do
    User.current = User.find(1)
    assert_select_in render_row, 'td.ci-holder', text: '-'
  end

  test "ci_row should have as many cells as the section has column headers" do
    [User.find(1), user_without_cmdb_permission, User.anonymous].each do |user|
      User.current = user
      HrzcmCiIssue.where(issue_id: @issue.id).delete_all
      HrzcmCiIssue.create!(ci_id: @ci.id, issue_id: @issue.id)
      @issue.reload

      section = render_section
      next if section.blank?

      header_count = Nokogiri::HTML(section).css('table.issue-cis-table thead th').size
      cell_count = Nokogiri::HTML(render_row).css('tr.ci-row td').size
      assert_equal 6, header_count if @issue.editable?
      assert_equal header_count, cell_count, "column mismatch for #{user.login}"
    end
  end

  test "section should render the holder column header translated" do
    User.current = User.find(1)
    HrzcmCiIssue.create!(ci_id: @ci.id, issue_id: @issue.id)
    @issue.reload

    html = render_section
    assert_select_in html, 'table.issue-cis-table thead th', text: 'Assigned user'
    assert_select_in html, 'tbody#ci-rows tr.ci-row', 1
    assert_select_in html, 'table.issue-cis-table[style*="display: none"]', 0
  end

  test "section should render a hidden table skeleton when no CI is linked" do
    User.current = User.find(1)
    HrzcmCiIssue.where(issue_id: @issue.id).delete_all
    @issue.reload

    html = render_section
    assert_select_in html, 'table.issue-cis-table[style*="display: none"] thead th', 6
    assert_select_in html, 'tbody#ci-rows tr', 0
  end

  test "section should pass translated messages to the JavaScript" do
    User.current = User.find(1)
    ::I18n.locale = 'de'
    html = render_section
    section = Nokogiri::HTML(html).at_css('#issue-cis-section')
    messages = JSON.parse(section['data-ci-messages'])

    assert_equal 'CI konnte nicht hinzugefügt werden', messages['add_failed']
    %w[load_failed add_failed add_request_failed remove_failed remove_request_failed].each do |key|
      assert messages[key].present?, "missing message #{key}"
    end
  ensure
    ::I18n.locale = 'en'
  end
end

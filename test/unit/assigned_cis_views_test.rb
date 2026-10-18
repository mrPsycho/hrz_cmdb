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
# Purpose: View tests for the tables of CIs handed out to a user: the shared _assigned_cis_table,
#          the Redmine user page block (_user_assigned_cis) and the "Issued assets" tab of the
#          RedmineUP People person page (_person_assigned_cis), including the view_cmdb checks.

require File.expand_path('../../test_helper', __FILE__)

class AssignedCisViewsTest < Redmine::HelperTest
  include ApplicationHelper
  helper ApplicationHelper

  fixtures :users, :email_addresses, :groups_users,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class, :hrzcm_lifecycle_status,
           :hrzcm_ci, :hrzcm_ci_history

  # Hands out CI 3 (WS01) and CI 1 (WEB01) to user 3; CI 2 (DB01) stays unassigned.
  def setup
    super
    @holder = User.find(3)
    HrzcmCi.where(id: [1, 3]).update_all(j_assigned_user_id: @holder.id)
  end

  # Renders the People tab partial for the given person.
  # Parameter person: Person/User whose tab is rendered
  # Returns: String HTML (empty without view_cmdb)
  def render_person_tab(person)
    render(partial: 'cmdb/person_assigned_cis', locals: { person: person })
  end

  test "person tab should list the CIs handed out to the person as a table" do
    User.current = user_with_cmdb_permission('view_cmdb')
    html = render_person_tab(@holder)

    assert_select_in html, '#cmdb-person-assigned-cis table.list tbody tr.ci-row', 2
    assert_select_in html, 'tr.ci-row td.ci-name a[href="/cmdb?ci_id=1"]', text: 'WEB01'
    assert_select_in html, 'tr.ci-row td.ci-name a[href="/cmdb?ci_id=3"]', text: 'WS01'
    assert_select_in html, 'tr[data-ci-id="2"]', 0
  end

  test "person tab should show producer, model, serial number, status and location path" do
    User.current = User.find(1)
    html = render_person_tab(@holder)

    assert_select_in html, 'thead th', 7
    assert_select_in html, 'tr[data-ci-id="3"]' do
      assert_select 'td.ci-producer', text: 'Lenovo'
      assert_select 'td.ci-model', text: 'ThinkPad T14'
      assert_select 'td.ci-serial', text: 'SN11111'
    end
    assert_select_in html, 'tr[data-ci-id="1"] td.ci-location', text: 'MB › 1F › 101'
  end

  test "person tab should sort the CIs by abbreviation" do
    User.current = User.find(1)
    names = Nokogiri::HTML(render_person_tab(@holder)).css('td.ci-name').map { |td| td.text.strip }
    assert_equal %w[WEB01 WS01], names
  end

  test "person tab should show no data for a person without CIs" do
    User.current = User.find(1)
    html = render_person_tab(User.find(2))

    assert_select_in html, '#cmdb-person-assigned-cis p.nodata', text: 'No data to display'
    assert_select_in html, 'table', 0
  end

  test "person tab should render nothing without view_cmdb" do
    User.current = user_without_cmdb_permission
    html = render_person_tab(@holder)

    # The output is only the partial's license comment; assert_select_in cannot parse that.
    assert_empty Nokogiri::HTML(html).css('#cmdb-person-assigned-cis, table')
    assert_not_includes html, 'WEB01'
    assert_not_includes html, '/cmdb?ci_id='
  end

  test "person tab should fall back to the @person of PeopleController" do
    User.current = User.find(1)
    @person = @holder
    html = render(partial: 'cmdb/person_assigned_cis')

    assert_select_in html, 'tr.ci-row', 2
  end

  test "user page block should render the shared table under its heading" do
    User.current = User.find(1)
    html = render(partial: 'cmdb/user_assigned_cis', locals: { user: @holder })

    assert_select_in html, '#cmdb-assigned-cis h3', text: 'Assigned configuration items'
    assert_select_in html, '#cmdb-assigned-cis table.cmdb-assigned-cis-table tr.ci-row', 2
  end

  test "user page block should render nothing for a user without CIs" do
    User.current = User.find(1)
    html = render(partial: 'cmdb/user_assigned_cis', locals: { user: User.find(2) })

    # The output is only the partial's license comment; assert_select_in cannot parse that.
    assert_empty Nokogiri::HTML(html).css('#cmdb-assigned-cis, table')
  end
end

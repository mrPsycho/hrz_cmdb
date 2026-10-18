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
# Purpose: Unit tests for HrzCmdb::Patches::PeopleHelperPatch, the optional RedmineUP People
#          integration adding the "Issued assets" tab to the person page. redmine_people is not
#          part of the test container, so a stand-in helper module plays PeopleHelper.

require File.expand_path('../../test_helper', __FILE__)

class PeopleHelperPatchTest < ActiveSupport::TestCase
  include Redmine::I18n

  fixtures :users, :email_addresses, :groups_users

  # Stand-in for PeopleHelper: returns the tabs redmine_people always shows.
  module FakePeopleHelper
    # Parameter _person: Person whose page is shown (unused)
    # Returns: Array with the base tab hashes of redmine_people
    def people_tabs(_person)
      [{ name: 'activity', partial: 'activity', label: 'Activity' }]
    end
  end

  # Stand-in for the view context / PeopleController including PeopleHelper.
  class FakePeopleView
    include Redmine::I18n
    include FakePeopleHelper
  end

  HrzCmdb::Patches::PeopleHelperPatch.prepend_to(FakePeopleHelper)

  # Builds a fresh stand-in view.
  def setup
    @view = FakePeopleView.new
    @person = User.find(3)
  end

  # Cleans up the current user set by the tests.
  def teardown
    User.current = nil
  end

  test "should add the issued assets tab for users with view_cmdb" do
    User.current = user_with_cmdb_permission('view_cmdb')
    tabs = @view.people_tabs(@person)

    assert_equal %w[activity cmdb_assets], tabs.map { |t| t[:name] }
    assert_equal 'cmdb/person_assigned_cis', tabs.last[:partial]
    assert_equal 'Issued assets', tabs.last[:label]
  end

  test "should add the issued assets tab for admins" do
    User.current = User.find(1)
    assert_includes @view.people_tabs(@person).map { |t| t[:name] }, 'cmdb_assets'
  end

  test "should not add the issued assets tab without view_cmdb" do
    User.current = user_without_cmdb_permission
    assert_equal %w[activity], @view.people_tabs(@person).map { |t| t[:name] }
  end

  test "should not add the issued assets tab for anonymous" do
    User.current = User.anonymous
    assert_equal %w[activity], @view.people_tabs(@person).map { |t| t[:name] }
  end

  test "should not add a tab without a person" do
    User.current = User.find(1)
    assert_nil @view.hrz_cmdb_people_tab(nil)
  end

  test "should translate the tab label" do
    User.current = User.find(1)
    ::I18n.locale = 'ru'
    assert_equal 'Выданные ассеты', @view.hrz_cmdb_people_tab(@person)[:label]
  ensure
    ::I18n.locale = 'en'
  end

  test "prepend_to should patch a helper module only once" do
    helper_module = Module.new do
      def people_tabs(_person)
        []
      end
    end

    assert HrzCmdb::Patches::PeopleHelperPatch.prepend_to(helper_module)
    assert HrzCmdb::Patches::PeopleHelperPatch.prepend_to(helper_module)
    assert_equal 1, helper_module.ancestors.count(HrzCmdb::Patches::PeopleHelperPatch)
  end

  test "apply should do nothing without the redmine_people plugin" do
    skip 'redmine_people is installed' if Redmine::Plugin.installed?(:redmine_people)

    assert_equal false, HrzCmdb::Patches::PeopleHelperPatch.apply
  end

  test "loader should be registered as after_plugins_loaded hook listener" do
    assert_includes Redmine::Hook.hook_listeners(:after_plugins_loaded).map(&:class),
                    HrzCmdb::Patches::PeopleHelperPatchLoader
  end
end

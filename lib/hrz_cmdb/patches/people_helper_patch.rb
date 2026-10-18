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
# Purpose: Optional integration with the RedmineUP People plugin (redmine_people).
#          Adds an "Issued assets" tab to the person page that lists the CIs currently handed
#          out to that person. Without redmine_people installed the patch does nothing.

module HrzCmdb
  module Patches
    module PeopleHelperPatch
      # Name of the tab on the person page (also used in the URL /people/:id/tabs/<name>).
      TAB_NAME = 'cmdb_assets'.freeze
      # Partial rendered as tab content, both on the initial page load and by
      # PeopleController#load_tab.
      TAB_PARTIAL = 'cmdb/person_assigned_cis'.freeze

      # Prepends this patch to PeopleHelper, if the RedmineUP People plugin is installed.
      # Called by the after_plugins_loaded hook below, i.e. after every plugin init.rb has run;
      # hrz_cmdb is loaded before redmine_people, so PeopleHelper cannot be patched earlier.
      # Returns: Boolean
      #   * true .... PeopleHelper is patched (now or already before)
      #   * false ... redmine_people is not installed, nothing was changed
      # Side effects: prepends this module to ::PeopleHelper (autoloads it if necessary).
      def self.apply
        return false unless Redmine::Plugin.installed?(:redmine_people) && defined?(::PeopleHelper)

        prepend_to(::PeopleHelper)
      end

      # Prepends this patch to the given helper module, at most once.
      # Parameter helper_module: Module providing people_tabs(person), normally ::PeopleHelper
      # Returns: true
      # Side effects: changes the method lookup of helper_module and of all classes including it.
      def self.prepend_to(helper_module)
        helper_module.prepend(self) unless helper_module.ancestors.include?(self)
        true
      end

      # Extends the tab list of the People person page with the "Issued assets" tab.
      # Parameter person: Person (a User subclass) whose page is shown
      # Returns: Array of tab hashes ({name:, partial:, label:}) from redmine_people, plus the
      #          CMDB tab if the current user may see it (see hrz_cmdb_people_tab)
      def people_tabs(person)
        tabs = super
        cmdb_tab = hrz_cmdb_people_tab(person)
        tabs << cmdb_tab if cmdb_tab
        tabs
      end

      # Builds the tab definition for the CIs handed out to a person.
      # The tab is shown to users with the group-based view_cmdb permission (admins always),
      # also when the person has no CIs; the tab content then shows "No data to display".
      # Parameter person: Person/User whose page is shown; nil yields no tab
      # Returns: Hash {name:, partial:, label:} in the format of PeopleHelper#people_tabs,
      #          or nil if there is no person or the current user lacks view_cmdb
      def hrz_cmdb_people_tab(person)
        return nil if person.nil?
        return nil unless HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'view_cmdb')

        { name: TAB_NAME, partial: TAB_PARTIAL, label: l('hrz_cmdb.cis.issued_assets_tab') }
      end
    end

    # Applies PeopleHelperPatch once all plugins are loaded.
    class PeopleHelperPatchLoader < Redmine::Hook::Listener
      # Redmine hook called at the end of plugin loading (also after every code reload in
      # development, which recreates PeopleHelper).
      # Parameter _context: Hash hook context (unused)
      # Returns: Boolean result of PeopleHelperPatch.apply
      # Side effects: see PeopleHelperPatch.apply
      def after_plugins_loaded(_context = {})
        PeopleHelperPatch.apply
      end
    end
  end
end

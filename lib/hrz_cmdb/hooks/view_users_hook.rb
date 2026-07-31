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
# Purpose: Redmine view hook injecting the list of assigned CIs into the user profile page.
#          Gives a fast link from a user account to the configuration items handed out to them.

module HrzCmdb
  module Hooks
    class ViewUsersHook < Redmine::Hook::ViewListener
      # Hook to add the assigned CI list at the bottom of the left column of the user page.
      # The permission check is done in the partial itself.
      render_on :view_account_left_bottom,
                partial: 'cmdb/user_assigned_cis'
    end
  end
end

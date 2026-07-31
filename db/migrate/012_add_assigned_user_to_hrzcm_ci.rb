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
# Purpose: Database migration adding the j_assigned_user_id column to hrzcm_ci.
#          Records which Redmine user a configuration item is currently handed out to.

class AddAssignedUserToHrzcmCi < ActiveRecord::Migration[6.1]
  def change
    add_column :hrzcm_ci, :j_assigned_user_id, :integer

    add_index :hrzcm_ci, :j_assigned_user_id
    add_foreign_key :hrzcm_ci, :users, column: :j_assigned_user_id
  end
end

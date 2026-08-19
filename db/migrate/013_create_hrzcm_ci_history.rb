#-------------------------------------------------------------------------------------------#
# Redmine CMDB plugin: Configuration Management DataBase                                    #
# Copyright (C) 2025 Franz Apeltauer                                                        #
#                                                                                           #
# This program is free software: you can redistribute it and/or modify it under the terms   #
# of the GNU Affero General Public License as published by the Free Software Foundation,     #
# either version 3 of the License, or (at your option) any later version.                   #
#                                                                                           #
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; #
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. #
# See the GNU Affero General Public License for more details.                               #
#                                                                                           #
# You should have received a copy of the GNU Affero General Public License                  #
# along with this program.  If not, see <https://www.gnu.org/licenses/>.                    #
#-------------------------------------------------------------------------------------eohdr-#
# Purpose: Database migration creating the asset change log table.
#          Stores each asset creation/update as a history event with timestamp and user.

class CreateHrzcmCiHistory < ActiveRecord::Migration[6.1]
  def change
    create_table :hrzcm_ci_history do |t|
      t.integer :j_ci_id, null: false
      t.string :b_action, null: false, limit: 50
      t.text :b_details
      t.integer :created_by
      t.datetime :created_on, null: false
      t.integer :updated_by
      t.datetime :updated_on

      t.timestamps null: false
    end

    add_index :hrzcm_ci_history, :j_ci_id
    add_index :hrzcm_ci_history, [:j_ci_id, :created_on]
    add_foreign_key :hrzcm_ci_history, :hrzcm_ci, column: :j_ci_id
    add_foreign_key :hrzcm_ci_history, :users, column: :created_by
    add_foreign_key :hrzcm_ci_history, :users, column: :updated_by
  end
end

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
# Purpose: Model for CI change history entries.
#          Records each asset creation and update with the user and timestamp.

class HrzcmCiHistory < ActiveRecord::Base
  self.table_name = 'hrzcm_ci_history'

  belongs_to :ci, class_name: 'HrzcmCi', foreign_key: 'j_ci_id', optional: false
  belongs_to :creator, class_name: 'User', foreign_key: 'created_by', optional: true
  belongs_to :updater, class_name: 'User', foreign_key: 'updated_by', optional: true

  scope :ordered_by_date, -> { order(created_on: :desc) }
  scope :recent, ->(limit = 20) { ordered_by_date.limit(limit) }

  before_create :set_creator
  before_save :set_updater

  # Stores a new asset change record for a CI.
  # Parameter ci: HrzcmCi instance being recorded
  # Parameter action: String action label to store (created or updated)
  # Parameter details: Optional String describing the affected field(s)
  # Returns: HrzcmCiHistory instance that was created
  def self.record(ci, action:, details: nil)
    create!(
      j_ci_id: ci.id,
      b_action: action,
      b_details: details || 'Asset updated',
      created_by: User.current&.id || ci.updated_by || ci.created_by,
      created_on: Time.current
    )
  end

  # Sets creator user ID and timestamp before record creation.
  # Called automatically before_create.
  # Sets: created_by from User.current, created_on to current time
  def set_creator
    self.created_by ||= User.current&.id
    self.created_on ||= Time.current
  end

  # Updates updater user ID and timestamp before record save.
  # Called automatically before_save.
  # Sets: updated_by from User.current, updated_on to current time
  def set_updater
    self.updated_by = User.current&.id if User.current
    self.updated_on = Time.current
  end
end

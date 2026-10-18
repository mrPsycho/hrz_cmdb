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
# Purpose: Junction model connecting Configuration Items to Redmine issues.
#          Enables tracking which hardware/software items are affected by or related to specific tickets.

class HrzcmCiIssue < ActiveRecord::Base
  self.table_name = 'hrzcm_ci_issues'

  # Associations
  belongs_to :ci, class_name: 'HrzcmCi', foreign_key: 'ci_id'
  belongs_to :issue, class_name: 'Issue', foreign_key: 'issue_id'
  belongs_to :creator, class_name: 'User', foreign_key: 'created_by', optional: true

  # Validations
  validates :ci_id, presence: true
  validates :issue_id, presence: true
  validates :ci_id, uniqueness: { scope: :issue_id, message: 'is already linked to this issue' }

  # Callbacks
  before_create :set_creator
  after_create :record_link_history
  after_destroy :record_unlink_history

  private

  # Sets creator user ID and timestamp before record creation.
  # Called automatically before_create.
  # Sets: created_by from User.current, created_on to current time
  def set_creator
    self.created_by ||= User.current&.id
    self.created_on ||= Time.current
  end

  # Adds an 'issue_linked' entry to the change history of the CI.
  # Called automatically after_create.
  # Side effects: inserts a row into hrzcm_ci_history
  def record_link_history
    HrzcmCiHistory.record_issue_link(ci, issue_id, HrzcmCiHistory::ACTION_ISSUE_LINKED) if ci
  end

  # Adds an 'issue_unlinked' entry to the change history of the CI. Also runs when the issue
  # is deleted. Skipped when the CI itself is being deleted, because its history goes with it.
  # Called automatically after_destroy.
  # Side effects: inserts a row into hrzcm_ci_history
  def record_unlink_history
    return if ci.nil? || destroyed_by_association&.active_record == HrzcmCi

    HrzcmCiHistory.record_issue_link(ci, issue_id, HrzcmCiHistory::ACTION_ISSUE_UNLINKED)
  end
end

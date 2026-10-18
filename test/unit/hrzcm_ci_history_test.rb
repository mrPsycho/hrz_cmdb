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
# Purpose: Unit tests for HrzcmCiHistory covering the change log written when a CI is created,
#          updated, linked to or unlinked from an issue, and the parsing of stored details.

require File.expand_path('../../test_helper', __FILE__)

class HrzcmCiHistoryTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers, :issue_statuses,
           :enumerations, :issues,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class, :hrzcm_lifecycle_status,
           :hrzcm_ci, :hrzcm_ci_history

  # Runs every test as the admin user so that created_by is filled.
  def setup
    User.current = User.find(1)
  end

  # Resets the current user so that it does not leak into other test cases.
  def teardown
    User.current = nil
  end

  # Returns the details of the newest history entry of a CI.
  # Parameter ci: HrzcmCi instance
  # Returns: Hash from HrzcmCiHistory#structured_details
  def latest_details(ci)
    ci.history_entries.ordered_by_date.first.structured_details
  end

  # Returns the stored change of one field from a details hash.
  # Parameter details: Hash from HrzcmCiHistory#structured_details
  # Parameter field: String column name
  # Returns: Hash with 'field', 'old', 'new' or nil if the field is not part of the change
  def change_for(details, field)
    details['changes'].find { |change| change['field'] == field }
  end

  test "should belong to ci" do
    entry = HrzcmCiHistory.find(1)
    assert_equal HrzcmCi.find(1), entry.ci
  end

  test "ordered_by_date should return newest entries first and break ties by id" do
    ci = HrzcmCi.find(1)
    time = Time.current
    first = HrzcmCiHistory.create!(j_ci_id: ci.id, b_action: 'updated', created_on: time)
    second = HrzcmCiHistory.create!(j_ci_id: ci.id, b_action: 'updated', created_on: time)
    assert_equal [second, first], ci.history_entries.ordered_by_date.to_a.first(2)
  end

  test "creating a ci should record its initial values" do
    ci = HrzcmCi.create!(b_name_abbr: 'NB01', j_ci_class_id: 2, j_location_id: 3,
                         j_status_id: 2, j_assigned_user_id: 2)
    entry = ci.history_entries.first

    assert_equal 1, ci.history_entries.count
    assert_equal HrzcmCiHistory::ACTION_CREATED, entry.b_action
    assert_equal 1, entry.created_by

    details = entry.structured_details
    assert_equal({ 'field' => 'j_location_id', 'new' => HrzcmLocation.find(3).display_name },
                 change_for(details, 'j_location_id'))
    assert_equal User.find(2).name, change_for(details, 'j_assigned_user_id')['new']
    assert_equal HrzcmLifecycleStatus.find(2).display_name, change_for(details, 'j_status_id')['new']
    assert_nil change_for(details, 'b_tag_serial'), 'blank columns are not listed on creation'
    assert_nil change_for(details, 'created_by'), 'bookkeeping columns are never listed'
  end

  test "handing a device to another user and moving it should record old and new values" do
    ci = HrzcmCi.find(1)
    ci.update!(j_assigned_user_id: 2)
    ci.update!(j_assigned_user_id: 3, j_location_id: 4)

    details = latest_details(ci)
    assert_equal({ 'field' => 'j_assigned_user_id', 'old' => User.find(2).name, 'new' => User.find(3).name,
                   'old_id' => 2, 'new_id' => 3 },
                 change_for(details, 'j_assigned_user_id'))
    assert_equal({ 'field' => 'j_location_id',
                   'old' => HrzcmLocation.find(3).display_name,
                   'new' => HrzcmLocation.find(4).display_name },
                 change_for(details, 'j_location_id'))
  end

  test "returning a device to storage should record the removed holder" do
    ci = HrzcmCi.find(1)
    ci.update!(j_assigned_user_id: 2)
    ci.update!(j_assigned_user_id: nil)

    change = change_for(latest_details(ci), 'j_assigned_user_id')
    assert_equal User.find(2).name, change['old']
    assert_equal 2, change['old_id']
    assert_nil change['new']
    assert_not change.key?('new_id'), 'no user id is stored for a removed holder'
  end

  test "creating a ci should store the id of the assigned user" do
    ci = HrzcmCi.create!(b_name_abbr: 'NB02', j_ci_class_id: 2, j_location_id: 3, j_assigned_user_id: 2)
    change = change_for(ci.history_entries.first.structured_details, 'j_assigned_user_id')

    assert_equal 2, change['new_id']
    assert_not change.key?('old_id'), 'created entries have no old value'
  end

  test "only user columns should store ids next to their values" do
    ci = HrzcmCi.find(1)
    ci.update!(j_location_id: 4)

    change = change_for(latest_details(ci), 'j_location_id')
    assert_not change.key?('old_id')
    assert_not change.key?('new_id')
  end

  test "saving without real changes should not record an entry" do
    ci = HrzcmCi.find(1)
    assert_no_difference -> { ci.history_entries.count } do
      ci.save!
      ci.update!(b_name_full: ci.b_name_full)
    end
  end

  test "changing the comment should record the field without its values" do
    ci = HrzcmCi.find(1)
    ci.update!(b_comment: 'secret' * 100)

    assert_equal({ 'field' => 'b_comment' }, change_for(latest_details(ci), 'b_comment'))
  end

  test "value_label should resolve foreign keys and fall back for unknown values" do
    assert_equal User.find(2).name, HrzcmCiHistory.value_label('j_assigned_user_id', 2)
    assert_equal HrzcmCiClass.find(2).display_name, HrzcmCiHistory.value_label('j_ci_class_id', 2)
    assert_equal '#999999', HrzcmCiHistory.value_label('j_location_id', 999_999)
    assert_nil HrzcmCiHistory.value_label('b_model', '')
    assert_nil HrzcmCiHistory.value_label('j_status_id', nil)
    assert_equal HrzcmCiHistory::MAX_VALUE_LENGTH, HrzcmCiHistory.value_label('b_model', 'x' * 500).length
  end

  test "structured_details should return nil for legacy plain text entries" do
    assert_nil HrzcmCiHistory.find(1).structured_details
    assert_nil HrzcmCiHistory.new(b_details: '{broken json').structured_details
    assert_nil HrzcmCiHistory.new(b_details: nil).structured_details
  end

  test "linking a ci to an issue should be recorded" do
    ci = HrzcmCi.find(1)
    HrzcmCiIssue.create!(ci_id: ci.id, issue_id: 1)

    entry = ci.history_entries.ordered_by_date.first
    assert_equal HrzcmCiHistory::ACTION_ISSUE_LINKED, entry.b_action
    assert_equal({ 'issue_id' => 1 }, entry.structured_details)
  end

  test "unlinking a ci from an issue should be recorded" do
    ci = HrzcmCi.find(1)
    link = HrzcmCiIssue.create!(ci_id: ci.id, issue_id: 1)
    link.destroy

    entry = ci.history_entries.ordered_by_date.first
    assert_equal HrzcmCiHistory::ACTION_ISSUE_UNLINKED, entry.b_action
    assert_equal({ 'issue_id' => 1 }, entry.structured_details)
  end

  test "deleting an issue should record the unlink in the ci history" do
    ci = HrzcmCi.find(2)
    HrzcmCiIssue.create!(ci_id: ci.id, issue_id: 1)
    Issue.find(1).destroy

    assert_equal HrzcmCiHistory::ACTION_ISSUE_UNLINKED, ci.history_entries.ordered_by_date.first.b_action
  end

  test "deleting a linked ci should remove it together with its history" do
    ci = HrzcmCi.find(1)
    HrzcmCiIssue.create!(ci_id: ci.id, issue_id: 1)

    assert ci.destroy
    assert_equal 0, HrzcmCiHistory.where(j_ci_id: ci.id).count
    assert_equal 0, HrzcmCiIssue.where(ci_id: ci.id).count
  end

  # Inserts a history entry as written by an older plugin version, without touching the CI.
  # Parameter ci: HrzcmCi instance
  # Parameter details: String stored in b_details as it is
  # Parameter age: ActiveSupport::Duration, how long ago the entry was written
  # Returns: HrzcmCiHistory instance that was created
  def old_entry(ci, details, age)
    HrzcmCiHistory.create!(j_ci_id: ci.id, b_action: 'updated', b_details: details,
                           created_by: 1, created_on: age.ago)
  end

  # Runs HrzcmCiHistory.inferred_values over the whole history of a CI.
  # Parameter ci: HrzcmCi instance
  # Returns: Hash from HrzcmCiHistory.inferred_values
  def inferred_for(ci)
    HrzcmCiHistory.inferred_values(ci.reload, ci.history_entries.ordered_by_date.to_a)
  end

  test "inferred_values should reconstruct the new values of a legacy entry from the current values" do
    ci = HrzcmCi.find(1)
    ci.update_columns(j_assigned_user_id: 2)
    legacy = old_entry(ci, 'j_assigned_user_id, b_comment', 1.hour)

    inferred = inferred_for(ci)
    assert_equal({ 'new' => User.find(2).name, 'new_id' => 2 }, inferred[legacy.id]['j_assigned_user_id'])
    assert_not inferred[legacy.id].key?('b_comment'), 'comment values are never shown'
    assert_equal({ 'new' => HrzcmLocation.find(3).display_name }, inferred[1]['j_location_id'],
                 'the older fixture entry gets the current location')
  end

  test "inferred_values should use the old value of a newer change for an older legacy entry" do
    ci = HrzcmCi.find(1)
    ci.update_columns(j_assigned_user_id: 2)
    legacy = old_entry(ci, 'j_assigned_user_id', 2.hours)
    ci.update!(j_assigned_user_id: 3)

    assert_equal({ 'new' => User.find(2).name, 'new_id' => 2 }, inferred_for(ci)[legacy.id]['j_assigned_user_id'])
  end

  test "inferred_values should not guess the value before a legacy change" do
    ci = HrzcmCi.find(1)
    ci.update_columns(j_assigned_user_id: 3)
    older = old_entry(ci, 'j_assigned_user_id', 3.hours)
    newer = old_entry(ci, 'j_assigned_user_id', 1.hour)

    inferred = inferred_for(ci)
    assert_equal 3, inferred[newer.id]['j_assigned_user_id']['new_id']
    assert_nil inferred[older.id]
  end

  test "inferred_values should add the user id to entries without one if the name matches" do
    ci = HrzcmCi.find(1)
    ci.update_columns(j_assigned_user_id: 3)
    without_id = old_entry(ci, { 'changes' => [{ 'field' => 'j_assigned_user_id', 'old' => User.find(2).name,
                                                 'new' => User.find(3).name }] }.to_json, 1.hour)
    legacy = old_entry(ci, 'j_assigned_user_id', 2.hours)

    inferred = inferred_for(ci)
    assert_equal({ 'j_assigned_user_id' => { 'new_id' => 3 } }, inferred[without_id.id])
    assert_equal({ 'new' => User.find(2).name }, inferred[legacy.id]['j_assigned_user_id'],
                 'the old value of an entry without ids has no id either')
  end

  test "inferred_values should not add a user id if the stored name differs" do
    ci = HrzcmCi.find(1)
    ci.update_columns(j_assigned_user_id: 3)
    entry = old_entry(ci, { 'changes' => [{ 'field' => 'j_assigned_user_id', 'old' => nil,
                                            'new' => 'Somebody else' }] }.to_json, 1.hour)

    assert_nil inferred_for(ci)[entry.id]
  end

  test "inferred_values should stop at the creation of the ci" do
    ci = HrzcmCi.create!(b_name_abbr: 'NB03', j_ci_class_id: 2, j_location_id: 3, j_assigned_user_id: 2)
    before_creation = old_entry(ci, 'j_assigned_user_id', 1.day)

    assert_nil inferred_for(ci)[before_creation.id]
  end

  test "legacy_fields should list the columns of entries written before 0.9.3 only" do
    assert_equal %w[b_name_full j_location_id], HrzcmCiHistory.find(1).legacy_fields
    assert_equal [], HrzcmCiHistory.new(b_details: 'Asset created').legacy_fields
    assert_equal [], HrzcmCiHistory.new(b_details: 'Asset updated').legacy_fields
    assert_equal [], HrzcmCiHistory.new(b_details: nil).legacy_fields
    assert_equal [], HrzcmCiHistory.new(b_details: { 'changes' => [] }.to_json).legacy_fields
  end
end

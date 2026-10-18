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
#          Updates store the changed fields with their old and new values, and linking or
#          unlinking an asset to/from an issue is recorded too, so the whole path of a
#          device (holder -> admin room -> storage -> new holder) can be followed.
#          Values that older entries did not store are reconstructed for display from the
#          CI's current values (see inferred_values).

require 'json'

class HrzcmCiHistory < ActiveRecord::Base
  self.table_name = 'hrzcm_ci_history'

  # Values of b_action
  ACTION_CREATED        = 'created'.freeze
  ACTION_UPDATED        = 'updated'.freeze
  ACTION_ISSUE_LINKED   = 'issue_linked'.freeze
  ACTION_ISSUE_UNLINKED = 'issue_unlinked'.freeze

  # Bookkeeping columns that are never reported as a change.
  IGNORED_FIELDS = %w[id created_on updated_on created_by updated_by].freeze
  # Columns that can hold long texts: only the fact that they changed is stored, not the values.
  VALUELESS_FIELDS = %w[b_comment].freeze
  # Columns holding a Redmine user ID: the raw IDs are stored next to the user names
  # ('old_id' / 'new_id'), so that the history can link to the user's profile.
  USER_FIELDS = %w[j_assigned_user_id].freeze
  # Maximum number of characters stored for a single old or new value.
  MAX_VALUE_LENGTH = 255

  belongs_to :ci, class_name: 'HrzcmCi', foreign_key: 'j_ci_id', optional: false
  belongs_to :creator, class_name: 'User', foreign_key: 'created_by', optional: true
  belongs_to :updater, class_name: 'User', foreign_key: 'updated_by', optional: true

  # Newest first. The id breaks ties between entries written within the same second.
  scope :ordered_by_date, -> { order(created_on: :desc, id: :desc) }
  scope :recent, ->(limit = 20) { ordered_by_date.limit(limit) }

  before_create :set_creator
  before_save :set_updater

  # Stores a new asset change record for a CI.
  # Parameter ci: HrzcmCi instance being recorded
  # Parameter action: String action label to store (created, updated, issue_linked, issue_unlinked)
  # Parameter details: Optional String describing the affected field(s). Entries written by
  #   record_changes / record_issue_link hold a JSON object (see structured_details), older
  #   entries hold plain text such as 'Asset created' or a comma separated list of column names.
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

  # Stores the creation or an update of a CI together with the changed values.
  # The values of foreign keys are stored as display names (user name, location, ...) as they
  # are at the time of the change, so the entry stays readable when the referenced record is
  # renamed or deleted later on. For USER_FIELDS the raw user IDs are stored as well
  # ('old_id' / 'new_id'), so that the history can link to the user's profile.
  # Parameter ci: HrzcmCi instance being recorded
  # Parameter changes: Hash of column name => [old_value, new_value], usually ci.saved_changes
  # Parameter action: String action to store
  #   * ACTION_CREATED .... always stores an entry, lists only the columns that received a value
  #   * ACTION_UPDATED .... stores an entry only if a non-bookkeeping column changed
  # Returns: HrzcmCiHistory instance that was created, or nil if nothing had to be recorded
  # Side effects: inserts a row into hrzcm_ci_history
  def self.record_changes(ci, changes, action: ACTION_UPDATED)
    entries = changes.to_h.except(*IGNORED_FIELDS).filter_map do |field, (old_value, new_value)|
      next if action == ACTION_CREATED && new_value.blank?

      entry = { 'field' => field }
      unless VALUELESS_FIELDS.include?(field)
        entry['old'] = value_label(field, old_value) unless action == ACTION_CREATED
        entry['new'] = value_label(field, new_value)
      end
      if USER_FIELDS.include?(field)
        entry['old_id'] = old_value.to_i if old_value.present? && action != ACTION_CREATED
        entry['new_id'] = new_value.to_i if new_value.present?
      end
      entry
    end
    return nil if entries.empty? && action != ACTION_CREATED

    record(ci, action: action, details: { 'changes' => entries }.to_json)
  end

  # Stores that a CI was linked to or unlinked from a Redmine issue.
  # Parameter ci: HrzcmCi instance being recorded
  # Parameter issue_id: Integer ID of the issue
  # Parameter action: String action to store
  #   * ACTION_ISSUE_LINKED ...... CI was linked to the issue
  #   * ACTION_ISSUE_UNLINKED .... CI was unlinked from the issue (or the issue was deleted)
  # Returns: HrzcmCiHistory instance that was created
  # Side effects: inserts a row into hrzcm_ci_history
  def self.record_issue_link(ci, issue_id, action)
    record(ci, action: action, details: { 'issue_id' => issue_id.to_i }.to_json)
  end

  # Converts a raw column value into the text stored in the history.
  # Parameter field: String column name of hrzcm_ci
  #   * 'j_assigned_user_id' .... resolved to the user's name
  #   * 'j_location_id' ......... resolved to the location's display name
  #   * 'j_ci_class_id' ......... resolved to the CI class's display name
  #   * 'j_status_id' ........... resolved to the lifecycle status's display name
  #   * any other column ........ value converted to a String
  # Parameter value: raw column value, may be nil or blank
  # Returns: String truncated to MAX_VALUE_LENGTH, nil for a blank value. An ID whose record
  #          no longer exists is returned as '#<id>'.
  def self.value_label(field, value)
    return nil if value.blank?

    label =
      case field
      when 'j_assigned_user_id' then User.find_by(id: value)&.name
      when 'j_location_id'      then HrzcmLocation.find_by(id: value)&.display_name
      when 'j_ci_class_id'      then HrzcmCiClass.find_by(id: value)&.display_name
      when 'j_status_id'        then HrzcmLifecycleStatus.find_by(id: value)&.display_name
      else value.to_s
      end
    (label || "##{value}").to_s.truncate(MAX_VALUE_LENGTH)
  end

  # Reconstructs the values that history entries did not store, by walking the history from
  # the newest entry back and starting from the CI's current values: the value after a change
  # is the current value, or the old value stored by the next newer change of the same field.
  #   * entries written before 0.9.3 only name the changed columns; for them the new value
  #     is reconstructed (old values stay unknown)
  #   * entries written by 0.9.3 / 0.9.4 store user names but no user IDs; for them the ID of
  #     the new user is reconstructed if the stored name matches the reconstructed one
  # The walk stops for a field at a change whose value is unknown, and for all fields at the
  # creation of the CI. This relies on every column change being recorded, which the model
  # callbacks of HrzcmCi have done since the history exists.
  # Parameter ci: HrzcmCi instance the entries belong to, with its current values
  # Parameter entries: Array or relation of HrzcmCiHistory of that CI, newest first and
  #   without gaps (e.g. ci.history_entries.ordered_by_date.limit(20))
  # Returns: Hash { entry id => { column name => { 'new' => String, 'new_id' => Integer } } },
  #          'new' only for entries before 0.9.3, 'new_id' only for USER_FIELDS; entries
  #          without reconstructed values are missing
  def self.inferred_values(ci, entries)
    # Value after the entry currently looked at; a missing key means "unknown", nil means blank.
    known = (HrzcmCi.column_names - IGNORED_FIELDS - VALUELESS_FIELDS).index_with do |field|
      current_value(ci, field)
    end

    entries.each_with_object({}) do |entry, result|
      inferred = {}
      data = entry.structured_details

      if data.nil?
        entry.legacy_fields.each do |field|
          inferred[field] = known[field] if known[field]
          known.delete(field)
        end
      else
        Array(data['changes']).each do |change|
          field = change['field']
          next if VALUELESS_FIELDS.include?(field) || !(change.key?('old') || change.key?('new'))

          after = known[field]
          if USER_FIELDS.include?(field) && !change.key?('new_id') && change['new'].present? &&
             after && after['new'] == change['new'] && after['new_id']
            inferred[field] = { 'new_id' => after['new_id'] }
          end
          if change.key?('old')
            known[field] = change['old'].present? ? { 'new' => change['old'], 'new_id' => change['old_id'] }.compact : nil
          else
            known.delete(field)
          end
        end
      end

      known.clear if entry.b_action == ACTION_CREATED
      result[entry.id] = inferred if inferred.any?
    end
  end

  # Returns the current value of a CI column in the form used by inferred_values.
  # Parameter ci: HrzcmCi instance
  # Parameter field: String column name of hrzcm_ci
  # Returns: Hash { 'new' => display text, 'new_id' => Integer user ID (USER_FIELDS only) },
  #          nil if the column is blank
  def self.current_value(ci, field)
    raw = ci[field]
    return nil if raw.blank?

    value = { 'new' => value_label(field, raw) }
    value['new_id'] = raw.to_i if USER_FIELDS.include?(field)
    value
  end

  # Returns the column names listed by an entry written before 0.9.3.
  # Returns: Array of String column names as stored (comma separated in b_details); empty for
  #          entries with JSON details, blank details and the default texts 'Asset created' /
  #          'Asset updated' (the latter was written when only bookkeeping columns changed)
  def legacy_fields
    return [] if structured_details || b_details.blank? || ['Asset created', 'Asset updated'].include?(b_details)

    b_details.split(',').map(&:strip).reject(&:blank?)
  end

  # Parses the JSON details written by record_changes / record_issue_link.
  # Returns: Hash with either
  #   * 'changes' => Array of { 'field' => column, 'old' => String/nil, 'new' => String/nil },
  #                  'old'/'new' are missing for VALUELESS_FIELDS and 'old' for created entries;
  #                  USER_FIELDS additionally carry 'old_id' / 'new_id' (Integer user IDs,
  #                  only in entries written since 0.9.5)
  #   * 'issue_id' => Integer ID of the linked/unlinked issue
  #   or nil for entries written before 0.9.3, whose b_details is plain text
  def structured_details
    return nil if b_details.blank? || !b_details.start_with?('{')

    data = JSON.parse(b_details)
    data.is_a?(Hash) ? data : nil
  rescue JSON::ParserError
    nil
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

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
# Purpose: View helper methods for CMDB permission checks in views and controllers.
#          Provides convenient methods to check user's view, edit, and basic_data permissions.

module CmdbHelper
  # Checks if current user can view CMDB data.
  # Users with edit or edit_basic_data permissions can also view.
  # Returns: Boolean indicating if user has view access
  def can_view_cmdb?
    # Users who can edit can also view
    HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'view_cmdb') ||
    HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_cmdb') ||
    HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_basic_data')
  end

  # Checks if current user can edit locations and CIs.
  # Returns: Boolean indicating if user has edit_cmdb permission
  def can_edit_cmdb?
    HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_cmdb')
  end

  # Checks if current user can edit basic data (CI classes, lifecycle statuses, external systems).
  # Returns: Boolean indicating if user has edit_basic_data permission
  def can_edit_basic_data?
    HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_basic_data')
  end

  # Formats documentation string as appropriate HTML link or text.
  # Parameter documentation: String documentation reference
  #   * 'tiki:PageName' ........... creates JavaScript link to TikiWiki page
  #   * 'https://...' ............. creates external link
  #   * plain text ................ wraps in span tag
  # Returns: HTML safe string (link or span element), or empty string if blank
  def format_documentation_link(documentation)
    return '' if documentation.blank?

    if documentation.starts_with?('tiki:')
      page_name = documentation.sub('tiki:', '')
      link_to documentation, "#", onclick: "HrzCmdb.openTiki('#{page_name}'); return false;",
              class: 'documentation-link', target: '_blank'
    elsif documentation =~ /\Ahttps?:\/\//
      link_to documentation, documentation, class: 'documentation-link', target: '_blank'
    else
      content_tag :span, documentation, class: 'documentation-text'
    end
  end

  # Generates breadcrumb navigation for a location showing all parent locations.
  # Parameter location: HrzcmLocation instance to generate breadcrumb for
  # Returns: HTML safe string with linked location names separated by ' > '
  def location_breadcrumb(location)
    parts = []
    current = location

    while current
      parts.unshift(link_to(current.b_name_abbr || current.b_name_full,
                           "#", onclick: "HrzCmdb.loadLocation(#{current.id}); return false;"))
      current = current.parent1
    end

    safe_join(parts, ' > ')
  end

  # Renders location select options grouped by hierarchy level.
  # Parameter selected_id: Integer ID of location to mark as selected (optional)
  # Parameter exclude_id: Integer ID of location to exclude from options (optional)
  # Returns: HTML safe string with optgroup elements containing location options
  def render_location_tree_options(selected_id = nil, exclude_id = nil)
    options = []

    HrzcmLocatHier.ordered_by_level.each do |hierarchy|
      options << content_tag(:optgroup, label: hierarchy.b_name_abbr) do
        locations = HrzcmLocation.for_type(hierarchy.id).ordered_by_b_name_abbr
        locations = locations.where.not(id: exclude_id) if exclude_id

        options_from_collection_for_select(locations, :id, :display_name, selected_id)
      end
    end

    safe_join(options)
  end

  # Returns appropriate icon HTML for a given CMDB item type.
  # Parameter type: String type identifier
  #   * 'folder' or 'location_with_children' ... folder icon 📁
  #   * 'page' or 'location' .................. page icon 📄
  #   * 'add' or 'new' ........................ add icon ➕
  #   * other ................................. default icon ▪
  # Returns: HTML safe span element with icon
  def cmdb_icon(type)
    case type
    when 'folder', 'location_with_children'
      content_tag :span, '📁', class: 'icon icon-folder'
    when 'page', 'location'
      content_tag :span, '📄', class: 'icon icon-page'
    when 'add', 'new'
      content_tag :span, '➕', class: 'icon icon-add'
    else
      content_tag :span, '▪', class: 'icon icon-default'
    end
  end

  # Generates JavaScript tag with i18n translations for client-side use.
  # Creates window.hrz_cmdb_translations object with common UI text strings.
  # Returns: HTML safe JavaScript tag setting window.hrz_cmdb_translations
  def cmdb_javascript_translations
    translations = {
      select_item: l('hrz_cmdb.select_item'),
      save: l('hrz_cmdb.buttons.save'),
      cancel: l('hrz_cmdb.buttons.cancel'),
      create: l('hrz_cmdb.buttons.create'),
      confirm_delete: l(:text_are_you_sure)
    }

    javascript_tag "window.hrz_cmdb_translations = #{translations.to_json};"
  end

  # Writes the REST API representation of a location hierarchy level into an API builder.
  # Used by the *.api.rsb templates for both single and collection responses.
  # Parameter locat_hier: HrzcmLocatHier instance to serialise
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Returns: nil, writes the hrzcm_locat_hier node into the builder as a side effect
  def render_api_locat_hier(locat_hier, api)
    api.hrzcm_locat_hier do
      api.id           locat_hier.id
      api.b_name_full  locat_hier.b_name_full
      api.b_name_abbr  locat_hier.b_name_abbr
      api.b_key        locat_hier.b_key
      api.b_comment    locat_hier.b_comment
      api.b_url_doc    locat_hier.b_url_doc
      api.j_level      locat_hier.j_level
      render_api_audit_fields(locat_hier, api)
    end
    nil
  end

  # Writes the REST API representation of a location into an API builder.
  # Parameter location: HrzcmLocation instance to serialise
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Returns: nil, writes the hrzcm_location node into the builder as a side effect
  def render_api_location(location, api)
    api.hrzcm_location do
      api.id           location.id
      api.b_name_full  location.b_name_full
      api.b_name_abbr  location.b_name_abbr
      api.b_key        location.b_key
      api.b_comment    location.b_comment
      api.b_url_doc    location.b_url_doc
      api.j_type_id      location.j_type_id
      api.j_part_of1_id  location.j_part_of1_id
      api.j_part_of2_id  location.j_part_of2_id
      api.locat_hier(:id => location.location_type.id, :name => location.location_type.b_name_abbr) if location.location_type
      api.part_of1(:id => location.parent1.id, :name => location.parent1.b_name_abbr) if location.parent1
      api.part_of2(:id => location.parent2.id, :name => location.parent2.b_name_abbr) if location.parent2
      render_api_audit_fields(location, api)
    end
    nil
  end

  # Writes the REST API representation of a CI class into an API builder.
  # Parameter ci_class: HrzcmCiClass instance to serialise
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Returns: nil, writes the hrzcm_ci_class node into the builder as a side effect
  def render_api_ci_class(ci_class, api)
    api.hrzcm_ci_class do
      api.id           ci_class.id
      api.b_name_full  ci_class.b_name_full
      api.b_name_abbr  ci_class.b_name_abbr
      api.b_key        ci_class.b_key
      api.b_comment    ci_class.b_comment
      api.b_url_doc    ci_class.b_url_doc
      api.j_sort            ci_class.j_sort
      api.j_subclass_of_id  ci_class.j_subclass_of_id
      api.subclass_of(:id => ci_class.parent_class.id, :name => ci_class.parent_class.b_name_abbr) if ci_class.parent_class
      render_api_audit_fields(ci_class, api)
    end
    nil
  end

  # Writes the REST API representation of a lifecycle status into an API builder.
  # Parameter status: HrzcmLifecycleStatus instance to serialise
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Returns: nil, writes the hrzcm_lifecycle_status node into the builder as a side effect
  def render_api_lifecycle_status(status, api)
    api.hrzcm_lifecycle_status do
      api.id           status.id
      api.b_name_full  status.b_name_full
      api.b_name_abbr  status.b_name_abbr
      api.b_key        status.b_key
      api.b_comment    status.b_comment
      api.b_url_doc    status.b_url_doc
      render_api_audit_fields(status, api)
    end
    nil
  end

  # Writes the REST API representation of an external system into an API builder.
  # The external system's Redmine service account is exposed as id and name only.
  # Parameter ext_sys: HrzcmExtSys instance to serialise
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Returns: nil, writes the hrzcm_ext_sys node into the builder as a side effect
  def render_api_ext_sys(ext_sys, api)
    api.hrzcm_ext_sys do
      api.id           ext_sys.id
      api.b_name_full  ext_sys.b_name_full
      api.b_name_abbr  ext_sys.b_name_abbr
      api.b_comment    ext_sys.b_comment
      api.b_url_doc    ext_sys.b_url_doc
      api.b_url_ci_details_ext   ext_sys.b_url_ci_details_ext
      api.j_redmine_user_id      ext_sys.j_redmine_user_id
      api.j_location_default_id  ext_sys.j_location_default_id
      api.redmine_user(:id => ext_sys.redmine_user.id, :name => ext_sys.redmine_user.name) if ext_sys.redmine_user
      api.location_default(:id => ext_sys.location_default.id, :name => ext_sys.location_default.b_name_abbr) if ext_sys.location_default
      render_api_audit_fields(ext_sys, api)
    end
    nil
  end

  # Writes the REST API representation of a configuration item into an API builder.
  # Parameter ci: HrzcmCi instance to serialise
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Parameter with_issues: Boolean
  #   * true .... include the linked Redmine issues as an issues array
  #   * false ... omit the issues array (default, avoids a query per CI in collections)
  # Returns: nil, writes the hrzcm_ci node into the builder as a side effect
  def render_api_ci(ci, api, with_issues = false)
    api.hrzcm_ci do
      api.id           ci.id
      api.b_name_full  ci.b_name_full
      api.b_name_abbr  ci.b_name_abbr
      api.b_comment    ci.b_comment
      api.b_url_doc    ci.b_url_doc
      api.b_producer   ci.b_producer
      api.b_model      ci.b_model
      api.b_tag_serial ci.b_tag_serial
      api.j_ci_class_id  ci.j_ci_class_id
      api.j_location_id  ci.j_location_id
      api.j_status_id    ci.j_status_id
      api.ci_class(:id => ci.ci_class.id, :name => ci.ci_class.b_name_abbr) if ci.ci_class
      api.location(:id => ci.location.id, :name => ci.location.b_name_abbr) if ci.location
      api.lifecycle_status(:id => ci.lifecycle_status.id, :name => ci.lifecycle_status.b_name_abbr) if ci.lifecycle_status
      if with_issues
        api.array :issues do
          ci.issues.visible.each do |issue|
            api.issue(:id => issue.id, :subject => issue.subject)
          end
        end
      end
      render_api_audit_fields(ci, api)
    end
    nil
  end

  # Writes the audit trail attributes shared by all CMDB records into an API builder.
  # Only the id and display name of the acting users are exposed, no further account data.
  # Parameter record: ActiveRecord object responding to created_on, updated_on, creator and updater
  # Parameter api: Redmine::Views::Builders instance (Json or Xml) to write into
  # Returns: nil, writes the audit nodes into the builder as a side effect
  def render_api_audit_fields(record, api)
    api.created_by(:id => record.creator.id, :name => record.creator.name) if record.creator
    api.updated_by(:id => record.updater.id, :name => record.updater.name) if record.updater
    api.created_on record.created_on
    api.updated_on record.updated_on
    nil
  end
end
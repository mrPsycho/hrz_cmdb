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
# Purpose: Controller for managing basic data configuration - location hierarchy levels/types.
#          Requires edit_basic_data permission to modify hierarchy structure definitions.

class CmdbBasicDataController < ApplicationController
  # Actions reachable through the Redmine REST API (API key or HTTP basic auth).
  # Authentication only. Authorisation stays with the check_permissions before_action below.
  accept_api_auth :index, :show, :create, :update, :destroy

  helper :cmdb

  before_action :check_permissions
  before_action :find_hierarchy, only: [:show, :update, :destroy]

  # Lists all location hierarchy levels ordered by level number.
  # Parameter offset / limit / page (via params): Redmine pagination parameters for .json/.xml
  #   requests only, limit is capped at 100. The HTML view always lists every level.
  # Sets: @hierarchies, and for API requests also @hierarchies_count, @offset and @limit
  # Returns: index.api.rsb for .json/.xml requests, otherwise the HTML view
  def index
    scope = HrzcmLocatHier.ordered_by_level

    if api_request?
      @offset, @limit = api_offset_and_limit
      @hierarchies_count = scope.count
      @hierarchies = scope.limit(@limit).offset(@offset).to_a
      return
    end

    @hierarchies = scope
  end

  # Shows details of a specific hierarchy level.
  # Uses @hierarchy instance variable set by find_hierarchy before_action.
  # Returns: show.api.rsb for .json/.xml requests, otherwise HTML partial or plain JSON
  def show
    return render(:action => 'show') if api_request?

    respond_to do |format|
      format.html { render partial: 'hierarchy_details', locals: { hierarchy: @hierarchy, can_edit: true } }
      format.json { render json: @hierarchy }
    end
  end

  # Renders form for creating a new hierarchy level.
  # No parameters required.
  # Returns: HTML partial with new hierarchy form
  def new_hierarchy
    @hierarchy = HrzcmLocatHier.new
    render partial: 'hierarchy_form', locals: { hierarchy: @hierarchy, can_edit: true }
  end

  # Creates a new hierarchy level from form or API parameters.
  # Parameter hierarchy (via params): Hash with hierarchy attributes (b_name_full, b_name_abbr, j_level, etc.)
  # Returns: 201 with show.api.rsb and a Location header for .json/.xml requests,
  #          422 with the validation errors on failure, otherwise the UI JSON envelope
  def create
    @hierarchy = HrzcmLocatHier.new(hierarchy_params)

    if @hierarchy.save
      if api_request?
        render :action => 'show', :status => :created,
               :location => url_for(:controller => 'cmdb_basic_data', :action => 'show',
                                    :id => @hierarchy.id, :format => params[:format], :only_path => false)
      else
        render json: {
          success: true,
          id: @hierarchy.id,
          notice: I18n.t('hrz_cmdb.location_hierarchy.created')
        }
      end
    else
      return render_validation_errors(@hierarchy) if api_request?

      render json: { success: false, errors: @hierarchy.errors.full_messages }
    end
  end

  # Updates an existing hierarchy level with new attributes.
  # Uses @hierarchy instance variable set by find_hierarchy before_action.
  # Parameter hierarchy (via params): Hash with hierarchy attributes to update
  # Returns: 204 for .json/.xml requests, 422 with the validation errors on failure,
  #          otherwise the UI JSON envelope
  def update
    if @hierarchy.update(hierarchy_params)
      return render_api_ok if api_request?

      render json: {
        success: true,
        id: @hierarchy.id,
        notice: I18n.t('hrz_cmdb.location_hierarchy.updated')
      }
    else
      return render_validation_errors(@hierarchy) if api_request?

      render json: { success: false, errors: @hierarchy.errors.full_messages }
    end
  end

  # Deletes a hierarchy level if it has no associated locations.
  # Uses @hierarchy instance variable set by find_hierarchy before_action.
  # Returns: 204 for .json/.xml requests, 422 with the blocking reason if the level still has
  #          locations, otherwise the UI JSON envelope
  def destroy
    if @hierarchy.locations.empty?
      if @hierarchy.destroy
        return render_api_ok if api_request?

        render json: {
          success: true,
          notice: I18n.t('hrz_cmdb.location_hierarchy.deleted')
        }
      else
        return render_validation_errors(@hierarchy) if api_request?

        render json: { success: false, errors: @hierarchy.errors.full_messages }
      end
    else
      return render_api_errors(I18n.t('hrz_cmdb.location_hierarchy.has_locations')) if api_request?

      render json: { success: false, errors: [I18n.t('hrz_cmdb.location_hierarchy.has_locations')] }
    end
  end

  # Shows the seed data management page.
  # Returns: HTML partial with seed data management options
  def show_seed_data_management
    html = render_to_string(partial: 'seed_data_management')
    render html: html.html_safe
  end

  # Adds seed data to the database, skipping existing records (by b_key).
  # Processes hierarchies from root to leaf to handle foreign key dependencies.
  # Returns: HTML partial with operation results
  def add_seed_data
    stats = HrzCmdb::SeedDataHelper.insert_all_seed_data
    html = render_to_string(partial: 'seed_data_result', locals: { operation: 'add', stats: stats })
    render html: html.html_safe
  end

  # Removes unused seed data (records not referenced by foreign keys).
  # Processes hierarchies from leaf to root to handle foreign key dependencies.
  # Returns: HTML partial with operation results
  def remove_unused_seed_data
    stats = HrzCmdb::SeedDataHelper.remove_unused_seed_data
    html = render_to_string(partial: 'seed_data_result', locals: { operation: 'remove', stats: stats })
    render html: html.html_safe
  end

  private

  # Verifies current user has edit_basic_data permission.
  # Called as before_action for all controller actions.
  # Denies access if user lacks required permission.
  def check_permissions
    unless HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_basic_data')
      deny_access
    end
  end

  # Finds and loads a hierarchy level by ID from params.
  # Called as before_action for show, update, and destroy actions.
  # Parameter id (via params): Integer ID of the hierarchy level to find
  # Sets: @hierarchy instance variable
  # Raises: Renders 404 if hierarchy level not found
  def find_hierarchy
    @hierarchy = HrzcmLocatHier.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Strong parameters filter for hierarchy attributes.
  # Permits only whitelisted attributes for mass assignment.
  # Returns: ActionController::Parameters with permitted hierarchy attributes
  def hierarchy_params
    params.require(:hierarchy).permit(:b_name_full, :b_name_abbr, :b_comment,
                                      :b_url_doc, :b_key, :j_level)
  end
end
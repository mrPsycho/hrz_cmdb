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
# Purpose: Controller for managing CI-Issue associations within Redmine tickets.
#          Handles linking/unlinking CIs to issues and provides available CIs for selection.

class IssueCisController < ApplicationController
  # Actions reachable through the Redmine REST API (API key or HTTP basic auth).
  # Authentication only. Authorisation stays with the authorize before_action below.
  accept_api_auth :index, :create, :destroy

  helper :cmdb

  before_action :find_issue
  before_action :check_module_enabled
  before_action :authorize

  # Lists the CIs linked to an issue.
  # Parameter issue_id (via params): Integer ID of the issue (set by find_issue)
  # Parameter offset / limit / page (via params): Redmine pagination parameters, limit is capped at 100
  # Sets: @cis, @cis_count, @offset, @limit
  # Returns: index.api.rsb rendering of the paginated collection, 406 for non API formats
  def index
    scope = @issue.cis.ordered_by_abbr

    @offset, @limit = api_offset_and_limit
    @cis_count = scope.count
    @cis = scope.includes(:ci_class, :location, :lifecycle_status).limit(@limit).offset(@offset).to_a
  end

  # Creates a new CI-Issue association and logs it in the issue history.
  # Parameter ci_id (via params): Integer ID of the CI to link to the issue
  # Parameter issue_id (via params): Integer ID of the issue (set by find_issue)
  # Returns: 201 with show.api.rsb for .json/.xml requests, 422 with the validation errors on
  #          failure, 404 if the CI does not exist, otherwise the UI JSON envelope with the CI row HTML
  def create
    @ci = HrzcmCi.find(params[:ci_id])
    @ci_issue = HrzcmCiIssue.new(ci_id: @ci.id, issue_id: @issue.id)

    if @ci_issue.save
      # Log the CI addition in the issue's history
      journal = @issue.init_journal(User.current, l(:notice_ci_added))
      journal.details << JournalDetail.new(
        property: 'relation',
        prop_key: 'ci',
        value: @ci.id,
        old_value: nil
      )
      journal.save

      return render(:action => 'show', :status => :created) if api_request?

      # Render the partial as a string without layout
      html = render_to_string(partial: 'issue_cis/ci_row', locals: { ci: @ci, issue: @issue }, layout: false)

      render json: {
        success: true,
        html: html,
        notice: l(:notice_ci_added)
      }
    else
      return render_validation_errors(@ci_issue) if api_request?

      render json: {
        success: false,
        errors: @ci_issue.errors.full_messages
      }
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Removes a CI-Issue association and logs the removal in the issue history.
  # Parameter id (via params): Integer ID of the CI to unlink from the issue
  # Parameter issue_id (via params): Integer ID of the issue (set by find_issue)
  # Returns: 204 for .json/.xml requests, 404 if the association does not exist,
  #          otherwise the UI JSON envelope
  def destroy
    @ci_issue = HrzcmCiIssue.find_by(ci_id: params[:id], issue_id: @issue.id)
    @ci = HrzcmCi.find_by(id: params[:id])

    if @ci_issue && @ci_issue.destroy
      # Log the CI removal in the issue's history
      journal = @issue.init_journal(User.current, l(:notice_ci_removed))
      journal.details << JournalDetail.new(
        property: 'relation',
        prop_key: 'ci',
        value: nil,
        old_value: @ci.id
      )
      journal.save

      return render_api_ok if api_request?

      render json: { success: true, notice: l(:notice_ci_removed) }
    else
      return render_404 if api_request?

      render json: { success: false, errors: [l(:error_ci_not_found)] }
    end
  end

  # Returns tree data structure for CI selection modal, excluding already linked CIs.
  # Parameter parent_id (via params):
  #   * blank ................... root level (shows top-level CI classes)
  #   * 'ci_class_X' ............ shows subclasses and CIs of CI class with ID X
  # Returns: JSON array of tree nodes for jsTree
  def available_cis
    # Return tree data for CI selection modal
    nodes = []

    if params[:parent_id].blank?
      # Root level - show "CIs by Class" structure
      HrzcmCiClass.root_classes.ordered_by_sort_and_abbr.each do |ci_class|
        nodes << ci_class_to_tree_node(ci_class)
      end
    elsif params[:parent_id].to_s.start_with?('ci_class_')
      # Show subclasses and CIs of this CI class
      ci_class_id = params[:parent_id].to_s.sub('ci_class_', '').to_i

      # Add subclasses
      HrzcmCiClass.for_parent(ci_class_id).ordered_by_sort_and_abbr.each do |subclass|
        nodes << ci_class_to_tree_node(subclass)
      end

      # Add CIs of this class (exclude already linked CIs)
      linked_ci_ids = @issue.cis.pluck(:id)
      HrzcmCi.for_ci_class(ci_class_id).ordered_by_abbr.where.not(id: linked_ci_ids).each do |ci|
        nodes << ci_to_tree_node(ci)
      end
    end

    render json: nodes
  end

  private

  # Finds and loads an issue by ID from params.
  # Called as before_action for all controller actions.
  # Only issues the current user is allowed to see are found, so the REST API cannot be used
  # to read or modify CI links of an issue that is invisible to the caller.
  # Parameter issue_id (via params): Integer ID of the issue to find
  # Sets: @issue and @project instance variables
  # Raises: Renders 404 if the issue does not exist or is not visible to the current user
  def find_issue
    @issue = Issue.visible.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Verifies that the CMDB module is enabled in the project.
  # Called as before_action for all controller actions.
  # Returns: false and renders 403 if module is not enabled
  def check_module_enabled
    # Check if CMDB module is enabled in the project
    unless @project && @project.module_enabled?(:cmdb)
      render_403
      return false
    end
  end

  # Checks user permissions based on the action being performed.
  # Called as before_action for all controller actions.
  # Permission requirements:
  #   * index action ............ requires view_issue_cis permission
  #   * available_cis action .... requires view_issue_cis permission
  #   * create/destroy actions ... requires manage_issue_cis permission
  # Returns: false and denies access if user lacks required permission
  def authorize
    # For read-only actions, check view_issue_cis permission
    if %w[index available_cis].include?(action_name)
      unless User.current.allowed_to?(:view_issue_cis, @project)
        deny_access
        return false
      end
    # For create/destroy actions, check manage_issue_cis permission
    else
      unless User.current.allowed_to?(:manage_issue_cis, @project)
        deny_access
        return false
      end
    end
  end

  # Converts a CI class to a jsTree node for the CI selection modal.
  # Parameter ci_class: HrzcmCiClass instance to convert
  # Returns: Hash with jsTree node structure (id, text, icon, children, type, title)
  # Note: Excludes already linked CIs from the children count
  def ci_class_to_tree_node(ci_class)
    # Check for subclasses and available CIs (excluding already linked ones)
    linked_ci_ids = @issue.cis.pluck(:id)
    available_cis_count = HrzcmCi.for_ci_class(ci_class.id).where.not(id: linked_ci_ids).count
    has_children = ci_class.has_subclasses? || available_cis_count > 0

    node = {
      id: "ci_class_#{ci_class.id}",
      text: ci_class.tree_label,
      icon: has_children ? 'icon-folder' : 'icon-page',
      children: has_children,
      type: 'ci_class'
    }
    if ci_class.b_name_full.present? && ci_class.b_name_abbr.present? && ci_class.b_name_full != ci_class.b_name_abbr
      node[:title] = ci_class.b_name_full
    end
    node
  end

  # Converts a CI to a jsTree node for the CI selection modal.
  # Parameter ci: HrzcmCi instance to convert
  # Returns: Hash with jsTree node structure (id, text, icon, children, type, selectable, title)
  def ci_to_tree_node(ci)
    node = {
      id: ci.id,
      text: ci.tree_label,
      icon: 'icon-page',
      children: false,
      type: 'ci',
      selectable: true
    }
    if ci.b_name_full.present? && ci.b_name_abbr.present? && ci.b_name_full != ci.b_name_abbr
      node[:title] = ci.b_name_full
    end
    node
  end
end

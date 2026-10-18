/*-------------------------------------------------------------------------------------------*/
/* Redmine CMDB plugin: Configuration Management DataBase                                    */
/* Copyright (C) 2025 Franz Apeltauer                                                        */
/*                                                                                           */
/* This program is free software: you can redistribute it and/or modify it under the terms   */
/* of the GNU Affero General Public License as published by the Free Software Foundation,    */
/* either version 3 of the License, or (at your option) any later version.                   */
/*                                                                                           */
/* This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; */
/* without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. */
/* See the GNU Affero General Public License for more details.                               */
/*                                                                                           */
/* You should have received a copy of the GNU Affero General Public License                  */
/* along with this program.  If not, see <https://www.gnu.org/licenses/>.                    */
/*-------------------------------------------------------------------------------------eohdr-*/
// Purpose: JavaScript for managing CI-Issue associations within Redmine tickets.
//          Handles CI selection modal, linking/unlinking CIs to issues, and dynamic CI list updates.

var IssueCis = {
  issueId: null,
  // Translated messages, read from the data-ci-messages attribute of #issue-cis-section
  // (rendered server-side by _issue_cis_section.html.erb).
  messages: {},

  init: function(issueId) {
    this.issueId = issueId;
    this.messages = $('#issue-cis-section').data('ci-messages') || {};
    this.bindEvents();
  },

  // Returns the translated message for a key of the data-ci-messages attribute.
  // Parameter key: 'load_failed', 'add_failed', 'add_request_failed', 'remove_failed' or
  //                'remove_request_failed'
  // Returns: String message, or the key itself when the server did not provide the message
  msg: function(key) {
    return this.messages[key] || key;
  },

  bindEvents: function() {
    var self = this;

    // Handle delete CI links
    $(document).on('ajax:success', 'a.icon-del[data-remote="true"]', function(event, data) {
      if (data.success) {
        var row = $(this).closest('tr.ci-row');
        row.fadeOut(300, function() {
          row.remove();
          self.updateCiList();
        });
        if (data.notice) {
          self.showNotice(data.notice);
        }
      } else {
        self.showErrors(data.errors || [self.msg('remove_failed')]);
      }
    });

    $(document).on('ajax:error', 'a.icon-del[data-remote="true"]', function() {
      self.showErrors([self.msg('remove_request_failed')]);
    });

    // Handle tree node clicks in modal
    $(document).on('click', '#ci-selection-tree .node-content', function(e) {
      var node = $(this).closest('.tree-node');
      var nodeType = node.data('type');

      if (nodeType === 'ci') {
        // This is a selectable CI
        var ciId = node.data('id');
        self.addCiToIssue(ciId);
      } else if (nodeType === 'ci_class') {
        // This is a folder, toggle expansion
        var expander = node.find('> .node-content > .expander');
        if (expander.length > 0) {
          if (expander.hasClass('collapsed')) {
            self.expandNode(node);
            expander.removeClass('collapsed').addClass('expanded');
            expander.text('\u25BC');
          } else {
            self.collapseNode(node);
            expander.removeClass('expanded').addClass('collapsed');
            expander.text('\u25B6');
          }
        }
      }
    });

    // Handle expander clicks
    $(document).on('click', '#ci-selection-tree .expander', function(e) {
      e.stopPropagation();
      var expander = $(this);
      var node = expander.closest('.tree-node');

      if (expander.hasClass('collapsed')) {
        self.expandNode(node);
        expander.removeClass('collapsed').addClass('expanded');
        expander.text('\u25BC');
      } else {
        self.collapseNode(node);
        expander.removeClass('expanded').addClass('collapsed');
        expander.text('\u25B6');
      }
    });
  },

  openModal: function() {
    $('#ci-selection-modal').show();
    $('#ci-selection-tree').empty();
    this.loadTreeRoot();
  },

  closeModal: function() {
    $('#ci-selection-modal').hide();
    $('#ci-selection-tree').empty();
  },

  loadTreeRoot: function() {
    var self = this;
    $('#ci-selection-loading').show();

    $.ajax({
      url: '/issues/' + this.issueId + '/cis/available',
      data: {},
      dataType: 'json',
      success: function(nodes) {
        $('#ci-selection-loading').hide();
        self.renderNodes(nodes, $('#ci-selection-tree'));
      },
      error: function() {
        $('#ci-selection-loading').hide();
        self.showErrors([self.msg('load_failed')]);
      }
    });
  },

  loadTreeNode: function(parentId, container) {
    var self = this;

    $.ajax({
      url: '/issues/' + this.issueId + '/cis/available',
      data: { parent_id: parentId },
      dataType: 'json',
      success: function(nodes) {
        self.renderNodes(nodes, container);
      },
      error: function() {
        self.showErrors([self.msg('load_failed')]);
      }
    });
  },

  renderNodes: function(nodes, container) {
    var ul = $('<ul class="tree-list"></ul>');

    $.each(nodes, function(index, node) {
      var li = $('<li class="tree-node" data-id="' + node.id + '" data-type="' + node.type + '"></li>');
      var nodeContent = $('<div class="node-content"></div>');

      // Add title attribute if present (for tooltip)
      if (node.title) {
        nodeContent.attr('title', node.title);
      }

      // Add expand/collapse icon for folders
      if (node.children) {
        var expander = $('<span class="expander collapsed">\u25B6</span>');
        nodeContent.append(expander);
      } else {
        nodeContent.append('<span class="spacer"></span>');
      }

      // Add node icon
      var icon = $('<span class="node-icon"></span>');
      if (node.children) {
        icon.addClass('icon-folder');
      } else {
        icon.addClass('icon-page');
      }
      nodeContent.append(icon);

      // Add node text
      var text = $('<span class="node-text">' + node.text + '</span>');
      if (node.title) {
        text.attr('title', node.title);
      }
      // Make CI nodes selectable
      if (node.type === 'ci') {
        nodeContent.addClass('selectable');
      }
      nodeContent.append(text);

      li.append(nodeContent);
      ul.append(li);
    });

    container.append(ul);
  },

  expandNode: function(node) {
    var nodeId = node.data('id');
    var childContainer = node.find('> .tree-children');

    if (childContainer.length === 0) {
      childContainer = $('<div class="tree-children"></div>');
      node.append(childContainer);
      this.loadTreeNode(nodeId, childContainer);
    } else {
      childContainer.show();
    }
  },

  collapseNode: function(node) {
    var childContainer = node.find('> .tree-children');
    childContainer.hide();
  },

  addCiToIssue: function(ciId) {
    var self = this;

    $.ajax({
      url: '/issues/' + this.issueId + '/cis',
      type: 'POST',
      data: { ci_id: ciId },
      dataType: 'json',
      success: function(response) {
        if (response.success) {
          self.closeModal();

          // Handle both string responses and Document objects
          // (Corrected: the request uses dataType 'json', so response.html is always the
          // rendered row as a string; the former Document branch was dead code and was removed.)
          var htmlContent = response.html || '';

          self.addCiRow(htmlContent);
          if (response.notice) {
            self.showNotice(response.notice);
          }
        } else {
          self.showErrors(response.errors || [self.msg('add_failed')]);
        }
      },
      error: function() {
        self.showErrors([self.msg('add_request_failed')]);
      }
    });
  },

  // Appends a rendered CI row (_ci_row.html.erb) to the CI table of the issue.
  // Parameter html: String HTML of one <tr class="ci-row">, possibly preceded by the AGPL header
  //                 HTML comments of the partial
  // Side effects: inserts the row into tbody#ci-rows and shows the table if it was hidden
  addCiRow: function(html) {
    // If table doesn't exist, create it
    // (Corrected: the table skeleton with the translated headers is always rendered server-side
    // by _issue_cis_section.html.erb and only hidden while empty, so it just has to be shown.)
    var tbody = document.getElementById('ci-rows');
    if (!tbody) {
      return;
    }
    $('#issue-cis-list table').show();

    // Add the new row
    // jQuery's append() picks its parsing wrapper from the first "<tag" in the string, which is
    // the "<https:" of the license header comment, so it would not parse the markup as table
    // content and the browser would drop the <tr>/<td> tags (ticket #148540). insertAdjacentHTML
    // parses in the context of the tbody, so the row stays intact and comments are harmless.
    tbody.insertAdjacentHTML('beforeend', html);
  },

  updateCiList: function() {
    // If no CIs left, just remove the table (Redmine standard - no message shown)
    // (Corrected: the table is hidden instead of removed, so a CI added later can reuse it.)
    if ($('#ci-rows tr').length === 0) {
      $('#issue-cis-list table').hide();
    }
  },

  showNotice: function(message) {
    var notice = $('<div class="flash notice">' + message + '</div>');
    $('#content').prepend(notice);
    setTimeout(function() {
      notice.fadeOut(function() {
        notice.remove();
      });
    }, 3000);
  },

  showErrors: function(errors) {
    var errorDiv = $('<div class="flash error"></div>');
    $.each(errors, function(index, error) {
      errorDiv.append('<div>' + error + '</div>');
    });
    $('#content').prepend(errorDiv);
    setTimeout(function() {
      errorDiv.fadeOut(function() {
        errorDiv.remove();
      });
    }, 5000);
  }
};

// Initialize on document ready (for issue show page)
$(document).ready(function() {
  if ($('#issue-cis-section').length > 0) {
    // Try multiple ways to get issue ID
    var issueId = null;

    // Try from body data attribute
    if ($('body').data('issue-id')) {
      issueId = $('body').data('issue-id');
    }
    // Try from URL
    else {
      var match = window.location.pathname.match(/\/issues\/(\d+)/);
      if (match) {
        issueId = match[1];
      }
    }

    // Try from issue-cis-section data attribute
    if (!issueId && $('#issue-cis-section').data('issue-id')) {
      issueId = $('#issue-cis-section').data('issue-id');
    }

    if (issueId) {
      IssueCis.init(issueId);
    } else {
      console.error('Could not determine issue ID for IssueCis initialization');
    }
  }
});

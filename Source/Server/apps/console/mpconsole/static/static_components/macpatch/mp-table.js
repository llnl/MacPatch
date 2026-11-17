/* MPTable - the one place that knows which table library the console uses.
 *
 * Today this wraps bootstrap-table.  Pages describe the table (columns, data, row
 * actions); they no longer repeat the option block, the action-button formatter or the
 * 'click .xyz' event map.  Swapping the table library later means changing this file.
 *
 *   var t = MPTable.create('#table', {
 *       idField: 'id',
 *       columns: [ {field: 'name', title: 'Name'}, ... ],
 *       data: [ ... ],                       // rows as real JSON, never built from strings
 *       toolbar: '#toolbar',
 *       actions: [                           // optional "operate" column, first column
 *           { name: 'edit', icon: 'fa-pencil', title: 'Edit',
 *             show: function (row) { return true; },          // optional
 *             onClick: function (row) { ... } },
 *       ]
 *   });
 *   icon and title may be strings or functions(row).
 *   An action with href: function(row) renders a real link (new tab) instead of a click handler.
 *
 *   editable on a column      click-to-edit cells, see mp-edit.js (type, url, source, validate, ...)
 *   checkbox: true           adds a leading checkbox column (use selections()/selectedIds(field))
 *   leadColumns: [ ... ]     extra columns placed after the action column (e.g. a Filter column)
 *   size: 'lg'               make action icons fa-lg
 *
 *   t.count()                     number of rows currently in the table
 *   t.removeRow(field, value)     remove the row whose field equals value
 *   t.selections()                checked rows
 *   t.refresh() / t.load(rows)
 */
(function (w, $) {
    'use strict';
    if (w.MPTable) return;

    var DEFAULTS = {
        pagination: true,
        sidePagination: 'client',
        pageList: ['10', '20', '50', '100', 'All'],
        search: true,
        escape: true,               // cell values are data, never markup (formatters still emit HTML)
        showRefresh: false,
        showColumns: true,
        sortable: true,
        icons: {
            refresh: 'fa fa-refresh',
            toggle: 'fa fa-th-list',
            columns: 'fa fa-columns',
            detailOpen: 'fa fa-info-circle',
            detailClose: 'fa fa-minus-circle'
        }
    };

    function esc(s) {
        return String(s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    function resolve(v, row) { return typeof v === 'function' ? v(row) : v; }

    /* Width that fits the icons: about 20px per icon, 21px for each separator, plus the cell padding.
       Pages with a fixed layout can still pass actionsWidth. */
    function defaultActionsWidth(count, sizeClass) {
        var icon = sizeClass ? 26 : 20;
        return count * icon + Math.max(0, count - 1) * 21 + 24;
    }

    function actionColumn(actions, width, size) {
        var sizeClass = size === 'lg' ? 'fa-lg' : '';
        var events = {};
        actions.forEach(function (a) {
            if (a.onClick) events['click .' + a.name] = function (e, value, row, index) { a.onClick(row, index, e); };
        });

        return {
            field: 'operate',
            title: '',
            align: 'center',
            width: width || defaultActionsWidth(actions.length, sizeClass),
            events: events,
            formatter: function (value, row) {
                var items = actions
                    .filter(function (a) { return !a.show || a.show(row); })
                    .map(function (a) {
                        var href = a.href ? a.href(row) : '';
                        var disabled = a.href && !href;
                        return '<div class="buttonItem"><a class="' + esc(a.name) + (disabled ? ' disabled' : '') + '"' +
                            ' href="' + (href ? esc(href) + '" target="_blank' : 'javascript:void(0)') + '"' +
                            ' title="' + esc(resolve(a.title, row)) + '">' +
                            '<i class="fa ' + esc(resolve(a.icon, row)) + (sizeClass ? ' ' + sizeClass : '') + '" aria-hidden="true"></i></a></div>';
                    });
                return '<div class="buttonGroup">' + items.join('<i class="buttonSeperator"></i>') + '</div>';
            }
        };
    }

    function create(selector, config) {
        var $table = $(selector);
        var options = $.extend(true, {}, DEFAULTS, config);
        var actions = options.actions;
        delete options.actions;

        var lead = [];
        if (options.checkbox) {
            lead.push({ field: options.stateField || 'state', checkbox: true, align: 'center', valign: 'middle', width: 40 });
        }
        if (actions && actions.length) {
            lead.push(actionColumn(actions, options.actionsWidth, options.size));
        }
        options.columns = lead.concat(options.leadColumns || [], options.columns);

        // bootstrap-table clears every check on a page change unless maintainMetaData is set
        // ('maintainSelected' was removed from the library, this is its replacement).  Any table with a
        // checkbox column keeps its selection, whether the page used the checkbox option or its own column.
        var hasCheckbox = options.columns.some(function (c) { return c.checkbox; });
        if (hasCheckbox && options.maintainMetaData === undefined) options.maintainMetaData = true;

        ['actionsWidth', 'checkbox', 'stateField', 'leadColumns', 'size'].forEach(function (k) { delete options[k]; });

        // Editable columns: the column's formatter shows the editable link, clicks are handled by MPEdit.
        // bootstrap-table's own editable extension is switched off, MPEdit replaces x-editable.
        options.editable = false;
        if (w.MPEdit) {
            w.MPEdit.attach($table, options.columns, options.idField);
            options.columns.forEach(function (c) { delete c.editable; });
        }

        $table.bootstrapTable(options);

        return {
            $el: $table,
            count: function () { return $table.bootstrapTable('getData').length; },
            removeRow: function (field, value) { $table.bootstrapTable('remove', { field: field, values: [value] }); },
            selections: function () { return $table.bootstrapTable('getSelections'); },
            selectedIds: function (field) { return $table.bootstrapTable('getSelections').map(function (r) { return r[field]; }); },
            removeRows: function (field, values) { $table.bootstrapTable('remove', { field: field, values: values }); },
            refresh: function () { $table.bootstrapTable('refresh'); },
            load: function (rows) { $table.bootstrapTable('load', rows); }
        };
    }

    w.MPTable = { create: create, escape: esc };
}(window, window.jQuery));

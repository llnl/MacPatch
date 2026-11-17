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

    function actionColumn(actions, width) {
        var events = {};
        actions.forEach(function (a) {
            events['click .' + a.name] = function (e, value, row, index) { a.onClick(row, index, e); };
        });

        return {
            field: 'operate',
            title: '',
            align: 'center',
            width: width || 160,
            events: events,
            formatter: function (value, row) {
                var items = actions
                    .filter(function (a) { return !a.show || a.show(row); })
                    .map(function (a) {
                        return '<div class="buttonItem"><a class="' + esc(a.name) + '" href="javascript:void(0)"' +
                            ' title="' + esc(resolve(a.title, row)) + '">' +
                            '<i class="fa ' + esc(resolve(a.icon, row)) + '" aria-hidden="true"></i></a></div>';
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

        if (actions && actions.length) {
            options.columns = [actionColumn(actions, options.actionsWidth)].concat(options.columns);
        }
        delete options.actionsWidth;

        $table.bootstrapTable(options);

        return {
            $el: $table,
            count: function () { return $table.bootstrapTable('getData').length; },
            removeRow: function (field, value) { $table.bootstrapTable('remove', { field: field, values: [value] }); },
            selections: function () { return $table.bootstrapTable('getSelections'); },
            refresh: function () { $table.bootstrapTable('refresh'); },
            load: function (rows) { $table.bootstrapTable('load', rows); }
        };
    }

    w.MPTable = { create: create, escape: esc };
}(window, window.jQuery));

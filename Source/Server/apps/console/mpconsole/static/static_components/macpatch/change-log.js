(function ($) {
    'use strict';
    function escape(value) {
        return $('<span>').text(value == null ? '' : String(value)).html();
    }
    function display(value) {
        return value === null ? '(empty)' : typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value);
    }
    $(function () {
        var $table = $('#change-log-table-view');
        var $filters = $('#change-log-filters');
        var $error = $('#change-log-error');
        $table.bootstrapTable({
            url: '/console/change_log/data',
            sidePagination: 'server', pagination: true, pageSize: 25,
            pageList: [25, 50, 100], search: true, searchTimeOut: 400,
            showRefresh: true, uniqueId: 'rid', detailView: true,
            queryParams: function (params) {
                $filters.serializeArray().forEach(function (field) { params[field.name] = field.value; });
                return params;
            },
            columns: [
                {field: 'created_at', title: 'Time', formatter: function (value) { return escape(new Date(value).toLocaleString()); }},
                {field: 'actor', title: 'User', formatter: escape},
                {field: 'action', title: 'Action', formatter: escape},
                {field: 'record_table', title: 'Record Type', formatter: escape},
                {field: 'record_label', title: 'Record', formatter: function (value, row) { return escape(value || JSON.stringify(row.record_key)); }},
                {field: 'changes', title: 'Changed Fields', formatter: function (value) { return escape(Object.keys(value).join(', ')); }}
            ],
            detailFormatter: function (index, row) {
                var html = '<div><strong>Record ID:</strong> ' + escape(JSON.stringify(row.record_key)) +
                    ' &nbsp; <strong>Request:</strong> ' + escape(row.request_id) +
                    ' &nbsp; ' + escape(row.method + ' ' + row.endpoint) + '</div>';
                html += '<table class="table table-bordered table-sm change-log-values"><thead><tr><th>Field</th><th>Before</th><th>After</th></tr></thead><tbody>';
                Object.keys(row.changes).forEach(function (field) {
                    var change = row.changes[field];
                    html += '<tr><td>' + escape(field) + '</td><td><pre>' + escape(display(change.before)) +
                        '</pre></td><td><pre>' + escape(display(change.after)) + '</pre></td></tr>';
                });
                return html + '</tbody></table>';
            },
            onLoadSuccess: function () { $error.prop('hidden', true); },
            onLoadError: function () { $error.text('Unable to load the change log. Please try again.').prop('hidden', false); }
        });
        $.getJSON('/console/change_log/filters').done(function (data) {
            data.actors.forEach(function (actor) { $('#change-log-actor').append($('<option>').val(actor).text(actor)); });
            data.tables.forEach(function (name) { $('#change-log-table').append($('<option>').val(name).text(name)); });
        });
        $filters.on('submit', function (event) { event.preventDefault(); $table.bootstrapTable('refresh', {pageNumber: 1}); });
        $filters.on('reset', function () { setTimeout(function () { $table.bootstrapTable('resetSearch', ''); $table.bootstrapTable('refresh', {pageNumber: 1}); }, 0); });
    });
}(jQuery));

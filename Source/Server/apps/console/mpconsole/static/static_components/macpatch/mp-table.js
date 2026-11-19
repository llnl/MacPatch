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
 *   An action with label: 'API' shows that text next to the icon; className adds extra classes to the link
 *   (e.g. className: 'server-log-action' for the inline icon + text layout).
 *   An action with showDisabled: true stays in the row as a greyed out, unclickable icon when show(row) is false
 *   (instead of disappearing), so the buttons keep their place.
 *   An action with href: function(row) renders a real link (new tab) instead of a click handler.
 *
 *   editable on a column      click-to-edit cells, see mp-edit.js (type, url, source, validate, ...)
 *   checkbox: true           adds a leading checkbox column (use selections()/selectedIds(field))
 *   leadColumns: [ ... ]     extra columns placed after the action column (e.g. a Filter column)
 *   size: 'lg'               make action icons fa-lg
 *
 *   Column choices (the columns menu) are saved per user on the server (/console/prefs/columns) so they follow
 *   the user to any browser, but each browser works from its own localStorage copy.  The page only carries a
 *   short hash per saved table (window.MP_PREFS); the saved choice is fetched when that hash differs from the
 *   one stored in this browser.  A change that could not be sent stays marked unsynced and is retried on the next
 *   page load.  Columns a page adds later keep their default.
 *   persistColumns: false    opt out
 *   columnsKey: 'name'       store under this name instead of the page path + table id (use it for pages whose
 *                            URL contains ids or other changing parts)
 *   t.resetColumns()         forget the saved choice and go back to the page defaults (reloads the page)
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
                    .filter(function (a) { return !a.show || a.show(row) || a.showDisabled; })
                    .map(function (a) {
                        var href = a.href ? a.href(row) : '';
                        var off = a.show && !a.show(row);
                        if (off) {
                            return '<div class="buttonItem"><i class="fa ' + esc(resolve(a.icon, row)) +
                                (sizeClass ? ' ' + sizeClass : '') + ' disabled" aria-hidden="true"></i></div>';
                        }
                        var disabled = a.href && !href;
                        var label = a.label ? '<span>' + esc(resolve(a.label, row)) + '</span>' : '';
                        return '<div class="buttonItem"><a class="' + esc(a.name) + (a.className ? ' ' + esc(a.className) : '') + (disabled ? ' disabled' : '') + '"' +
                            ' href="' + (href ? esc(href) + '" target="_blank' : 'javascript:void(0)') + '"' +
                            ' title="' + esc(resolve(a.title, row)) + '">' +
                            '<i class="fa ' + esc(resolve(a.icon, row)) + (sizeClass ? ' ' + sizeClass : '') + '" aria-hidden="true"></i>' + label + '</a></div>';
                    });
                return '<div class="buttonGroup">' + items.join('<i class="buttonSeperator"></i>') + '</div>';
            }
        };
    }

    function storageKey($table, name) {
        return name || (w.location.pathname + ':' + ($table.attr('id') || ''));
    }

    /* The browser copy is {columns: {field: bool}, hash, dirty}.  hash is the server's fingerprint of what this
       browser last saw; dirty means a change has not reached the server yet.  Older entries are a bare
       {field: bool} map, they are treated as unsynced and uploaded. */
    function readLocal(key) {
        try {
            var v = JSON.parse(w.localStorage.getItem('mptable.columns:' + key));
            if (!v || typeof v !== 'object') return null;
            if (v.columns && typeof v.columns === 'object') return v;
            return { columns: v, hash: null, dirty: true };
        } catch (e) { return null; }
    }

    function writeLocal(key, entry) {
        try { w.localStorage.setItem('mptable.columns:' + key, JSON.stringify(entry)); } catch (e) { /* storage blocked */ }
    }

    function dropLocal(key) {
        try { w.localStorage.removeItem('mptable.columns:' + key); } catch (e) { /* ignore */ }
    }

    function serverHash(key) {
        var prefs = w.MP_PREFS && w.MP_PREFS.columns;
        return prefs && typeof prefs[key] === 'string' ? prefs[key] : null;
    }

    function currentState($table) {
        var state = {};
        $table.bootstrapTable('getVisibleColumns').forEach(function (c) { if (c.field) state[c.field] = true; });
        $table.bootstrapTable('getHiddenColumns').forEach(function (c) { if (c.field) state[c.field] = false; });
        return state;
    }

    function push(key, columns) {
        if (!w.MPHttp) return;
        w.MPHttp.sendJSONAs('PUT', '/console/prefs/columns', { key: key, columns: columns }).then(function (res) {
            var local = readLocal(key);
            // only mark it clean if nothing changed while the request was running
            if (local && JSON.stringify(local.columns) === JSON.stringify(columns)) {
                writeLocal(key, { columns: columns, hash: res.hash, dirty: false });
            }
        }, function () { /* stays dirty, the next page load tries again */ });
    }

    /* Apply a saved choice to a table that already exists; columns it does not mention go back to their default. */
    function applyState($table, state, defaults) {
        var visible = {};
        $table.bootstrapTable('getVisibleColumns').forEach(function (c) { visible[c.field] = true; });
        var show = [], hide = [];
        Object.keys(defaults).forEach(function (field) {
            var want = typeof state[field] === 'boolean' ? state[field] : defaults[field];
            if (want && !visible[field]) show.push(field);
            if (!want && visible[field]) hide.push(field);
        });
        if (show.length) $table.bootstrapTable('showColumn', show);
        if (hide.length) $table.bootstrapTable('hideColumn', hide);
    }

    /* Local first: the table is already shown from this browser's copy.  Only when the server's hash differs
       from the one stored here is the saved choice fetched (a change made in another browser). */
    function sync($table, key, defaults) {
        if (!w.MPHttp) return;
        var local = readLocal(key);
        var remote = serverHash(key);

        if (local && local.dirty) return push(key, local.columns);
        if (!w.MP_PREFS) return;   // this page was not given the server data: keep the browser copy as it is
        if (remote === null) {
            if (local) { dropLocal(key); applyState($table, {}, defaults); }   // reset from another browser
            return;
        }
        if (local && local.hash === remote) return;

        w.MPHttp.getJSON('/console/prefs/columns?key=' + encodeURIComponent(key)).then(function (res) {
            writeLocal(key, { columns: res.columns, hash: res.hash, dirty: false });
            applyState($table, res.columns, defaults);
        }, function () { /* keep what this browser has */ });
    }

    function resetColumns(key) {
        dropLocal(key);
        var done = function () { w.location.reload(); };
        if (!w.MPHttp) return done();
        w.MPHttp.sendJSONAs('DELETE', '/console/prefs/columns', { key: key }).then(done, done);
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

        var persist = options.persistColumns !== false;
        var key = storageKey($table, options.columnsKey);
        delete options.persistColumns;
        delete options.columnsKey;
        var defaults = {};
        if (persist) {
            var local = readLocal(key);
            var saved = local ? local.columns : {};
            options.columns.forEach(function (c) {
                if (!c.field || c.checkbox || c.field === 'operate') return;
                defaults[c.field] = c.visible !== false;
                if (typeof saved[c.field] === 'boolean') c.visible = saved[c.field];
            });
        }

        // headers may wrap (see .mp-table in console-theme.css) so the columns can shrink to the window width
        $table.addClass('mp-table');

        $table.bootstrapTable(options);

        if (persist) {
            var timer = null;
            $table.on('column-switch.bs.table column-switch-all.bs.table', function () {
                var columns = currentState($table);
                var prev = readLocal(key);
                writeLocal(key, { columns: columns, hash: prev ? prev.hash : null, dirty: true });
                clearTimeout(timer);
                timer = setTimeout(function () { push(key, columns); }, 300);
            });
            sync($table, key, defaults);
        }

        return {
            $el: $table,
            count: function () { return $table.bootstrapTable('getData').length; },
            removeRow: function (field, value) { $table.bootstrapTable('remove', { field: field, values: [value] }); },
            selections: function () { return $table.bootstrapTable('getSelections'); },
            selectedIds: function (field) { return $table.bootstrapTable('getSelections').map(function (r) { return r[field]; }); },
            removeRows: function (field, values) { $table.bootstrapTable('remove', { field: field, values: values }); },
            resetColumns: function () { resetColumns(key); },
            refresh: function () { $table.bootstrapTable('refresh'); },
            load: function (rows) { $table.bootstrapTable('load', rows); }
        };
    }

    w.MPTable = { create: create, escape: esc };
}(window, window.jQuery));

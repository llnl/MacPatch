/* MPEdit - click-to-edit table cells.  Replaces x-editable and its Bootstrap popover shims.
 *
 * Columns keep the same `editable` settings the pages already use:
 *
 *   { field: 'active', editable: { type: 'select', url: '/patches/custom/active',
 *                                  source: [{value: 0, text: 'False'}, {value: 1, text: 'True'}] } }
 *
 *   type        'text' (default) | 'select' | 'date'
 *   url         POSTed to with form fields  pk, name, value  (what the existing server routes read)
 *   pk          value sent as `pk`, default is the row's idField
 *   source      [{value, text}] for select
 *   validate    function(value) -> an error message to refuse the value
 *   title       tooltip on the cell (select cells get a small chevron after the text, see mp.css)
 *   emptytext   shown when the cell is empty
 *   format      for date, 'yyyy-mm-dd' (default)
 *
 * A failed save keeps the editor open and shows the server's message under it.  Escape cancels.
 * A successful save updates the row and fires `editable-save.bs.table` with (field, row, oldValue),
 * the same event x-editable fired, so pages that refresh on save keep working.
 *
 * How it is wired: MPTable wraps each editable column's formatter so the cell shows a link, and
 * calls MPEdit.attach($table, columns, idField) once.  There is no per-cell setup, one click handler on the
 * table body handles every cell, so it keeps working when the table is paged, sorted or reloaded.
 */
(function (w, $) {
    'use strict';
    if (w.MPEdit) return;

    var EMPTY_DEFAULT = 'Empty';

    function esc(s) {
        return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    function csrf() {
        var meta = document.querySelector('meta[name="csrf-token"]');
        return meta ? meta.getAttribute('content') : null;
    }

    function textFor(opts, value) {
        if (opts.type === 'select') {
            var found = (opts.source || []).filter(function (o) { return String(o.value) === String(value); })[0];
            if (found) return found.text;
        }
        return value === null || value === undefined ? '' : String(value);
    }

    /* What the cell shows.  The value is escaped here, formatters in bootstrap-table are not escaped. */
    function display(opts, value, field) {
        var text = textFor(opts, value);
        var empty = text === '';
        return '<a href="javascript:void(0)" class="mp-editable' + (opts.type === 'select' ? ' mp-editable-select' : '') + (empty ? ' mp-editable-empty' : '') + '"' +
            ' data-mp-edit="' + esc(field) + '"' + (opts.title ? ' title="' + esc(opts.title) + '"' : '') + '>' +
            esc(empty ? (opts.emptytext || EMPTY_DEFAULT) : text) + '</a>';
    }

    function buildInput(opts, value) {
        var input;
        if (opts.type === 'select') {
            input = document.createElement('select');
            (opts.source || []).forEach(function (o) {
                var option = document.createElement('option');
                option.value = o.value;
                option.textContent = o.text;
                if (String(o.value) === String(value)) option.selected = true;
                input.appendChild(option);
            });
        } else {
            input = document.createElement('input');
            input.type = opts.type === 'date' ? 'date' : 'text';
            input.value = value === null || value === undefined ? '' : String(value);
        }
        // Bootstrap 5 draws a select's arrow through .form-select; .form-control leaves it a plain box.
        input.className = (opts.type === 'select' ? 'form-select form-select-sm' : 'form-control form-control-sm') + ' mp-editable-input';
        return input;
    }

    function post(url, data) {
        var body = new URLSearchParams(data);
        var headers = { 'X-Requested-With': 'XMLHttpRequest' };
        var token = csrf();
        if (token) headers['X-CSRFToken'] = token;
        return fetch(url, { method: 'POST', headers: headers, body: body, credentials: 'same-origin' })
            .then(function (response) {
                return response.text().then(function (text) {
                    if (!response.ok) {
                        var err = new Error(text || ('Save failed (HTTP ' + response.status + ')'));
                        err.status = response.status;
                        throw err;
                    }
                    return text;
                });
            });
    }

    /* Open the editor over a cell.  Only one editor is open at a time. */
    function openEditor($table, idField, column, link, row) {
        var opts = column.mpEditable;
        var $td = $(link).closest('td');
        if ($td.find('.mp-editable-form').length) return;
        closeEditors($table);

        var oldValue = row[column.field];
        var form = document.createElement('form');
        form.className = 'mp-editable-form form-inline';
        form.style.cssText = 'display:flex;align-items:flex-start;flex-wrap:wrap;';

        var input = buildInput(opts, oldValue);
        var ok = document.createElement('button');
        ok.type = 'submit'; ok.className = 'btn btn-primary btn-sm'; ok.setAttribute('aria-label', 'Save');
        ok.innerHTML = '<i class="fa fa-check" aria-hidden="true"></i>';
        var cancel = document.createElement('button');
        cancel.type = 'button'; cancel.className = 'btn btn-default btn-sm'; cancel.setAttribute('aria-label', 'Cancel');
        cancel.innerHTML = '<i class="fa fa-times" aria-hidden="true"></i>';
        var message = document.createElement('div');
        message.className = 'mp-editable-error text-danger small';
        message.style.cssText = 'flex-basis:100%;display:none;';

        form.appendChild(input); form.appendChild(ok); form.appendChild(cancel); form.appendChild(message);
        link.style.display = 'none';
        link.parentNode.insertBefore(form, link.nextSibling);
        input.focus();
        if (input.select && input.type === 'text') input.select();

        function close() {
            form.remove();
            link.style.display = '';
        }
        form._close = close;

        cancel.addEventListener('click', close);
        form.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.preventDefault(); close(); } });

        form.addEventListener('submit', function (e) {
            e.preventDefault();
            var value = input.value;

            if (opts.validate) {
                var problem = opts.validate(value);
                if (problem) { message.textContent = problem; message.style.display = ''; return; }
            }
            if (String(value) === String(oldValue === null || oldValue === undefined ? '' : oldValue)) { close(); return; }

            var pk = opts.pk !== undefined ? opts.pk : row[idField];
            var data = { pk: pk, name: column.field, value: value };
            if (opts.params) $.extend(data, typeof opts.params === 'function' ? opts.params(data) : opts.params);

            ok.disabled = cancel.disabled = input.disabled = true;
            post(opts.url, data)
                .then(function (response) {
                    row[column.field] = value;
                    link.outerHTML = display(opts, value, column.field);
                    close();
                    if (opts.success) opts.success(response, value);
                    $table.trigger('editable-save.bs.table', [column.field, row, oldValue, $td]);
                })
                .catch(function (err) {
                    ok.disabled = cancel.disabled = input.disabled = false;
                    message.textContent = err.message || 'Save failed.';
                    message.style.display = '';
                    input.focus();
                });
        });
    }

    function closeEditors($table) {
        $table.find('.mp-editable-form').each(function () { if (this._close) this._close(); });
    }

    /* Wrap each editable column's formatter, and handle clicks for all of them */
    function attach($table, columns, idField) {
        var editable = columns.filter(function (c) { return c.editable; });
        if (!editable.length) return;

        editable.forEach(function (column) {
            var opts = column.editable;
            var inner = column.formatter;
            column.mpEditable = opts;          // our copy, the library never sees the `editable` key
            column.escape = false;             // display() escapes the value itself, the library must not escape the link
            column.formatter = function (value, row, index) {
                return display(opts, inner ? inner(value, row, index) : value, column.field);
            };
        });

        $table.on('click', 'a.mp-editable', function (e) {
            e.preventDefault();
            var field = this.getAttribute('data-mp-edit');
            var column = editable.filter(function (c) { return c.field === field; })[0];
            var index = $(this).closest('tr').data('index');
            var row = $table.bootstrapTable('getData')[index];
            if (column && row) openEditor($table, idField, column, this, row);
        });
    }

    w.MPEdit = { attach: attach, display: display };
}(window, window.jQuery));

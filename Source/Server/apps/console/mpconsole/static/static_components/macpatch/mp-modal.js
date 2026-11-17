/* MPModal - drives the shared #modalDialog defined in base.html.
 *
 * Replaces the resetModalWindow(); set title; set body; set height; .modal('show')
 * sequence that is copied into every page.  Titles are set as text (not HTML), so
 * names that come from the database can not inject markup.
 *
 *   MPModal.open({ title, url | html | iframe, size, height, footer })
 *       url     fetch an HTML fragment and show it
 *       html    show this HTML fragment
 *       iframe  show this URL in an iframe
 *       size    '' (default) | 'mid' | 'wide'
 *       height  css height for the body, e.g. '200px', '60vh'
 *       footer  false hides the Cancel/Save footer (default true)
 *   MPModal.error(title, message)   red "Close only" dialog
 *   MPModal.close()
 *
 * The only jQuery use is the Bootstrap show/hide call, kept in show()/close() so it is
 * the single line to change when Bootstrap's modal is replaced.
 */
(function (w) {
    'use strict';
    if (w.MPModal) return;

    function byId(id) { return document.getElementById(id); }

    function show() { w.jQuery('#modalDialog').modal('show'); }

    function close() { w.jQuery('#modalDialog').modal('hide'); }

    function reset() {
        w.resetModalWindow();                       // from base.html
        byId('modalSaveButton').style.display = '';
        byId('modalCancelButton').textContent = 'Cancel';
        byId('modalBody').style.height = '';
    }

    function present(opts, content) {
        reset();

        byId('modalTitle').textContent = opts.title || '';

        var body = byId('modalBody');
        if (typeof content === 'string') {
            body.innerHTML = '<div id="myContent">' + content + '</div>';
        } else {
            body.replaceChildren(content);
        }

        if (opts.height) body.style.height = opts.height;
        if (opts.size === 'wide') byId('modalDialog').classList.add('modal-wide');
        if (opts.size === 'mid') byId('modalDialog').classList.add('modal-mid');
        if (opts.footer === false) byId('modalFooter').style.display = 'none';

        show();
    }

    function open(opts) {
        if (opts.iframe) {
            var frame = document.createElement('iframe');
            frame.id = 'modaliFrame';
            frame.src = opts.iframe;
            frame.setAttribute('frameborder', '0');
            frame.setAttribute('allowtransparency', 'true');
            frame.style.cssText = 'width: 98%; height: 98%; position: absolute';
            present(opts, frame);
            return Promise.resolve();
        }
        if (opts.url) {
            return w.MPHttp.get(opts.url).then(function (html) { present(opts, html); });
        }
        present(opts, opts.html || '');
        return Promise.resolve();
    }

    function error(title, message) {
        present({ title: title, html: '', height: '200px' }, '');
        byId('modalBody').textContent = message;
        byId('modalSaveButton').style.display = 'none';
        byId('modalCancelButton').textContent = 'Close';
        byId('modalHeader').classList.add('panel-heading');
        byId('modalContent').classList.add('panel-danger');
    }

    w.MPModal = { open: open, error: error, close: close };
}(window));

/* MPBusy - "working" indicator for actions that take a few seconds (saving, deleting, ...).
 *
 *   MPBusy.run(promise, { message: 'Saving...', button: element })  -> the same promise
 *       shows a full page overlay with a spinner and the message until the promise settles,
 *       and disables `button` meanwhile so the action can not be started twice.
 *
 *   MPBusy.show('Saving...') / MPBusy.hide()   for manual control
 *
 * Needs no stylesheet, the overlay is styled inline.  It sits above Bootstrap modals (z-index 2000).
 */
(function (w) {
    'use strict';
    if (w.MPBusy) return;

    var overlay = null;
    var depth = 0;                       // overlapping calls keep the overlay until the last one ends

    function build(message) {
        var el = document.createElement('div');
        el.id = 'mpBusyOverlay';
        el.setAttribute('role', 'alert');
        el.setAttribute('aria-live', 'assertive');
        el.style.cssText = 'position:fixed;top:0;right:0;bottom:0;left:0;z-index:2000;' +
            'background:rgba(0,0,0,.55);display:flex;flex-direction:column;' +
            'align-items:center;justify-content:center;color:#fff;';

        var spinner = document.createElement('i');
        spinner.className = 'fa fa-spinner fa-spin fa-3x';
        spinner.setAttribute('aria-hidden', 'true');

        var text = document.createElement('div');
        text.id = 'mpBusyMessage';
        text.style.cssText = 'margin-top:14px;font-size:20px;';
        text.textContent = message;

        el.appendChild(spinner);
        el.appendChild(text);
        return el;
    }

    function show(message) {
        depth++;
        if (!overlay) {
            overlay = build(message || 'Working...');
            document.body.appendChild(overlay);
        } else if (message) {
            overlay.querySelector('#mpBusyMessage').textContent = message;
        }
    }

    function hide() {
        depth = Math.max(0, depth - 1);
        if (depth === 0 && overlay) {
            overlay.remove();
            overlay = null;
        }
    }

    function run(promise, opts) {
        opts = opts || {};
        var button = opts.button;
        if (button) button.disabled = true;
        show(opts.message);

        function done() {
            hide();
            if (button) button.disabled = false;
        }
        promise.then(done, done);
        return promise;
    }

    w.MPBusy = { run: run, show: show, hide: hide };
}(window));

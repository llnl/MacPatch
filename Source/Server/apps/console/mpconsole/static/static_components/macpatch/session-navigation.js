/* An expired modal or table request must log out the whole console tab.
 * Also adds the CSRF token (from <meta name="csrf-token">) to state changing requests. */
(function ($) {
    'use strict';
    if (!$ || $.macpatchSessionNavigation) return;
    $.macpatchSessionNavigation = true;
    var redirecting = false;
    var safeMethods = /^(GET|HEAD|OPTIONS|TRACE)$/i;

    function csrfToken() {
        var meta = document.querySelector('meta[name="csrf-token"]');
        return meta ? meta.getAttribute('content') : null;
    }

    $.ajaxPrefilter(function (options, originalOptions, xhr) {
        if (!options.crossDomain && !safeMethods.test(options.type)) {
            var token = csrfToken();
            if (token) xhr.setRequestHeader('X-CSRFToken', token);
        }

        xhr.always(function () {
            var loginUrl = xhr.getResponseHeader('X-MacPatch-Login');
            if (xhr.status !== 401 || !loginUrl || redirecting) return;
            var target = new URL(loginUrl, window.location.href);
            if (target.origin !== window.location.origin) return;
            redirecting = true;
            window.top.location.replace(target.href);
        });
    });

    /* Regular (non AJAX) form posts can not send a header, add the token as a field.
     * Runs after the page's own submit handlers, so forms they send via AJAX are skipped. */
    window.addEventListener('submit', function (event) {
        var form = event.target;
        if (event.defaultPrevented || !form || (form.method || '').toLowerCase() !== 'post') return;
        if (form.querySelector('input[name="csrf_token"]')) return;
        var token = csrfToken();
        if (!token) return;
        var input = document.createElement('input');
        input.type = 'hidden';
        input.name = 'csrf_token';
        input.value = token;
        form.appendChild(input);
    });
}(window.jQuery));

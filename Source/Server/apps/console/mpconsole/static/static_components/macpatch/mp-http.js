/* MPHttp - fetch based request helper (no jQuery).
 *
 * Replaces the per page $.ajax/$.get/$.post + error handler boilerplate.
 *   - adds the CSRF header (from <meta name="csrf-token">) to state changing requests
 *   - sends the whole console tab to the login page when the session has expired
 *     (same contract as session-navigation.js does for jQuery requests)
 *   - rejects on HTTP errors, the Error has .status and .body
 *
 *   MPHttp.get(url)                 -> Promise<string>   (HTML fragments)
 *   MPHttp.post(url, data)          -> Promise<string>   (data: plain object or FormData, optional)
 *   MPHttp.getJSON(url)             -> Promise<object>
 *   MPHttp.postJSON(url, data)      -> Promise<object>   (parses the response body as JSON)
 *   MPHttp.delete(url, data)        -> Promise<string>
 *   MPHttp.errorMessage(err)        -> the server's {"errormsg": ...} text, or a generic message
 */
(function (w) {
    'use strict';
    if (w.MPHttp) return;

    var safeMethods = /^(GET|HEAD|OPTIONS|TRACE)$/i;
    var redirecting = false;

    function csrfToken() {
        var meta = document.querySelector('meta[name="csrf-token"]');
        return meta ? meta.getAttribute('content') : null;
    }

    function request(url, opts) {
        opts = opts || {};
        var method = (opts.method || 'GET').toUpperCase();
        var headers = { 'X-Requested-With': 'XMLHttpRequest' };
        var body;

        if (!safeMethods.test(method)) {
            var token = csrfToken();
            if (token) headers['X-CSRFToken'] = token;
        }

        if (opts.data instanceof FormData) {
            body = opts.data;
        } else if (opts.data) {
            body = new URLSearchParams(opts.data);   // form encoded, same as $.post
        }

        return fetch(url, {
            method: method,
            headers: headers,
            body: body,
            credentials: 'same-origin'
        }).then(function (response) {
            var loginUrl = response.headers.get('X-MacPatch-Login');
            if (response.status === 401 && loginUrl && !redirecting) {
                var target = new URL(loginUrl, w.location.href);
                if (target.origin === w.location.origin) {
                    redirecting = true;
                    w.top.location.replace(target.href);
                }
            }
            return response.text().then(function (text) {
                if (!response.ok) {
                    var err = new Error('HTTP ' + response.status + ' for ' + url);
                    err.status = response.status;
                    err.body = text;
                    throw err;
                }
                return text;
            });
        });
    }

    function errorMessage(err) {
        try { var m = JSON.parse(err.body).errormsg; if (m) return m; } catch (e) { /* not JSON */ }
        return 'Request failed' + (err && err.status ? ' (HTTP ' + err.status + ')' : '') + '.';
    }

    w.MPHttp = {
        request: request,
        errorMessage: errorMessage,
        delete: function (url, data) { return request(url, { method: 'DELETE', data: data }); },
        get: function (url) { return request(url); },
        post: function (url, data) { return request(url, { method: 'POST', data: data }); },
        getJSON: function (url) { return request(url).then(JSON.parse); },
        postJSON: function (url, data) { return request(url, { method: 'POST', data: data }).then(JSON.parse); }
    };
}(window));

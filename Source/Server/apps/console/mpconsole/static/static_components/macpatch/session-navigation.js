/* An expired modal or table request must log out the whole console tab. */
(function ($) {
    'use strict';
    if (!$ || $.macpatchSessionNavigation) return;
    $.macpatchSessionNavigation = true;
    var redirecting = false;

    $.ajaxPrefilter(function (options, originalOptions, xhr) {
        xhr.always(function () {
            var loginUrl = xhr.getResponseHeader('X-MacPatch-Login');
            if (xhr.status !== 401 || !loginUrl || redirecting) return;
            var target = new URL(loginUrl, window.location.href);
            if (target.origin !== window.location.origin) return;
            redirecting = true;
            window.top.location.replace(target.href);
        });
    });
}(window.jQuery));

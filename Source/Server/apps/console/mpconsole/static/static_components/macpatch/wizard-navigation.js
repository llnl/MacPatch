(function (window) {
    'use strict';

    window.WizardNavigation = {
        open: function (url) {
            var target = new URL(url, window.location.origin);
            target.searchParams.set('return_to', window.location.pathname + window.location.search + window.location.hash);
            window.location.assign(target.pathname + target.search + target.hash);
        },
        returnToParent: function (fallback) {
            var requested = new URLSearchParams(window.location.search).get('return_to');
            var target = new URL(fallback, window.location.origin);
            if (requested) {
                try {
                    var candidate = new URL(requested, window.location.origin);
                    if (candidate.origin === window.location.origin) {
                        target = candidate;
                    }
                } catch (error) {
                    // Use the wizard's parent view when the supplied URL is invalid.
                }
            }
            window.location.assign(target.pathname + target.search + target.hash);
        }
    };
})(window);

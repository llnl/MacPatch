/* Console shell (Bootstrap 5 / SB Admin 2): opens the menu section of the current page.  The sidebar is
 * always shown, there is no hide/show toggle.
 *
 * Replaces sb-admin-2.js and the metismenu code that used to live in base.html.
 *
 * A page that is not in the menu itself (edit pages, wizards) names the item it belongs under with
 * data-active-menu on <body>.
 */
(function (w, d) {
    'use strict';

    var sidebar = d.querySelector('.sidebar');
    if (!sidebar) return;

    // Open the section that holds the current page and mark its link.
    var activePath = d.body.getAttribute('data-active-menu') || w.location.pathname;
    var link = null;
    sidebar.querySelectorAll('a[href]').forEach(function (a) {
        if (!link && a.getAttribute('href') !== '#' && a.pathname === activePath) link = a;
    });
    if (link) {
        link.classList.add('active');
        for (var el = link.parentElement; el && el !== sidebar; el = el.parentElement) {
            if (el.classList.contains('collapse')) {
                el.classList.add('show');
                var toggle = sidebar.querySelector('[data-bs-target="#' + el.id + '"]');
                if (toggle) { toggle.classList.remove('collapsed'); toggle.setAttribute('aria-expanded', 'true'); }
            }
            if (el.classList.contains('nav-item')) el.classList.add('active');
        }
    }
}(window, document));

/* Console shell (Bootstrap 5 / SB Admin 2): sidebar toggle, responsive collapse, and opening the menu
 * section of the current page.
 *
 * Replaces sb-admin-2.js (jQuery .collapse() plugin calls do not exist in Bootstrap 5) and the metismenu
 * code that used to live in base.html.
 *
 * A page that is not in the menu itself (edit pages, wizards) names the item it belongs under with
 * data-active-menu on <body>.
 */
(function (w, d) {
    'use strict';

    var sidebar = d.querySelector('.sidebar');
    if (!sidebar) return;

    function sections() { return sidebar.querySelectorAll('.collapse'); }

    function hideSections() {
        sections().forEach(function (el) {
            var c = w.bootstrap.Collapse.getInstance(el);
            if (c) c.hide(); else el.classList.remove('show');
        });
    }

    function setToggled(on) {
        d.body.classList.toggle('sidebar-toggled', on);
        sidebar.classList.toggle('toggled', on);
        if (on) hideSections();
    }

    d.querySelectorAll('#sidebarToggle, #sidebarToggleTop').forEach(function (btn) {
        btn.addEventListener('click', function (e) {
            e.preventDefault();
            setToggled(!sidebar.classList.contains('toggled'));
        });
    });

    // Small windows start with the sidebar closed; shrinking the window closes it again.
    var phone = w.matchMedia('(max-width: 767.98px)');
    function onPhone(e) { if (e.matches) setToggled(true); }
    onPhone(phone);
    (phone.addEventListener ? phone.addEventListener('change', onPhone) : phone.addListener(onPhone));

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

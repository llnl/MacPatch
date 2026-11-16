(function ($) {
    'use strict';
    var pending;
    var $modal = $('#modalDialog');

    function reset() {
        $modal.find('select').each(function () {
            if (this.selectize) this.selectize.destroy();
        });
        $modal.removeClass('client-group-modal modal-wide modal-mid modal-mid-wide modal-mid-60 modal-mid-70 modal-mid-80');
        $('#modalHeader').removeClass('panel-heading');
        $('#modalContent').removeClass('panel-danger');
        $('#modalBody').empty().removeClass('client-group-dashboard').css({height: '', overflow: ''});
        $('#modalFooter').show();
        $('#modalSaveButton').off('.clientGroupForm').text('Save').show();
        $('#modalCancelButton').text('Cancel').show();
    }

    $modal.on('shown.bs.modal.clientGroup', function () {
        if (!$modal.hasClass('client-group-modal')) return;
        $modal.find('select[data-group-picker]').each(function () {
            if (!this.selectize) $(this).selectize({
                create: false,
                copyClassesToDropdown: false,
                sortField: 'text',
                placeholder: this.dataset.placeholder,
                dropdownParent: 'body',
                dropdownClass: 'selectize-dropdown client-group-picker-dropdown'
            });
            // Bootstrap's fixed-height input styling belongs to the native select,
            // not Selectize's wrapper or its scrollable option list.
            this.selectize.$wrapper.removeClass('form-control');
        });
    }).on('hidden.bs.modal.clientGroup', function () {
        if (pending) { pending.abort(); pending = null; }
        reset();
    });

    window.ClientGroupModals = {
        open: function (options) {
            reset();
            $modal.addClass('client-group-modal');
            if (options.wide) $modal.addClass('modal-wide');
            if (options.danger) {
                $('#modalHeader').addClass('panel-heading');
                $('#modalContent').addClass('panel-danger');
            }
            $('#modalTitle').text(options.title);
            $('#modalBody').html(options.content);
            if (options.dashboard) $('#modalBody').addClass('client-group-dashboard');
            $('#modalFooter').toggle(!!options.footer);
            if (options.footer) {
                $('#modalSaveButton').hide();
                $('#modalCancelButton').text('Close');
            }
            if (options.ready) options.ready($('#modalBody'));
            $modal.modal('show');
        },
        load: function (url, options) {
            if (pending) pending.abort();
            pending = $.get(url).done(function (content) {
                pending = null;
                options.content = content;
                window.ClientGroupModals.open(options);
            }).fail(function (xhr, status) {
                pending = null;
                if (status !== 'abort') alert('Unable to open this client group dialog. Please try again.');
            });
        }
    };
})(jQuery);

/* Adapt the installed Bootstrap 3 X-editable popups to Bootstrap 4. */
(function ($) {
    'use strict';

    var Popover = $.fn.popover && $.fn.popover.Constructor;
    if (!Popover || !/^4\./.test(Popover.VERSION) || !$.fn.editableContainer) {
        return;
    }

    $.extend($.fn.editableContainer.Popup.prototype, {
        defaults: Popover.Default,
        innerCss: '.popover-body',

        tip: function () {
            var popover = this.container();
            return popover ? $(popover.getTipElement()) : null;
        },

        initContainer: function () {
            this.containerOptions = $.extend({}, Popover.Default, this.containerOptions, {
                trigger: 'manual',
                selector: false,
                content: ' ',
                template: Popover.Default.template,
                animation: false
            });
            this.call(this.containerOptions);
        },

        innerDestroy: function () {
            this.call('dispose');
        },

        setContainerOption: function (key, value) {
            this.container().config[key] = value;
        },

        setPosition: function () {
            var popover = this.container();
            if (popover) {
                popover.update();
            }
        }
    });

    $.fn.editableform.buttons =
        '<button type="submit" class="btn btn-primary btn-sm editable-submit" aria-label="Save">' +
        '<i class="fa fa-check" aria-hidden="true"></i></button>' +
        '<button type="button" class="btn btn-default btn-sm editable-cancel" aria-label="Cancel">' +
        '<i class="fa fa-times" aria-hidden="true"></i></button>';
}(jQuery));

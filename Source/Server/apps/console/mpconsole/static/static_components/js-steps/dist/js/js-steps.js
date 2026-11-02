/**
 * JS Steps - JavaScript Wizard Plugin
 * @version 1.0.0
 * @license MIT
 */
(function (factory) {
    typeof define === 'function' && define.amd ? define(factory) :
    factory();
})((function () { 'use strict';

    /**
     * JS Steps - JavaScript Wizard Plugin
     *
     * @version 1.0.0
     * @license MIT
     */


    (function (window, document) {

        // ========================================
        // ENUMS
        // ========================================

        const ContentMode = {
            HTML: 0,
            IFRAME: 1,
            ASYNC: 2
        };

        const Orientation = {
            HORIZONTAL: 0,
            VERTICAL: 1
        };

        const TransitionEffect = {
            NONE: 0,
            FADE: 1,
            SLIDE: 2,
            SLIDE_LEFT: 3
        };

        // ========================================
        // UTILITIES
        // ========================================

        function $(selector, context = document) {
            if (typeof selector === 'string') {
                return Array.from(context.querySelectorAll(selector));
            }
            return selector ? [selector] : [];
        }

        function $1(selector, context = document) {
            if (typeof selector === 'string') {
                return context.querySelector(selector);
            }
            return selector || null;
        }

        function addClass(el, className) {
            el.classList.add(...className.split(' '));
        }

        function removeClass(el, className) {
            el.classList.remove(...className.split(' '));
        }

        function extend(target, ...sources) {
            sources.forEach(source => {
                if (source) {
                    Object.keys(source).forEach(key => {
                        if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
                            target[key] = extend({}, target[key] || {}, source[key]);
                        } else {
                            target[key] = source[key];
                        }
                    });
                }
            });
            return target;
        }

        // ========================================
        // DEFAULTS
        // ========================================

        const defaults = {
            headerTag: 'h1',
            bodyTag: 'div',
            contentContainerTag: 'div',
            actionContainerTag: 'div',
            stepsContainerTag: 'div',
            cssClass: 'wizard',
            clearFixCssClass: 'clearfix',
            stepsOrientation: Orientation.HORIZONTAL,

            // Content
            titleTemplate: '<span class="number">#index#.</span> #title#',
            loadingTemplate: '<span class="spinner"></span> #text#',

            // Transitions
            transitionEffect: TransitionEffect.FADE,
            transitionEffectSpeed: 200,

            // Events
            onStepChanging: () => true,
            onStepChanged: () => { },
            onCanceled: () => { },
            onFinishing: () => true,
            onFinished: () => { },
            onContentLoaded: () => { },
            onInit: () => { },

            // Labels
            labels: {
                cancel: 'Cancel',
                current: 'current step:',
                pagination: 'Pagination',
                finish: 'Finish',
                next: 'Next',
                previous: 'Previous',
                loading: 'Loading ...'
            },

            // Features
            enableAllSteps: false,
            enableKeyNavigation: true,
            enablePagination: true,
            suppressPaginationOnFocus: true,
            enableContentCache: true,
            enableCancelButton: false,
            enableFinishButton: true,
            preloadContent: false,
            showFinishButtonAlways: false,
            forceMoveForward: false,
            saveState: false,
            startIndex: 0,

            // Async
            contentMode: ContentMode.HTML,
            contentURL: ''
        };

        // ========================================
        // STEPS CLASS
        // ========================================

        class Steps {
            constructor(element, options) {
                this.element = element;
                this.options = extend({}, defaults, options);
                this.state = {
                    currentIndex: this.options.startIndex,
                    maxVisitedIndex: this.options.startIndex,
                    currentStep: null,
                    stepCount: 0,
                    transitionElement: null
                };
                this.steps = [];
                this.uniqueId = 'steps-' + Math.random().toString(36).substr(2, 9);

                this._init();
            }

            _init() {
                this._parseSteps();
                this._render();
                this._bindEvents();
                this._loadInitialStep();

                // Fire init event
                if (this.options.onInit) {
                    this.options.onInit.call(this.element, null, this.state.currentIndex);
                }
            }

            _parseSteps() {
                const headers = $(this.options.headerTag, this.element);
                const bodies = $(this.options.bodyTag, this.element);

                this.state.stepCount = Math.min(headers.length, bodies.length);

                console.log('_parseSteps: Found', headers.length, 'headers and', bodies.length, 'bodies');

                for (let i = 0; i < this.state.stepCount; i++) {
                    const content = bodies[i].innerHTML;
                    console.log('Step', i, 'title:', headers[i].textContent.trim());
                    console.log('Step', i, 'content length:', content.length);
                    console.log('Step', i, 'content preview:', content.substring(0, 100));

                    this.steps.push({
                        title: headers[i].textContent.trim(),
                        content: content,
                        contentElement: bodies[i]
                    });
                }

                // Clear original content
                this.element.innerHTML = '';
            }

            _render() {
                const wizard = this.element;
                addClass(wizard, this.options.cssClass);
                addClass(wizard, this.options.clearFixCssClass);

                if (this.options.stepsOrientation === Orientation.VERTICAL) {
                    addClass(wizard, 'vertical');
                }

                // Create steps navigation
                const stepsContainer = document.createElement(this.options.stepsContainerTag);
                addClass(stepsContainer, 'steps');
                stepsContainer.innerHTML = '<ul role="tablist"></ul>';
                wizard.appendChild(stepsContainer);

                const stepsList = $1('ul', stepsContainer);

                this.steps.forEach((step, index) => {
                    const li = document.createElement('li');
                    li.setAttribute('role', 'tab');
                    li.setAttribute('aria-disabled', 'true');
                    addClass(li, 'disabled'); // Add disabled class for styling

                    const link = document.createElement('a');
                    link.href = '#' + this.uniqueId + '-' + index;
                    link.innerHTML = this.options.titleTemplate
                        .replace(/#index#/g, index + 1)
                        .replace(/#title#/g, step.title);

                    li.appendChild(link);
                    stepsList.appendChild(li);
                });

                // Create content container
                const contentContainer = document.createElement(this.options.contentContainerTag);
                addClass(contentContainer, 'content');
                contentContainer.setAttribute('role', 'main');
                wizard.appendChild(contentContainer);

                this.steps.forEach((step, index) => {
                    const section = document.createElement(this.options.bodyTag);
                    section.id = this.uniqueId + '-body-' + index;
                    section.setAttribute('role', 'tabpanel');
                    section.setAttribute('aria-hidden', 'true');
                    addClass(section, 'body');

                    // CRITICAL: Hide all body elements initially - they use position:absolute and stack
                    section.style.display = 'none';

                    section.innerHTML = step.content;
                    console.log('Created body element', index, '- innerHTML length:', section.innerHTML.length);
                    contentContainer.appendChild(section);
                });

                // Create actions container
                const actionsContainer = document.createElement(this.options.actionContainerTag);
                addClass(actionsContainer, 'actions');
                actionsContainer.setAttribute('role', 'navigation');
                wizard.appendChild(actionsContainer);

                const actionsList = document.createElement('ul');
                actionsContainer.appendChild(actionsList);

                // Previous button
                actionsList.innerHTML += `
                <li>
                    <a href="#previous" role="button" aria-disabled="true">
                        ${this.options.labels.previous}
                    </a>
                </li>
            `;

                // Next button
                actionsList.innerHTML += `
                <li>
                    <a href="#next" role="button">
                        ${this.options.labels.next}
                    </a>
                </li>
            `;

                // Finish button
                if (this.options.enableFinishButton) {
                    actionsList.innerHTML += `
                    <li>
                        <a href="#finish" role="button" style="display:none;">
                            ${this.options.labels.finish}
                        </a>
                    </li>
                `;
                }

                // Cancel button
                if (this.options.enableCancelButton) {
                    actionsList.insertAdjacentHTML('afterbegin', `
                    <li class="wizard-cancel">
                        <a href="#cancel" role="button">
                            ${this.options.labels.cancel}
                        </a>
                    </li>
                `);
                }
            }

            _bindEvents() {
                const wizard = this.element;

                // Action buttons
                const actions = $('.actions a', wizard);
                actions.forEach(link => {
                    link.addEventListener('click', (e) => {
                        e.preventDefault();
                        const href = link.getAttribute('href');

                        if (link.getAttribute('aria-disabled') === 'true') {
                            return;
                        }

                        if (href === '#next') {
                            this.next();
                        } else if (href === '#previous') {
                            this.previous();
                        } else if (href === '#finish') {
                            this.finish();
                        } else if (href === '#cancel') {
                            this.cancel();
                        }
                    });
                });

                // Step navigation
                const stepLinks = $('.steps a', wizard);
                stepLinks.forEach((link, index) => {
                    link.addEventListener('click', (e) => {
                        e.preventDefault();
                        if (this.options.enableAllSteps || link.parentElement.getAttribute('aria-disabled') !== 'true') {
                            this.goTo(index);
                        }
                    });
                });

                // Keyboard navigation
                if (this.options.enableKeyNavigation) {
                    wizard.addEventListener('keyup', (e) => {
                        if (this.options.suppressPaginationOnFocus &&
                            e.target.closest('input, textarea, select, [contenteditable="true"], .ace_editor')) {
                            return;
                        }
                        if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
                            e.preventDefault();
                            this.next();
                        } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
                            e.preventDefault();
                            this.previous();
                        }
                    });
                }
            }

            _loadInitialStep() {
                this.goTo(this.state.currentIndex);
            }

            _updateUI() {
                const current = this.state.currentIndex;
                const wizard = this.element;

                // Update step items
                const stepItems = $('.steps li', wizard);
                stepItems.forEach((item, index) => {
                    removeClass(item, 'current done disabled');
                    item.setAttribute('aria-selected', 'false');

                    if (index !== current && index <= this.state.maxVisitedIndex) {
                        addClass(item, 'done');
                        removeClass(item, 'disabled');
                        item.setAttribute('aria-disabled', 'false');
                    } else if (index === current) {
                        addClass(item, 'current');
                        removeClass(item, 'disabled');
                        item.setAttribute('aria-selected', 'true');
                        item.setAttribute('aria-disabled', 'false');
                    } else {
                        addClass(item, 'disabled');
                        item.setAttribute('aria-disabled', 'true');
                    }
                });

                // Update content
                const bodies = $('.content .body', wizard);
                bodies.forEach((body, index) => {
                    body.style.display = index === current ? 'block' : 'none';
                    body.setAttribute('aria-hidden', index === current ? 'false' : 'true');
                });

                // Update buttons
                const prevBtn = $1('.actions a[href="#previous"]', wizard);
                const nextBtn = $1('.actions a[href="#next"]', wizard);
                const finishBtn = $1('.actions a[href="#finish"]', wizard);

                // Previous button
                if (prevBtn) {
                    prevBtn.setAttribute('aria-disabled', current === 0 ? 'true' : 'false');
                    prevBtn.style.display = current === 0 ? 'none' : '';
                }

                // Next/Finish buttons
                const isLastStep = current === this.state.stepCount - 1;

                if (nextBtn) {
                    nextBtn.style.display = isLastStep ? 'none' : '';
                }

                if (finishBtn) {
                    finishBtn.style.display = (isLastStep || this.options.showFinishButtonAlways) ? '' : 'none';
                }
            }

            _transition(fromIndex, toIndex, callback) {
                const wizard = this.element;
                const bodies = $('.content .body', wizard);
                const effect = this.options.transitionEffect;
                const speed = this.options.transitionEffectSpeed;

                const oldBody = bodies[fromIndex];
                const newBody = bodies[toIndex];

                if (!oldBody || !newBody) {
                    if (callback) callback();
                    return;
                }

                // Same step (initial load or no change)
                if (fromIndex === toIndex) {
                    newBody.style.display = 'block';
                    if (callback) callback();
                    return;
                }

                // No transition
                if (effect === TransitionEffect.NONE || speed === 0) {
                    oldBody.style.display = 'none';
                    newBody.style.display = 'block';
                    if (callback) callback();
                    return;
                }

                // Fade transition
                if (effect === TransitionEffect.FADE) {
                    oldBody.style.opacity = '1';
                    newBody.style.opacity = '0';
                    newBody.style.display = 'block';

                    fadeOut(oldBody, speed / 2, () => {
                        oldBody.style.display = 'none';
                        fadeIn(newBody, speed / 2, callback);
                    });
                }
                // Slide transitions
                else {
                    oldBody.style.display = 'none';
                    newBody.style.display = 'block';
                    if (callback) callback();
                }
            }

            // Public methods

            next() {
                if (this.state.currentIndex < this.state.stepCount - 1) {
                    this.goTo(this.state.currentIndex + 1);
                    return true;
                }
                return false;
            }

            previous() {
                if (this.state.currentIndex > 0) {
                    this.goTo(this.state.currentIndex - 1);
                    return true;
                }
                return false;
            }

            goTo(index) {
                if (index < 0 || index >= this.state.stepCount) {
                    return false;
                }

                const oldIndex = this.state.currentIndex;

                // Fire onStepChanging
                if (this.options.onStepChanging) {
                    const canChange = this.options.onStepChanging.call(
                        this.element,
                        null,
                        oldIndex,
                        index
                    );

                    if (!canChange) {
                        return false;
                    }
                }

                // Update state
                this.state.currentIndex = index;
                this.state.maxVisitedIndex = Math.max(this.state.maxVisitedIndex, index);

                // Transition
                this._transition(oldIndex, index, () => {
                    this._updateUI();

                    // Fire onStepChanged
                    if (this.options.onStepChanged) {
                        this.options.onStepChanged.call(
                            this.element,
                            null,
                            index,
                            oldIndex
                        );
                    }
                });

                return true;
            }

            finish() {
                // Fire onFinishing
                if (this.options.onFinishing) {
                    const canFinish = this.options.onFinishing.call(
                        this.element,
                        null,
                        this.state.currentIndex
                    );

                    if (!canFinish) {
                        return false;
                    }
                }

                // Fire onFinished
                if (this.options.onFinished) {
                    this.options.onFinished.call(
                        this.element,
                        null,
                        this.state.currentIndex
                    );
                }

                return true;
            }

            cancel() {
                if (this.options.onCanceled) {
                    this.options.onCanceled.call(this.element, null);
                }
            }

            getCurrentIndex() {
                return this.state.currentIndex;
            }

            getCurrentStep() {
                return this.steps[this.state.currentIndex];
            }

            getStep(index) {
                return this.steps[index];
            }

            destroy() {
                // Remove event listeners
                const actions = $('.actions a', this.element);
                actions.forEach(link => {
                    link.replaceWith(link.cloneNode(true));
                });

                // Remove data
                delete this.element._stepsInstance;

                // Restore original content
                this.element.innerHTML = this.steps.map((step, index) => {
                    return `<${this.options.headerTag}>${step.title}</${this.options.headerTag}>
                        <${this.options.bodyTag}>${step.content}</${this.options.bodyTag}>`;
                }).join('');
            }
        }

        // ========================================
        // ANIMATION HELPERS
        // ========================================

        function fadeIn(element, duration, callback) {
            element.style.opacity = '0';
            element.style.display = 'block';
            const start = performance.now();

            function animate(time) {
                const progress = Math.min((time - start) / duration, 1);
                element.style.opacity = progress.toString();

                if (progress < 1) {
                    requestAnimationFrame(animate);
                } else {
                    element.style.opacity = '';
                    if (callback) callback();
                }
            }

            requestAnimationFrame(animate);
        }

        function fadeOut(element, duration, callback) {
            const start = performance.now();
            const startOpacity = parseFloat(getComputedStyle(element).opacity) || 1;

            function animate(time) {
                const progress = Math.min((time - start) / duration, 1);
                element.style.opacity = (startOpacity * (1 - progress)).toString();

                if (progress < 1) {
                    requestAnimationFrame(animate);
                } else {
                    element.style.display = 'none';
                    element.style.opacity = '';
                    if (callback) callback();
                }
            }

            requestAnimationFrame(animate);
        }

        // ========================================
        // API
        // ========================================

        function jsSteps(selector, options) {
            const element = typeof selector === 'string' ? $1(selector) : selector;

            if (!element) {
                throw new Error('Element not found: ' + selector);
            }

            // Check if already initialized
            if (element._stepsInstance) {
                return element._stepsInstance;
            }

            // Create new instance
            const instance = new Steps(element, options);
            element._stepsInstance = instance;

            return instance;
        }

        // Static properties
        jsSteps.ContentMode = ContentMode;
        jsSteps.Orientation = Orientation;
        jsSteps.TransitionEffect = TransitionEffect;

        // Export
        if (typeof module !== 'undefined' && module.exports) {
            module.exports = jsSteps;
        } else {
            window.Steps = jsSteps;
        }

    })(typeof window !== 'undefined' ? window : undefined, typeof document !== 'undefined' ? document : {});

}));

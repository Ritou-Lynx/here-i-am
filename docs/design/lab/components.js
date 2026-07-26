(function () {
  // ── Screen tab switching ──
  var tabs = document.querySelectorAll('.screen-tab');
  var screens = {
    'life-space': document.getElementById('screen-life-space'),
    'memory-review': document.getElementById('screen-memory-review'),
    'settings': document.getElementById('screen-settings'),
    'health': document.getElementById('screen-health')
  };

  tabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      var target = this.getAttribute('data-screen');
      tabs.forEach(function (t) { t.classList.remove('screen-tab--active'); });
      this.classList.add('screen-tab--active');
      Object.keys(screens).forEach(function (key) {
        if (screens[key]) screens[key].style.display = key === target ? '' : 'none';
      });
    });
  });

  // ── Nav active state on scroll ──
  var navLinks = document.querySelectorAll('.nav-link');
  var sections = document.querySelectorAll('.spec-section');

  function updateNav() {
    var scrollY = window.scrollY + 120;
    var current = '';
    sections.forEach(function (sec) {
      if (sec.offsetTop <= scrollY) current = sec.id;
    });
    navLinks.forEach(function (link) {
      link.classList.toggle('active', link.getAttribute('href') === '#' + current);
    });
  }
  window.addEventListener('scroll', updateNav, { passive: true });
  updateNav();

  // ── Toggle interaction ──
  document.querySelectorAll('.toggle').forEach(function (el) {
    el.addEventListener('click', function () {
      this.classList.toggle('toggle--on');
    });
  });

  // ── Segment control interaction ──
  document.querySelectorAll('.segment-control').forEach(function (ctrl) {
    ctrl.querySelectorAll('.segment-control__item').forEach(function (item) {
      item.addEventListener('click', function () {
        ctrl.querySelectorAll('.segment-control__item').forEach(function (i) {
          i.classList.remove('segment-control__item--active');
        });
        this.classList.add('segment-control__item--active');
      });
    });
  });

  // ── Top bar tab interaction ──
  document.querySelectorAll('.top-bar__tabs').forEach(function (tabsEl) {
    tabsEl.querySelectorAll('.top-bar__tab').forEach(function (tab) {
      tab.addEventListener('click', function () {
        tabsEl.querySelectorAll('.top-bar__tab').forEach(function (t) {
          t.classList.remove('top-bar__tab--active');
        });
        this.classList.add('top-bar__tab--active');
      });
    });
  });
})();

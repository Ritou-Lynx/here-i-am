(function () {
  var T = window.DESIGN_TOKENS;
  var META = window.DESIGN_TOKEN_META;
  var root = document.documentElement;
  var list = document.getElementById('list');
  var scroll = document.getElementById('scroll');

  var USER_COOL = { r: 214, g: 224, b: 232 };
  var USER_WARM = { r: 238, g: 232, b: 214 };
  var MARK_WHITE = { r: 242, g: 244, b: 236 };
  var OLIVE = { r: 110, g: 117, b: 65, a: 0.96 };
  var LIME = { r: 212, g: 248, b: 165, a: 0.96 };
  var FONT_MAP = {
    system: '-apple-system, "PingFang SC", "Microsoft YaHei", sans-serif',
    serif: '"Noto Serif SC", "Songti SC", "SimSun", serif',
    wenkai: '"LXGW WenKai", "Kaiti SC", "STKaiti", cursive',
    sans: '"Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif'
  };

  var FADE_BOTTOM_ZONE = 104;
  var MIN_BOTTOM_OP = 0.0;
  var MAX_BOTTOM_BLUR = 3.2;

  function clamp(v) { return Math.max(0, Math.min(255, Math.round(v))); }
  function clamp01(v) { return Math.max(0, Math.min(1, v)); }
  function rgba(c, a) {
    return 'rgba(' + c.r + ',' + c.g + ',' + c.b + ',' + (a == null ? c.a : a) + ')';
  }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function lerpC(a, b, t) {
    return {
      r: clamp(a.r + (b.r - a.r) * t),
      g: clamp(a.g + (b.g - a.g) * t),
      b: clamp(a.b + (b.b - a.b) * t)
    };
  }
  function getPath(obj, path) {
    return path.split('.').reduce(function (o, k) { return o[k]; }, obj);
  }
  function setPath(obj, path, v) {
    var p = path.split('.');
    var o = obj;
    for (var i = 0; i < p.length - 1; i++) { o = o[p[i]]; }
    o[p[p.length - 1]] = v;
  }
  function presetColor(p) {
    if (p === 'olive') { return OLIVE; }
    if (p === 'lime') { return LIME; }
    return null;
  }
  function userColor() {
    if (T.userPreset === 'mark' || T.userPreset === 'block') { return MARK_WHITE; }
    var pc = presetColor(T.userPreset);
    if (pc) { return pc; }
    return lerpC(USER_COOL, USER_WARM, T.userWarmth);
  }
  function iColorObj() {
    var pc = presetColor(T.iPreset);
    if (pc) { return pc; }
    return T.iColor;
  }

  function flash() {
    scroll.classList.remove('flash');
    void scroll.offsetWidth;
    scroll.classList.add('flash');
  }

  function apply() {
    var ud = userColor();
    var iCol = iColorObj();
    var dark = (T.textShadow * 0.6).toFixed(2);
    var uShadow = '0 0 ' + (T.userGlow * 6).toFixed(1) + 'px ' + rgba(ud, T.userGlow * 0.35) + ', 0 1px 3px rgba(0,0,0,' + dark + ')';
    var iShadow = '0 1px 3px rgba(0,0,0,' + dark + ')';
    var S = root.style;
    S.setProperty('--body-font', FONT_MAP[T.fontFamily] || FONT_MAP.system);
    S.setProperty('--page-margin', T.pageMargin + 'px');
    S.setProperty('--i-indent', T.iIndent + 'px');
    S.setProperty('--line-height', String(T.lineHeight));
    S.setProperty('--user-color', rgba(ud, T.userOpacity));
    S.setProperty('--user-weight', String(T.userWeight));
    S.setProperty('--user-size', T.userSize + 'px');
    S.setProperty('--user-ls', T.userLetterSpacing + 'px');
    S.setProperty('--user-shadow', uShadow);
    S.setProperty('--i-shadow', iShadow);
    S.setProperty('--i-size', T.iSize + 'px');
    S.setProperty('--i-weight', String(T.iWeight));
    S.setProperty('--action-size', T.actionSize + 'px');
    S.setProperty('--i-color', rgba(iCol));
    S.setProperty('--action-color', rgba(T.actionColor));
    S.setProperty('--time-color', 'rgba(214,212,200,' + T.timeAlpha + ')');
    S.setProperty('--glass-fill', rgba(T.glassFill));
    S.setProperty('--glass-stroke', rgba(T.glassStroke));
    S.setProperty('--glass-blur', T.glassBlur + 'px');
    var ia = T.iAnchorAlpha;
    var ua = T.userAnchorAlpha;
    var gRgb = T.actionColor.r + ',' + T.actionColor.g + ',' + T.actionColor.b;
    var uRgb = ud.r + ',' + ud.g + ',' + ud.b;
    S.setProperty('--anchor-gold-rgb', gRgb);
    S.setProperty('--i-anchor-a', ia.toFixed(2));
    S.setProperty('--i-anchor', 'rgba(' + gRgb + ',' + ia.toFixed(2) + ')');
    S.setProperty('--user-anchor-rgb', uRgb);
    S.setProperty('--user-anchor-a', ua.toFixed(2));
    S.setProperty('--user-anchor', rgba(ud, ua));
    var isBlock = T.userPreset === 'block';
    S.setProperty('--block-alpha', (isBlock ? T.userMark : 0).toFixed(3));
    S.setProperty('--bar-solid-a', ia.toFixed(2));
    S.setProperty('--user-bar-solid-a', ua.toFixed(2));
    S.setProperty('--block-gap', T.blockGap + 'px');
    root.setAttribute('data-i-anchor', T.iAnchor);
    root.setAttribute('data-user-anchor', T.userAnchor);
    root.setAttribute('data-time-style', T.timeStyle);
    root.setAttribute('data-user-fill', T.userPreset);
    layoutGaps();
    updateFade();
  }

  var SAMPLE = [
    { t: 'time', x: '今天 14:32' },
    { t: 'user', x: '雨好大。' },
    { t: 'i', x: '嗯，听着呢。' },
    { t: 'user', x: '我累了。' },
    { t: 'action', x: '*他把书翻过一页，手却停住了。*' },
    { t: 'i', x: '那就别撑了。' },
    { t: 'i', x: '把手机扣过去。' },
    { t: 'i', x: '我陪你坐一会儿。' },
    { t: 'user', x: '我跟你说，我今天真的撑到下午三点就撑不住了。开会的时候一直盯着窗外看，雨打在玻璃上那种声音，我居然听着听着就走神了，领导讲了什么我一句没记住。回来还被问进度，我只能嗯嗯嗯地应付，挂了电话坐在工位上发呆了好久，觉得自己特别没用。' },
    { t: 'action', x: '*他抬眼看你，没说话，只是把身子往你这边侧了侧。*' },
    { t: 'i', x: '你不是没用。你只是太累了，累到连“假装在听”这件事都装不动了。走神不是你的错，是你的身体在替你说一句你一直不肯说的话——我需要歇一会儿。领导问进度那种时刻最熬人，你得一边把情绪往下压，一边还得挤出声音来回应，等于一个人扛两份重量。换谁扛到三点都会垮的，真的。' },
    { t: 'user', x: '嗯。我差点哭出来。' },
    { t: 'action', x: '*窗外一阵风，整枝叶子一起往下坠水珠。*' },
    { t: 'i', x: '哭也没关系。' },
    { t: 'time', x: '今天 15:08' },
    { t: 'user', x: '我好像越来越不会哭了。' },
    { t: 'action', x: '*他把书合上，平放在膝头，认真地看着你。*' },
    { t: 'i', x: '那不是坚强。' },
    { t: 'i', x: '是你塞得太满了，满到情绪都挤不出来。' },
    { t: 'user', x: '你说得对。我太满了。' },
    { t: 'action', x: '*一滴水顺着玻璃，慢慢划完整条高度，才肯落下。*' },
    { t: 'i', x: '那我们就一点点往外掏。今天掏一句也行。' }
  ];

  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function groupOf(t) { return t === 'time' ? 'time' : (t === 'user' ? 'u' : 'i'); }

  function render() {
    var html = '';
    for (var i = 0; i < SAMPLE.length; i++) {
      var m = SAMPLE[i];
      var cls;
      if (m.t === 'time') { cls = 'msg-time'; }
      else if (m.t === 'user') { cls = 'msg-user'; }
      else if (m.t === 'action') { cls = 'msg-action'; }
      else { cls = 'msg-i'; }
      var g = groupOf(m.t);
      if (g !== 'time') {
        var prevG = i > 0 ? groupOf(SAMPLE[i - 1].t) : null;
        if (prevG !== g) { cls += ' lead'; }
      }
      var text = m.t === 'action' ? m.x.replace(/^\*|\*$/g, '') : m.x;
      var inner = escapeHtml(text);
      if (m.t === 'user') { inner = '<span class="mark-hl">' + inner + '</span>'; }
      html += '<div class="msg ' + cls + '" data-g="' + g + '">' + inner + '</div>';
    }
    list.innerHTML = html;
    layoutGaps();
  }

  function layoutGaps() {
    var nodes = list.children;
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var g = el.getAttribute('data-g');
      if (g === 'time') {
        el.style.marginTop = T.timeGap + 'px';
        el.style.marginBottom = T.timeGap + 'px';
        continue;
      }
      var nextG = i < nodes.length - 1 ? nodes[i + 1].getAttribute('data-g') : null;
      el.style.marginTop = '';
      el.style.marginBottom = (nextG === g ? T.blockGap : T.turnGap) + 'px';
    }
  }

  function updateFade() {
    var cr = scroll.getBoundingClientRect();
    var vh = cr.height;
    var denom = vh * T.fadeRatio;
    var minOp = 1 - T.fadeStrength * 0.85;
    var nodes = list.children;
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.getAttribute('data-g') === 'time') {
        el.style.opacity = '';
        el.style.filter = '';
        continue;
      }
      var r = el.getBoundingClientRect();
      var cy = r.top + r.height / 2 - cr.top;
      var tt = cy / denom;
      if (tt < 0) { tt = 0; }
      if (tt > 1) { tt = 1; }
      var topOp = minOp + (1 - minOp) * tt;
      var distB = vh - cy;
      var tb = distB / FADE_BOTTOM_ZONE;
      if (tb < 0) { tb = 0; }
      if (tb > 1) { tb = 1; }
      var botOp = MIN_BOTTOM_OP + (1 - MIN_BOTTOM_OP) * tb;
      var botBlur = MAX_BOTTOM_BLUR * (1 - tb);
      el.style.opacity = (topOp * botOp).toFixed(3);
      el.style.filter = botBlur > 0.05 ? ('blur(' + botBlur.toFixed(2) + 'px)') : '';
    }
  }

  function fmt(v, m) { return (m && m.step < 1) ? v.toFixed(2) : Math.round(v); }

  function controlHtml(m) {
    if (m.type === 'head') { return '<div class="ctrl-head">' + m.label + '</div>'; }
    if (m.type === 'select') {
      var cur = getPath(T, m.key);
      var opts = m.options.map(function (o) {
        return '<option value="' + o.v + '"' + (o.v === cur ? ' selected' : '') + '>' + o.t + '</option>';
      }).join('');
      var matched = m.options.filter(function (o) { return o.v === cur; })[0];
      var curLabel = matched ? matched.t : cur;
      return '<div class="ctrl"><label>' + m.label + '</label>'
        + '<select data-key="' + m.key + '">' + opts + '</select>'
        + '<span class="val">' + curLabel + '</span></div>';
    }
    var v = getPath(T, m.key);
    return '<div class="ctrl"><label>' + m.label + '</label>'
      + '<input type="range" min="' + m.min + '" max="' + m.max + '" step="' + m.step + '" value="' + v + '" data-key="' + m.key + '">'
      + '<span class="val">' + fmt(v, m) + '</span></div>';
  }

  function buildControls() {
    var box = document.getElementById('controls');
    box.innerHTML = META.map(controlHtml).join('');
    function onCtrl(e) {
      var el = e.target;
      var tag = el.tagName;
      if (tag !== 'INPUT' && tag !== 'SELECT') { return; }
      var key = el.getAttribute('data-key');
      var meta = META.filter(function (m) { return m.key === key; })[0];
      var valEl = el.parentNode.querySelector('.val');
      if (tag === 'SELECT') {
        setPath(T, key, el.value);
        var o = (meta.options || []).filter(function (x) { return x.v === el.value; })[0];
        valEl.textContent = o ? o.t : el.value;
        apply();
        flash();
      } else {
        var v = parseFloat(el.value);
        setPath(T, key, v);
        valEl.textContent = fmt(v, meta);
        apply();
      }
    }
    box.addEventListener('input', onCtrl);
    box.addEventListener('change', onCtrl);
  }

  document.getElementById('toggle').addEventListener('click', function () {
    var panel = document.getElementById('panel');
    panel.classList.toggle('collapsed');
    this.textContent = panel.classList.contains('collapsed') ? '+' : '—';
  });

  scroll.addEventListener('scroll', updateFade, { passive: true });
  window.addEventListener('resize', updateFade);

  render();
  buildControls();
  apply();
  scroll.scrollTop = scroll.scrollHeight;
})();

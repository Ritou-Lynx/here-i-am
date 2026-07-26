window.DESIGN_TOKENS = {
  pageMargin: 22,
  iIndent: 21,
  lineHeight: 1.52,
  blockGap: 6,
  turnGap: 20,
  timeGap: 27,
  timeStyle: 'line',
  timeAlpha: 0.80,
  fontFamily: 'wenkai',
  iAnchor: 'bar',
  iAnchorAlpha: 0.05,
  userAnchor: 'none',
  userAnchorAlpha: 0.26,
  userPreset: 'moss',
  userWarmth: 0.34,
  userOpacity: 0.92,
  userGlow: 0.3,
  userMark: 1.0,
  userWeight: 600,
  userSize: 16,
  userLetterSpacing: 0.3,
  iPreset: 'ivory',
  iSize: 17,
  iWeight: 500,
  actionSize: 14.5,
  iColor: { r: 245, g: 238, b: 224, a: 0.96 },
  actionColor: { r: 242, g: 202, b: 112, a: 1.0 },
  glassFill: { r: 255, g: 255, b: 255, a: 0.06 },
  glassStroke: { r: 255, g: 255, b: 255, a: 0.18 },
  glassBlur: 2,
  fadeStrength: 0.45,
  fadeRatio: 0.45,
  textShadow: 0.5,
  imgMaxW: 72,
  imgRadius: 12,
  linkBarAlpha: 0.5,
  justify: 'on'
};

window.DESIGN_TOKEN_META = [
  { type: 'head', label: '正文字体' },
  { key: 'fontFamily', label: '字体', type: 'select', options: [
    { v: 'serif', t: '思源宋体' }, { v: 'wenkai', t: '霞鹜文楷' }, { v: 'sans', t: '思源黑体' }, { v: 'system', t: '系统黑' }
  ] },
  { type: 'head', label: '布局' },
  { key: 'pageMargin', label: '页面边距', min: 14, max: 40, step: 1 },
  { key: 'iIndent', label: 'i 缩进', min: 0, max: 48, step: 1 },
  { key: 'lineHeight', label: '行高', min: 1.2, max: 2.0, step: 0.02 },
  { type: 'head', label: '节奏（治字墙）' },
  { key: 'blockGap', label: '同块内距', min: 0, max: 18, step: 1 },
  { key: 'turnGap', label: '换人距', min: 8, max: 44, step: 1 },
  { key: 'timeGap', label: '跨时间距', min: 16, max: 72, step: 1 },
  { type: 'head', label: '时间标' },
  { key: 'timeStyle', label: '时间样式', type: 'select', options: [
    { v: 'text', t: '纯文字' }, { v: 'line', t: '两端细线' }, { v: 'ornament', t: '花饰' }
  ] },
  { key: 'timeAlpha', label: '时间清晰', min: 0.3, max: 1, step: 0.02 },
  { type: 'head', label: '对话引导标识（默认关）' },
  { key: 'iAnchor', label: 'i 锚点', type: 'select', options: [
    { v: 'none', t: '无' }, { v: 'dash', t: '破折号' }, { v: 'dot', t: '圆点' }, { v: 'bar', t: '竖线' }
  ] },
  { key: 'iAnchorAlpha', label: 'i 锚浓度', min: 0.05, max: 0.7, step: 0.02 },
  { key: 'userAnchor', label: 'user 锚点', type: 'select', options: [
    { v: 'none', t: '无' }, { v: 'dash', t: '破折号' }, { v: 'dot', t: '圆点' }, { v: 'bar', t: '竖线' }
  ] },
  { key: 'userAnchorAlpha', label: 'user 锚浓度', min: 0.05, max: 0.7, step: 0.02 },
  { type: 'head', label: '用户字色 / 衬底 / 高亮' },
  { key: 'userPreset', label: '用户字色', type: 'select', options: [
    { v: 'temp', t: '窗光白（滑块）' }, { v: 'moss', t: '苔绿 #a3a866' }, { v: 'olive', t: '橄榄字 #6e7541' }, { v: 'lime', t: '嫩黄绿 #d4f8a5' }, { v: 'mark', t: '马克笔高亮（逐行·白字）' }, { v: 'block', t: '整块衬底（白字）' }
  ] },
  { key: 'userMark', label: '高亮 / 衬底浓度', min: 0, max: 1, step: 0.05 },
  { key: 'userWarmth', label: '冷白↔暖白', min: 0, max: 1, step: 0.02 },
  { key: 'userOpacity', label: '用户虚实', min: 0.3, max: 1, step: 0.02 },
  { key: 'userGlow', label: '窗光漫射', min: 0, max: 1, step: 0.05 },
  { key: 'userWeight', label: '用户字重', min: 300, max: 600, step: 50 },
  { key: 'userSize', label: '用户字号', min: 12, max: 22, step: 0.5 },
  { key: 'userLetterSpacing', label: '用户字距', min: 0, max: 3, step: 0.1 },
  { type: 'head', label: 'i 字色与动作' },
  { key: 'iPreset', label: 'i 字色', type: 'select', options: [
    { v: 'ivory', t: '暖象牙' }, { v: 'olive', t: '橄榄 #6e7541' }, { v: 'lime', t: '嫩黄绿 #d4f8a5' }
  ] },
  { key: 'iSize', label: 'i 字号', min: 12, max: 24, step: 0.5 },
  { key: 'iWeight', label: 'i 字重', min: 400, max: 700, step: 50 },
  { key: 'actionSize', label: '动作字号', min: 11, max: 20, step: 0.5 },
  { key: 'actionColor.a', label: '动作透明', min: 0.2, max: 1, step: 0.02 },
  { type: 'head', label: '玻璃输入条' },
  { key: 'glassBlur', label: '玻璃模糊', min: 0, max: 40, step: 1 },
  { key: 'glassFill.a', label: '玻璃浓度', min: 0, max: 0.4, step: 0.01 },
  { type: 'head', label: '淡出与描影' },
  { key: 'fadeStrength', label: '淡出强度', min: 0, max: 1, step: 0.05 },
  { key: 'fadeRatio', label: '淡出位置', min: 0.2, max: 0.9, step: 0.05 },
  { key: 'textShadow', label: '文字描影', min: 0, max: 1, step: 0.05 },
  { type: 'head', label: '多模态（钉入）' },
  { key: 'imgMaxW', label: '单图宽度%', min: 40, max: 100, step: 1 },
  { key: 'imgRadius', label: '图片圆角', min: 0, max: 24, step: 1 },
  { key: 'linkBarAlpha', label: '链接钉线浓度', min: 0.05, max: 1, step: 0.05 },
  { key: 'justify', label: '长文两端对齐', type: 'select', options: [
    { v: 'off', t: '关' }, { v: 'on', t: '开' }
  ] }
];

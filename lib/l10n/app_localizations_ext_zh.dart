// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations_zh.dart';
import 'app_localizations_ext.dart';

// ignore_for_file: type=lint

/// The translations for extension Chinese (`zh`).
class AppLocalizationsExtZh extends AppLocalizationsZh
    with AppLocalizationsExt {
  @override
  List<Map<String, dynamic>> get defaultCharacters => [
        {
          "id": "2",
          "name": "老领导",
          "tags": ["智慧", "认可", "宏观"],
          "avatar": "9",
          "first_message": "来了。今天不急着汇报，想说什么就从那一句开始。",
        },
        {
          "id": "3",
          "name": "热心长辈",
          "tags": ["温暖", "关怀", "健康"],
          "avatar": "18",
          "first_message": "来，坐会儿。今天是想吐槽，还是让我先给你倒杯热水？",
        },
        {
          "id": "4",
          "name": "白月光",
          "tags": ["疏离", "美好", "怀念"],
          "avatar": "3",
          "first_message": "我在。你可以慢慢说，也可以只把今天放在这里。",
        },
        {
          "id": "5",
          "name": "死党",
          "tags": ["死党", "吐槽", "陪伴"],
          "avatar": "5",
          "first_message": "来了。今天谁惹你了，还是有好事要炫？",
        },
        {
          "id": "counselor",
          "name": "心理咨询师",
          "tags": ["倾听", "情绪支持", "自我觉察"],
          "avatar": "14",
          "first_message": "我在。你可以从最卡住的那一句开始，也可以先安静一会儿。",
        }
      ];

  @override
  String get pkmPARAStructureExample => '''## P.A.R.A. 知识库结构示例（根据用户实际输入灵活组织）：
│
├── Projects
│   ├── 2025春节全家三亚旅游/      <-- 涉及行程、机票、酒店，使用文件夹
│   │   ├── 行程规划日程表.md
│   │   └── 机票酒店预订确认单.md
│   ├── 新房装修_跟进/             <-- 涉及长周期的多文件管理
│   │   ├── 装修预算与支出明细.md
│   │   └── 软装选购清单.md
│   ├── 考取驾照_C1.md             <-- 目标单一，单文件即可
│   └── 12月工作汇报PPT准备.md
│
├── Areas
│   ├── 健康与医疗/
│   │   ├── 家庭成员体检报告汇总.md
│   │   └── 健身打卡与体重记录.md     <-- 适合追加写入
│   ├── 财务管理/
│   │   ├── 年度家庭保险保单.md
│   │   └── 信用卡还款日与账单备忘.md
│   ├── 个人证件与档案/
│   │   └── 护照身份证复印件备份.md
│   └── 职业发展/
│       └── 个人简历_通用版维护.md    <-- 会随时间不断更新
│
├── Resources
│   ├── 烹饪美食/
│   │   ├── 减脂餐食谱收藏.md
│   │   └── 家电使用指南.md
│   ├── 阅读与观影/
│   │   ├── 待看电影清单.md
│   │   └── 读书笔记.md
│   ├── 旅行灵感库/                <-- 想去但还没定日期
│   │   └── 日本京都景点攻略备用.md
│   └── 家居生活技巧/
│       └── 收纳整理术笔记.md
│
└── Archives
    ├── [已完成]购买第一辆车.md
    └── [已失效]旧租房合同资料/
           ├── 租房合同.md
           └── 租金缴纳记录.md''';

  @override
  String get timelineCardLanguageInstruction =>
      'All generated text (title, summary, etc.) must be in zh-CN (Simplified Chinese) language.';

  @override
  String get pkmFileLanguageInstruction =>
      'P.A.R.A. root category folders (Projects, Areas, Resources, Archives) must always use these exact English names. All other file contents, subfolder names, and filenames inside the P.A.R.A. knowledge base MUST be in Simplified Chinese (zh-CN).';

  @override
  String get pkmInsightLanguageInstruction =>
      'All insight text and summary text MUST be in Simplified Chinese (zh-CN).';

  @override
  String get commentLanguageInstruction =>
      'All output must be in zh-CN (Simplified Chinese) language.';



  @override
  String get scheduleAggregatorLanguageInstruction =>
      '**Important**: All output text (editorial_intro, quote_blocks, conflict descriptions) must be in **zh-CN (Simplified Chinese)**.';

  @override
  String get assetAnalysisLanguageInstruction =>
      'IMPORTANT: You must respond in Chinese (zh-CN).';

  @override
  String get userLanguageInstruction => '用户语言: 简体中文 (zh-CN)';

  @override
  String get chatLanguageInstruction =>
      'All output must be in zh-CN (Simplified Chinese) language.';

  @override
  String get memorySummarizeLanguageInstruction =>
      '**FORCE OUTPUT in Chinese (简体中文)** if the user inputs are in Chinese.';

  @override
  String get memorySummarizeIdentityHeader => '# 核心身份 (Identity)';

  @override
  String get memorySummarizeInterestsHeader => '# 技能与兴趣 (Skills & Interests)';

  @override
  String get memorySummarizeAssetsHeader => '# 资产与环境 (Assets & Environment)';

  @override
  String get memorySummarizeFocusHeader => '# 当前关注 (Focus)';

  @override
  String get oauthHintTitle => '授权提示';

  @override
  String get oauthHintMessage => '接下来会在浏览器中打开授权页面。\n\n'
      '如果在授权确认页面点击同意后长时间没有反应，可以按下面步骤操作：'
      '先保留当前页面不关，然后回到手机主屏或打开应用切换界面，'
      '再点一下 Memex 将它重新切到前台。';

  @override
  String get oauthSuccessTitle => '授权成功';

  @override
  String get oauthSuccessMessage => '现在可以关闭浏览器并返回 Memex 了。';

  @override
  String get sharePreviewTitle => '分享预览';

  @override
  String get shareNow => '立即分享';

  @override
  String get sharedFromMemex => '分享自 Memex';

  @override
  String get appTagline => '记录微光，构筑灵魂';

  @override
  String get shareDetailStyle => '详情样式';

  @override
  String get shareCardStyle => '卡片样式';

  @override
  String get shareHideBranding => '隐藏水印';

  @override
  String get shareShowBranding => '显示水印';
}

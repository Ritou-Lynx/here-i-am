/// Conservative local gate for Project Memory candidate generation.
library;

class ProjectMemoryIntentClassifier {
  const ProjectMemoryIntentClassifier._();

  static const _strongTerms = <String>[
    '项目',
    'project',
    'dev room',
    'devroom',
    'codex',
    'claude code',
    'hermes',
    '代码',
    '开发',
    '分支',
    'commit',
    '提交',
    'pull request',
    '论文',
    '投稿',
    'ui搭建',
    'ui 搭建',
    '界面搭建',
  ];

  static const _progressTerms = <String>[
    '进度',
    '做到哪',
    '做了什么',
    '下一步',
    '待办',
    '决策',
    '收工',
    '交接',
  ];

  static bool isProjectIntent(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (_strongTerms.any(normalized.contains)) return true;

    // Progress words alone are ordinary life/task language. Require an
    // engineering/work noun before opening the project lane.
    const workNouns = ['功能', '模块', '产品', 'app', '仓库', '文档', '研究', '写作'];
    return _progressTerms.any(normalized.contains) &&
        workNouns.any(normalized.contains);
  }
}

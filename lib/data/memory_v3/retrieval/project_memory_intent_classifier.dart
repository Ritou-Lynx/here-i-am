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
    '记得什么项目',
    '知道什么项目',
    '工作进展',
    'here i am',
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
    '记得',
    '知道',
    '忙什么',
    '在搞',
  ];

  static bool isProjectIntent(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (_strongTerms.any(normalized.contains)) return true;

    const workNouns = [
      '功能', '模块', '产品', 'app', '仓库', '文档', '研究', '写作', '项目',
    ];
    return _progressTerms.any(normalized.contains) &&
        workNouns.any(normalized.contains);
  }
}

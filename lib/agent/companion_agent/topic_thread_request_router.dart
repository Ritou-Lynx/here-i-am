/// Pure intent routing helpers for Topic Thread write-back commands.
library;

class TopicThreadRequestRouter {
  TopicThreadRequestRouter._();

  static final List<RegExp> _appendRequestPatterns = [
    RegExp(r'(整理|总结|归纳|并入|合并|加入|加进|补进|记到|放到).{0,12}(这个|刚才|原来|之前|已有|话题|线索)'),
    RegExp(r'(这个|刚才|原来|之前|已有|话题|线索).{0,12}(整理|总结|归纳|并入|合并|加入|加进|补进|记到|放到)'),
  ];

  static bool isAppendRequest(String text) =>
      _appendRequestPatterns.any((pattern) => pattern.hasMatch(text));
}

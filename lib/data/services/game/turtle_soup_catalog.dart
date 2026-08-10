import 'dart:math';

/// One immutable built-in lateral-thinking puzzle.
///
/// The surface is shown to the player while the solution stays inside the
/// game definition snapshot for the isolated GameAgent referee.
class TurtleSoupPuzzle {
  const TurtleSoupPuzzle({
    required this.id,
    required this.title,
    required this.surface,
    required this.solution,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String surface;
  final String solution;
  final String difficulty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'surface': surface,
        'solution': solution,
        'difficulty': difficulty,
      };

  factory TurtleSoupPuzzle.fromJson(Map<String, dynamic> json) =>
      TurtleSoupPuzzle(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '未命名汤面',
        surface: json['surface']?.toString() ?? '',
        solution: json['solution']?.toString() ?? '',
        difficulty: json['difficulty']?.toString() ?? '普通',
      );
}

/// Curated puzzles keep the soup surface and canonical answer stable across
/// app restarts. More sources (including model-generated soups) can be added
/// later without changing the session format.
abstract final class TurtleSoupCatalog {
  TurtleSoupCatalog._();

  static const puzzles = <TurtleSoupPuzzle>[
    TurtleSoupPuzzle(
      id: 'light_at_sea',
      title: '熄灭的灯',
      surface: '一个男人关掉一盏灯后就去睡觉了。第二天醒来，他得知许多人死了，于是崩溃大哭。为什么？',
      solution:
          '男人是灯塔看守员。他误把灯塔的导航灯关掉，夜间航行的船失去指引后触礁，造成多人死亡。',
      difficulty: '普通',
    ),
    TurtleSoupPuzzle(
      id: 'desert_match',
      title: '半截火柴',
      surface: '一个人死在沙漠里，手中紧握着半截火柴，周围没有脚印。他是怎么死的？',
      solution:
          '他和同伴乘坐的热气球即将坠毁。大家抽火柴决定谁跳下去减轻重量，他抽中了较短的那根，于是从空中跳下，周围自然没有脚印。',
      difficulty: '经典',
    ),
    TurtleSoupPuzzle(
      id: 'elevator_rain',
      title: '停在七楼',
      surface: '一个人住在十楼。晴天回家时他只坐电梯到七楼，再走楼梯上去；雨天却会直接坐到十楼。为什么？',
      solution:
          '他个子较矮，平时只能按到七楼按钮；雨天带着长伞，可以用伞尖按到十楼。',
      difficulty: '入门',
    ),
    TurtleSoupPuzzle(
      id: 'field_package',
      title: '没有打开的包裹',
      surface: '一个人躺在空旷的田野里，身旁有一个没有打开的包裹。现场没有其他人，他为什么死了？',
      solution: '那个包裹是他的降落伞。降落伞没有打开，他从高空坠落身亡。',
      difficulty: '入门',
    ),
    TurtleSoupPuzzle(
      id: 'locked_room_puddle',
      title: '房间里的水',
      surface: '一名男子被发现吊在反锁的空房间里，脚下只有一摊水，房间里没有可以垫脚的家具。发生了什么？',
      solution: '他站在一大块冰上完成上吊。之后冰融化，只在脚下留下了一摊水。',
      difficulty: '普通',
    ),
    TurtleSoupPuzzle(
      id: 'train_tunnel',
      title: '窗外的黑暗',
      surface: '一个人乘火车穿过隧道时突然自杀了。在进隧道前，他还非常开心。为什么？',
      solution:
          '他曾经失明，刚做完手术恢复视力，开心地坐火车回家。进入隧道后四周突然变黑，他误以为自己再次永久失明，绝望之下自杀。',
      difficulty: '困难',
    ),
  ];

  static TurtleSoupPuzzle pick({
    Iterable<String> excludingIds = const [],
    Random? random,
  }) {
    final excluded = excludingIds.toSet();
    final candidates = puzzles.where((p) => !excluded.contains(p.id)).toList();
    final pool = candidates.isEmpty ? puzzles : candidates;
    return pool[(random ?? Random()).nextInt(pool.length)];
  }
}

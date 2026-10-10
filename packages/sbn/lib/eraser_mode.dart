/// 橡皮擦的工作方式。
enum EraserMode(
  /// 序列化用的名字。别直接展示给用户。
  final String name,
) {
  /// 笔迹模式：碰到哪条笔迹，就把整条删掉（原来的行为）。
  stroke('stroke'),

  /// 圆形擦子：只擦掉圆形范围内的那一部分笔迹。
  circle('circle'),

  /// 方形擦子：只擦掉方形范围内的那一部分笔迹。
  square('square');

  /// 从序列化名字还原，认不出来就退回默认值。
  static EraserMode fromName(String? name) => EraserMode.values
      .firstWhere((mode) => mode.name == name, orElse: () => stroke);
}

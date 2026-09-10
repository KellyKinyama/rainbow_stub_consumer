/// Live presence snapshot for a peer.
class Presence {
  const Presence({required this.show, this.status});

  final String show;
  final String? status;

  Presence copyWith({String? show, String? status}) =>
      Presence(show: show ?? this.show, status: status ?? this.status);

  @override
  bool operator ==(Object other) =>
      other is Presence && other.show == show && other.status == status;

  @override
  int get hashCode => Object.hash(show, status);
}

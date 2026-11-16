// Watch-wear tracker models. Wear metadata syncs; photos never do — the
// watch *photo* files live in the app documents directory and their paths
// are kept in a separate local-only store (see state/watch_photo_store.dart).

/// A watch in the collection.
class Watch {
  Watch({
    required this.id,
    required this.brand,
    required this.model,
    this.nickname = '',
    this.reference = '',
    this.movement = '',
    this.caseSizeMm,
    this.color = 'cyan',
    this.notes = '',
    this.status = statusOwned,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const String statusOwned = 'owned';
  static const String statusRepair = 'repair';
  static const String statusSold = 'sold';
  static const String statusWishlist = 'wishlist';

  final String id;
  final String brand;
  final String model;
  final String nickname;
  final String reference;
  final String movement;

  /// Case diameter, millimetres.
  final double? caseSizeMm;
  final String color;
  final String notes;
  final String status;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  /// In the collection right now (owned or away for service).
  bool get owned => !archived && (status == statusOwned || status == statusRepair);

  String get displayName {
    final nick = nickname.trim();
    if (nick.isNotEmpty) return nick;
    final full = '$brand $model'.trim();
    return full.isEmpty ? 'watch' : full;
  }

  Watch copyWith({
    String? brand,
    String? model,
    String? nickname,
    String? reference,
    String? movement,
    double? caseSizeMm,
    bool clearCaseSizeMm = false,
    String? color,
    String? notes,
    String? status,
    bool? archived,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      Watch(
        id: id,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        nickname: nickname ?? this.nickname,
        reference: reference ?? this.reference,
        movement: movement ?? this.movement,
        caseSizeMm: clearCaseSizeMm ? null : (caseSizeMm ?? this.caseSizeMm),
        color: color ?? this.color,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'model': model,
        'nickname': nickname,
        'reference': reference,
        'movement': movement,
        'caseSizeMm': caseSizeMm,
        'color': color,
        'notes': notes,
        'status': status,
        'archived': archived,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory Watch.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return Watch(
      id: json['id']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      movement: json['movement']?.toString() ?? '',
      caseSizeMm: (json['caseSizeMm'] as num?)?.toDouble(),
      color: json['color']?.toString() ?? 'cyan',
      notes: json['notes']?.toString() ?? '',
      status: json['status']?.toString() ?? statusOwned,
      archived: json['archived'] == true,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}

/// Which watch was worn on which day. The optional wrist photo is NOT part of
/// this record — it lives in the local-only photo store.
class WearLog {
  WearLog({
    required this.id,
    required this.watchId,
    required this.day,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String watchId;

  /// Epoch day.
  final int day;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'watchId': watchId,
        'day': day,
        'date': _dateKey(day), // readability only
        'note': note,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  static String _dateKey(int day) {
    final d = DateTime(1970, 1, 1).add(Duration(days: day));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  factory WearLog.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    var day = (json['day'] as num?)?.toInt();
    if (day == null && json['date'] != null) {
      final d = DateTime.tryParse(json['date'].toString());
      if (d != null) day = DateTime(d.year, d.month, d.day).difference(DateTime(1970, 1, 1)).inDays;
    }
    return WearLog(
      id: json['id']?.toString() ?? '',
      watchId: json['watchId']?.toString() ?? '',
      day: day ?? 0,
      note: json['note']?.toString() ?? '',
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}

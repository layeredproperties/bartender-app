enum Role { bartender, barback }

/// A roster entry.
///
/// Immutable: the tip-out is keyed by name and the same instances are
/// held by the app-wide roster and by whichever screen is on top, so
/// screens swap entries with [copyWith] rather than flipping fields on
/// an object someone else is reading.
class Person {
  final String name;
  final Role role;
  final bool isSelected;
  final bool isUser;

  const Person({
    required this.name,
    required this.role,
    this.isSelected = false,
    this.isUser = false,
  });

  Person copyWith({
    String? name,
    Role? role,
    bool? isSelected,
    bool? isUser,
  }) {
    return Person(
      name: name ?? this.name,
      role: role ?? this.role,
      isSelected: isSelected ?? this.isSelected,
      isUser: isUser ?? this.isUser,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role.name,
        'isSelected': isSelected,
        'isUser': isUser,
      };

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      name: json['name'] as String? ?? '',
      role: Role.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => Role.bartender,
      ),
      isSelected: json['isSelected'] as bool? ?? false,
      isUser: json['isUser'] as bool? ?? false,
    );
  }
}

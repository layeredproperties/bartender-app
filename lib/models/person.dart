enum Role { bartender, barback }

class Person {
  final String name;
  final Role role;
  bool isSelected;
  final bool isUser;

  Person({
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

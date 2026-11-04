class Channel {
  const Channel({
    required this.name,
    required this.url,
    this.tvgId,
    this.logo,
    this.group,
  });

  final String name;
  final String url;
  final String? tvgId;
  final String? logo;
  final String? group;
}

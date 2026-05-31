String teamIdFromName(String? teamName) {
  if (teamName == null || teamName.isEmpty) return 'unknown';
  return teamName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

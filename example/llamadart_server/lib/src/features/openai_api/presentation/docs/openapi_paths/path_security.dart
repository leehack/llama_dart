List<Map<String, List<String>>> operationSecurity(bool apiKeyEnabled) {
  if (!apiKeyEnabled) {
    return const <Map<String, List<String>>>[];
  }

  return <Map<String, List<String>>>[
    <String, List<String>>{'bearerAuth': <String>[]},
  ];
}

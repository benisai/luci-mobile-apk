String formatWifiBand(String band) {
  switch (band.toLowerCase()) {
    case '2g':
    case '2.4g':
      return '2.4 GHz';
    case '5g':
      return '5 GHz';
    case '6g':
      return '6 GHz';
    default:
      return '';
  }
}

String? normalizeWifiChannel(Object? value) {
  final channel = value?.toString().trim() ?? '';
  if (channel.isEmpty ||
      const {
        '0',
        'auto',
        'n/a',
        'na',
        'unknown',
        '--',
      }.contains(channel.toLowerCase())) {
    return null;
  }
  return channel;
}

String resolveWifiChannel({Object? actual, Object? configured}) {
  return normalizeWifiChannel(actual) ??
      normalizeWifiChannel(configured) ??
      'N/A';
}

String uciString(Object? value, [String fallback = '']) {
  if (value is List) return value.isEmpty ? fallback : value.first.toString();
  return value?.toString() ?? fallback;
}

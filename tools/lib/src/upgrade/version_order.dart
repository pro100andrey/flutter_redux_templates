/// Orders two `x.y.z[-pre]` versions: negative, zero or positive, like any
/// comparator.
///
/// Enough semver to answer "is this newer", and no more: the numeric triple
/// compared component-wise, and a build carrying a `-suffix` ranked below the
/// same triple without one, because that is what a prerelease is. A component
/// that is not a number sorts as 0 rather than throwing — a version string frx
/// cannot parse should not stop an upgrade from being *reported*, and the
/// install is gated on the checksum either way.
int compareVersions(String a, String b) {
  final (left, leftPre) = _parse(a);
  final (right, rightPre) = _parse(b);
  for (var i = 0; i < 3; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) {
      return l.compareTo(r);
    }
  }
  if (leftPre == rightPre) {
    return 0;
  }
  return leftPre ? -1 : 1;
}

/// The numeric components of [v], and whether it carries a prerelease suffix.
(List<int>, bool) _parse(String v) {
  final dash = v.indexOf('-');
  final core = dash < 0 ? v : v.substring(0, dash);
  return (
    [for (final part in core.split('.')) int.tryParse(part) ?? 0],
    dash >= 0,
  );
}

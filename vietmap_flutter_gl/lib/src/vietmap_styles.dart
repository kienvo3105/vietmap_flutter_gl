part of '../vietmap_flutter_gl.dart';

// @Deprecated('MaplibreStyles was renamed to MapLibreStyles.')
// typedef MaplibreStyles = VietmapStyles;

/// VietmapGL styles used mostly for demonstration.
abstract class VietmapStyles {
  /// A very simple VietmapGL demo style that shows only countries with their
  /// boundaries.
  static const String demo = "https://maps.vietmap.vn/maps/styles/tm/style.json?apikey=YOUR_TILEMAP_KEY";
}

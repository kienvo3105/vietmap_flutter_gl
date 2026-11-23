part of '../vietmap_flutter_gl.dart';

class UserLocationLayer extends StatefulWidget {
  /// The icon that will be used to represent the user's location on the map.
  final Widget? locationIcon;

  /// The icon that will be used to represent the user's bearing on the map.
  final Widget? bearingIcon;
  final Color pulseColor;
  final double pulseOpacity;

  /// The controller of the map.
  final VietmapController mapController;

  /// Set this value to true to ignore pointer events on the markers.
  /// If you using a marker like a button and have a [GestureDetector] inside it,
  /// set this value to false to prevent the map from receiving the gesture.
  final bool? ignorePointer;

  /// The size of the icon that will be used to represent the user's location on the map.
  /// This will apply for icon only, not for pulse size.
  final double iconSize;

  /// The markers to be placed on the map.
  /// use [UserLocationLayer] inside a [Stack], that contain [VietmapGL] and [UserLocationLayer] to work properly
  /// [VietmapGL.trackCameraPosition] must be set to true to work properly
  const UserLocationLayer(
      {super.key,
      this.locationIcon,
      this.bearingIcon,
      required this.mapController,
      this.ignorePointer,
      this.pulseOpacity = 0.3,
      this.iconSize = 50,
      this.pulseColor = Colors.blue});

  @override
  State<UserLocationLayer> createState() => _UserLocationLayerState();
}

class _UserLocationLayerState extends State<UserLocationLayer> {
  /// How often the initial position is polled before giving up.
  ///
  /// The controller reaches Dart as soon as the platform view exists, which is
  /// well before the style finishes loading and the native location component
  /// is built, so the first attempts legitimately return null.
  static const _initialLocationAttempts = 12;
  static const _initialLocationRetryDelay = Duration(milliseconds: 500);

  /// How long to wait for the map to report a camera event before projecting
  /// anyway. Only reached by maps that never move (no tracking mode, no
  /// gesture); everything else settles well inside this.
  static const _settleFallback = Duration(milliseconds: 1500);

  VietmapController get _mapController => widget.mapController;
  MarkerState? _positionMarkerStates;
  UserLocation? _currentPosition;

  /// Set once a position from the device has been received. Until then nothing
  /// is drawn - showing the marker at the camera target would put the "you are
  /// here" dot at a place the user has never been.
  bool _hasFix = false;

  /// Set once the map has reported a camera event, which is the first point at
  /// which projecting a coordinate to a screen point gives a usable answer.
  ///
  /// iOS hands out `mapView.userLocation` from CoreLocation's cached fix, often
  /// within milliseconds of the platform view being created - long before the
  /// map view is laid out and the initial camera applied. Projecting then
  /// returns a point near the origin, which is what parked the marker in the
  /// top-left corner until the camera settled a few seconds later.
  bool _mapSettled = false;
  Timer? _settleTimer;

  // ignore: use_late_for_private_fields_and_variables
  Widget? _child;
  double _pulseSize = 0;
  LatLng? _location;
  Point<num>? _initialPosition;

  double get _iconSize => widget.iconSize;
  double lastBearing = 0;

  @override
  void didUpdateWidget(covariant UserLocationLayer oldWidget) {
    _updatePulseSize();

    if (_currentPosition == null) return;
    final location = LatLng(_currentPosition?.position.latitude ?? 0,
        _currentPosition?.position.longitude ?? 0);
    final currentTime = DateTime.now();
    _mapController.toScreenLocation(location).then((value) {
      print(currentTime.difference(DateTime.now()).inMilliseconds);
      if (mounted) {
        setState(() {
          _location = location;
          _initialPosition = value;
        });
      }
    });
    _mapController.toScreenLocationBatch([location]).then((value) async {
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      if (mounted) {
        setState(() {
          _location = location;
          _initialPosition = value.first;
        });
      }
    });
    super.didUpdateWidget(oldWidget);
  }

  Function()? onMapListener;
  Function(CameraPosition?)? onLocationMarkerListener;
  Function(UserLocation)? onUserLocationListener;

  @override
  void initState() {
    _updatePulseSize();
    _updateUserLocationWidget();
    onMapListener = () {
      _updatePulseSize();
      _updateUserLocationPosition();
      _updateUserLocationWidget();
    };
    onLocationMarkerListener = (cameraPosition) {
      _markMapSettled();
      _updateUserLocationPosition();
    };
    _mapController.getPlatform.onCameraIdlePlatform
        .add(onLocationMarkerListener!);
    _mapController.addListener(onMapListener!);
    onUserLocationListener = (event) {
      _currentPosition = event;
      if (_currentPosition == null) return;
      _onFirstFix();

      _placeMarkerAt(LatLng(_currentPosition?.position.latitude ?? 0,
          _currentPosition?.position.longitude ?? 0));
      _updatePulseSize();
      _updateUserLocationPosition();
      _updateUserLocationWidget();
    };
    _mapController.getPlatform.onUserLocationUpdatedPlatform
        .add(onUserLocationListener!);
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _requestInitialFix());
  }

  /// Records the first position and arms the fallback that releases the marker
  /// even if the map never emits a camera event.
  void _onFirstFix() {
    if (_hasFix) return;
    _hasFix = true;
    if (!_mapSettled) {
      _settleTimer = Timer(_settleFallback, _markMapSettled);
    }
  }

  void _markMapSettled() {
    if (_mapSettled) return;
    _mapSettled = true;
    _settleTimer?.cancel();
    _settleTimer = null;

    // Re-project now that the map is on screen: the point stored before this
    // was computed against a viewport that was not laid out yet.
    final position = _currentPosition?.position;
    if (position != null) {
      _placeMarkerAt(position);
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Polls the platform for the last known position until one arrives.
  ///
  /// Returning null is the normal answer while the map is still setting itself
  /// up, so a single attempt - which is what this used to do - almost always
  /// came back empty and left the layer with no position at all.
  Future<void> _requestInitialFix() async {
    for (var attempt = 0; attempt < _initialLocationAttempts; attempt++) {
      if (!mounted || _hasFix) return;

      LatLng? currentLatLng;
      try {
        currentLatLng = await _mapController.requestMyLocationLatLng();
      } catch (_) {
        // Platform side refused (permission revoked, location off). Keep the
        // marker hidden; live updates may still arrive later.
        return;
      }
      if (!mounted || _hasFix) return;

      if (currentLatLng != null) {
        _onFirstFix();
        setState(() {
          _currentPosition = UserLocation(
              position: currentLatLng!,
              altitude: 0,
              bearing: 0,
              speed: 0,
              horizontalAccuracy: 0,
              verticalAccuracy: 0,
              timestamp: DateTime.now(),
              heading: null);
        });
        await _placeMarkerAt(currentLatLng);
        return;
      }
      await Future.delayed(_initialLocationRetryDelay);
    }
  }

  Future<void> _placeMarkerAt(LatLng location) async {
    final points = await _mapController.toScreenLocationBatch([location]);
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    if (!mounted || points.isEmpty) return;
    setState(() {
      _location = location;
      _initialPosition = points.first;
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _mapController.getPlatform.onCameraIdlePlatform
        .remove(onLocationMarkerListener!);
    // Was never de-registered before, so every visit to a page using this layer
    // left another live callback on the platform instance.
    if (onUserLocationListener != null) {
      _mapController.getPlatform.onUserLocationUpdatedPlatform
          .remove(onUserLocationListener!);
    }
    _mapController.removeListener(onMapListener!);
    super.dispose();
  }

  void _updateUserLocationPosition() {
    final coordinates = <LatLng>[];

    if (_positionMarkerStates != null) {
      coordinates.add(_positionMarkerStates!.getCoordinate());
    }

    _mapController.toScreenLocationBatch(coordinates).then((points) async {
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      if (points.isEmpty || _positionMarkerStates == null) return;
      _positionMarkerStates!.updatePosition(
          points.first,
          _getRotateAngle(_currentPosition?.heading?.trueHeading ??
              _currentPosition?.bearing ??
              0));
    });
  }

  /// this function return the angle of the marker relative to the map.ß
  /// which present the angle of user and angle of the map to north pole
  /// [bearing] is the angle of the marker relative to the north pole
  /// [(_mapController.cameraPosition?.bearing ?? 0)] is the angle of the map relative to the north pole
  double _getRotateAngle(double bearing) {
    /// The modulo operation (% 360.0) ensures that the resulting angle is in the range [0, 360).
    /// The Transform.rotate widget takes the rotation angle in radians, so we
    /// need to convert the angle from degrees to radians by multiplying it by [(pi / 180.0).]
    ///
    /// [bearing - (_mapController.cameraPosition?.bearing ?? 0)] is the angle of the marker relative to the map.
    /// which present the angle of user and angle of the map to north pole

    return ((bearing - (_mapController.cameraPosition?.bearing ?? 0)) % 360) *
        pi /
        180;
  }

  _updatePulseSize() {
    var width = _currentPosition?.horizontalAccuracy ?? 0;
    final height = _currentPosition?.verticalAccuracy ?? 0;
    // max of width and height
    width = max(width, height);
    final zoomLevel = _mapController.cameraPosition?.zoom ?? 0;
    // convert from meter to pixel with zoom level

    if (mounted) {
      setState(() {
        _pulseSize = width / 38543 * pow(2, zoomLevel);
      });
    }
  }

  Widget _updateUserLocationWidget() {
    if (widget.locationIcon != null && widget.bearingIcon != null) {
      _child = SizedBox(
        width: _iconSize,
        height: _iconSize,
        child: IgnorePointer(
          ignoring: widget.ignorePointer ?? true,
          child: Stack(
            alignment: AlignmentDirectional.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  size: Size(_pulseSize, _pulseSize),
                  painter: CirclePainter(
                    radius: _pulseSize / 2,
                    color: widget.pulseColor
                        .withAlpha((widget.pulseOpacity * 255).round()),
                  ),
                ),
              ),
              widget.locationIcon!,
              widget.bearingIcon!,
            ],
          ),
        ),
      );
    } else {
      _child = Stack(
        alignment: AlignmentDirectional.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _iconSize,
            height: _iconSize,
            decoration: BoxDecoration(
                color: Colors.blue,
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(100)),
          ),
          // draw a bearing angle icon with a triangle anchor is 60
          Container(
              width: _iconSize,
              height: _iconSize,
              decoration: BoxDecoration(
                  color: Colors.blue,
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(100)),
              child: const Icon(Icons.arrow_upward, color: Colors.white)),
        ],
      );
    }
    return _child!;
  }

  @override
  Widget build(BuildContext context) {
    return _hasFix &&
            _mapSettled &&
            _location != null &&
            _initialPosition != null
        ? MarkerWidget(
            key: 'vietmapLocationMarker2024',
            coordinate: _location!,
            initialPosition: _initialPosition!,
            angle: _getRotateAngle(_currentPosition?.bearing ??
                _currentPosition?.heading?.trueHeading ??
                0),
            addMarkerState: (_) {
              _positionMarkerStates = _;
            },
            tiltRotate: _mapController._cameraPosition?.tilt ?? 0,
            width: _iconSize,
            height: _iconSize,
            child: _updateUserLocationWidget())
        : const SizedBox.shrink();
  }
}

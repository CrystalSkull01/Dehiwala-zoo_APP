import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const ZooMapApp());
}

class ZooMapApp extends StatelessWidget {
  const ZooMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dehiwala Zoo Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const ZooMapScreen(),
    );
  }
}

class ZooMapScreen extends StatefulWidget {
  const ZooMapScreen({super.key});

  @override
  State<ZooMapScreen> createState() => _ZooMapScreenState();
}

class _ZooMapScreenState extends State<ZooMapScreen> {
  late final Future<ZooMapData> _mapDataFuture;

  @override
  void initState() {
    super.initState();
    _mapDataFuture = _loadMapData();
  }

  Future<ZooMapData> _loadMapData() async {
    // Load both local data files.
    final files = await Future.wait([
      rootBundle.loadString('assets/data/waypoints_flutter.json'),
      rootBundle.loadString('assets/data/recorded_route.geojson'),
    ]);

    // Read the named zoo locations.
    final waypointJson = jsonDecode(files[0]) as List<dynamic>;

    final waypoints = waypointJson.map((item) {
      return ZooWaypoint.fromJson(Map<String, dynamic>.from(item as Map));
    }).toList();

    // Read the recorded GPS route.
    final routeJson = jsonDecode(files[1]) as Map<String, dynamic>;

    final features = routeJson['features'] as List<dynamic>;
    final routes = <List<LatLng>>[];

    for (final feature in features) {
      final featureMap = Map<String, dynamic>.from(feature as Map);

      final geometry = Map<String, dynamic>.from(featureMap['geometry'] as Map);

      if (geometry['type'] != 'LineString') {
        continue;
      }

      final coordinates = geometry['coordinates'] as List<dynamic>;

      final points = coordinates.map((coordinate) {
        final values = coordinate as List<dynamic>;

        // GeoJSON stores longitude first, latitude second.
        return LatLng(
          (values[1] as num).toDouble(),
          (values[0] as num).toDouble(),
        );
      }).toList();

      if (points.length >= 2) {
        routes.add(points);
      }
    }

    return ZooMapData(waypoints: waypoints, routes: routes);
  }

  IconData _markerIcon(String category) {
    switch (category.toLowerCase()) {
      case 'animal':
        return Icons.pets;
      case 'facility':
        return Icons.place;
      default:
        return Icons.location_on;
    }
  }

  Color _markerColor(String category) {
    switch (category.toLowerCase()) {
      case 'animal':
        return Colors.green.shade700;
      case 'facility':
        return Colors.orange.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  void _showWaypointDetails(ZooWaypoint waypoint) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waypoint.name,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('Category: ${waypoint.category}'),
                Text(
                  'Latitude: '
                  '${waypoint.latitude.toStringAsFixed(6)}',
                ),
                Text(
                  'Longitude: '
                  '${waypoint.longitude.toStringAsFixed(6)}',
                ),
                if (waypoint.needsReview) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This location needs verification.',
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dehiwala Zoo Map'), centerTitle: true),
      body: FutureBuilder<ZooMapData>(
        future: _mapDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load the zoo map data.\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;

          return FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(6.8565, 79.8728),
              initialZoom: 17,
              minZoom: 12,
              maxZoom: 19,
            ),
            children: [
              // Geographic map background.
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/'
                    '{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.dehiwala_zoo_app',
              ),

              // GPS track. Each recorded segment stays separate.
              PolylineLayer(
                polylines: data.routes.map((route) {
                  return Polyline(
                    points: route,
                    color: Colors.blue,
                    strokeWidth: 4,
                  );
                }).toList(),
              ),

              // Named locations from the JSON file.
              MarkerLayer(
                markers: data.waypoints.map((waypoint) {
                  return Marker(
                    point: LatLng(waypoint.latitude, waypoint.longitude),
                    width: 48,
                    height: 48,
                    child: GestureDetector(
                      onTap: () => _showWaypointDetails(waypoint),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _markerColor(waypoint.category),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _markerIcon(waypoint.category),
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ZooMapData {
  final List<ZooWaypoint> waypoints;
  final List<List<LatLng>> routes;

  const ZooMapData({required this.waypoints, required this.routes});
}

class ZooWaypoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String category;
  final bool needsReview;

  const ZooWaypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.needsReview,
  });

  factory ZooWaypoint.fromJson(Map<String, dynamic> json) {
    return ZooWaypoint(
      id: json['id'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Unnamed location',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] as String? ?? 'other',
      needsReview: json['needsReview'] as bool? ?? false,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 1. On transforme le main en fonction asynchrone pour initialiser Supabase
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://fsaoggrkrdqdrwjjizwu.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZzYW9nZ3JrcmRxZHJ3amppend1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwMDMyODAsImV4cCI6MjA5MzU3OTI4MH0.ZYC6R0SC_q-c2qw0ar_We5CYRhCPJ1wTIlfWQNDY-CE',
  );

  runApp(const PetTrackerApp());
}

class PetTrackerApp extends StatelessWidget {
  const PetTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Liste qui va contenir nos vrais marqueurs
  List<Marker> _markers = [];
  bool _isLoading = true;

  // On garde un centre par défaut (Paris cette fois, par exemple)
  final LatLng _defaultCenter = const LatLng(48.8566, 2.3522);
  LatLng? _mapCenter;

  @override
  void initState() {
    super.initState();
    _fetchScans();
  }

  // 2. Fonction pour récupérer les données depuis Supabase
  Future<void> _fetchScans() async {
    try {
      final data = await Supabase.instance.client
          .from('scans')
          .select('latitude, longitude');

      if (data.isNotEmpty) {
        List<Marker> newMarkers = [];

        for (var scan in data) {
          // On passe par "num" qui accepte à la fois les int et les double, puis on convertit proprement
          final lat = (scan['latitude'] as num).toDouble();
          final lng = (scan['longitude'] as num).toDouble();

          newMarkers.add(
            Marker(
              point: LatLng(lat, lng),
              width: 50,
              height: 50,
              child: const Icon(
                Icons.location_on,
                color: Colors.red,
                size: 40,
              ),
            ),
          );
        }

        setState(() {
          _markers = newMarkers;
          _mapCenter = LatLng(
            (data[0]['latitude'] as num).toDouble(),
            (data[0]['longitude'] as num).toDouble()
          );
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération des scans : $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Position de mon animal', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Petit bouton pour rafraîchir manuellement la carte
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchScans();
            },
          )
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : FlutterMap(
            options: MapOptions(
              // On centre sur le point trouvé, ou sur le défaut si aucun point
              initialCenter: _mapCenter ?? _defaultCenter,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pettracker.app',
              ),
              MarkerLayer(
                markers: _markers,
              ),
            ],
          ),
    );
  }
}

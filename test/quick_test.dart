import 'dart:convert';
import 'package:http/http.dart' as http;

// Quick test for current server on port 8089
const baseUrl = 'http://localhost:8089';

Future<void> main() async {
  print('🧪 Quick Test - Server on port 8089\n');

  // Test 1: Health
  print('1️⃣  Testing health...');
  final health = await http.get(Uri.parse('$baseUrl/health'));
  if (health.statusCode == 200) {
    final data = jsonDecode(health.body);
    print('   ✅ Health OK - ${data['gtfs']['stops']} stops loaded\n');
  } else {
    print('   ❌ Health failed\n');
    return;
  }

  // Test 2: Nearby stops
  print('2️⃣  Testing nearby stops...');
  final nearby = await http.get(
    Uri.parse('$baseUrl/stops/nearby?lat=-17.3935&lon=-66.1570&maxResults=3'),
  );
  if (nearby.statusCode == 200) {
    final data = jsonDecode(nearby.body);
    print('   ✅ Found ${data['count']} stops nearby\n');
  }

  // Test 3: Plan route
  print('3️⃣  Testing route planning...');
  final plan = await http.post(
    Uri.parse('$baseUrl/plan'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'from': {'lat': -17.3935, 'lon': -66.1570},
      'to': {'lat': -17.4000, 'lon': -66.1600},
    }),
  );
  if (plan.statusCode == 200) {
    final data = jsonDecode(plan.body);
    if (data['success']) {
      final path = data['paths'][0];
      print('   ✅ Found ${data['count']} routes');
      print('   📍 First route: ${path['segments'][0]['route']['shortName']}');
      print('   🚶 Walk: ${path['totalWalk']}m');
      print('   🔄 Transfers: ${path['transfers']}\n');
    }
  }

  print('✅ All quick tests passed!');
}

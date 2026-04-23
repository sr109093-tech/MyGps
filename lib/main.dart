import 'dart:async';
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart';      
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:weather/weather.dart';
import 'package:intl/intl.dart';

// --- 1. 데이터베이스 매니저 (기존 구조 유지) ---
class DBHelper {
  static late Database _db;
  static Future<void> init() async {
    String path = p.join(await getDatabasesPath(), 'k_path_v17.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) {
      db.execute("CREATE TABLE records(id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT, type TEXT, distance REAL, date TEXT, duration TEXT, points TEXT)");
      db.execute("CREATE TABLE user(id TEXT PRIMARY KEY, name TEXT, age TEXT, height TEXT, weight TEXT, voice INTEGER, lang TEXT, photo TEXT)");
    });
  }
  static Future<List<Map<String, dynamic>>> getRecordsById(String userId) async => 
    await _db.query('records', where: 'userId = ?', whereArgs: [userId], orderBy: 'id DESC');
  static Future<void> deleteRecord(int id) async => await _db.delete('records', where: 'id = ?', whereArgs: [id]);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBHelper.init();
  runApp(const KPathApp());
}

class KPathApp extends StatelessWidget {
  const KPathApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false, 
      title: 'K-Path',
      home: KPathHomePage()
    );
  }
}

// --- 2. 메인 홈 화면 ---
class KPathHomePage extends StatefulWidget {
  const KPathHomePage({super.key});
  @override
  State<KPathHomePage> createState() => _KPathHomePageState();
}

class _KPathHomePageState extends State<KPathHomePage> {
  String _temp = "--°";
  String _weather = "GPS 확인 중";
  String _userId = "Guest"; 
  String _userName = "";
  String _userPhoto = ""; 
  String _currentLang = "한국어";
  int _totalCount = 0;
  double _totalDist = 0.0;
  final WeatherFactory wf = WeatherFactory("856822fd8e22db5e3ba37c0eec9ca94c");

  @override
  void initState() { super.initState(); _startUp(); }
  Future<void> _startUp() async { await [Permission.location, Permission.camera].request(); _refresh(); }
  
  Future<void> _refresh() async {
    var userList = await DBHelper._db.query('user', limit: 1); 
    if (userList.isNotEmpty) {
      var user = userList.first;
      setState(() {
        _userId = user['id'] as String;
        _userName = user['name'] as String? ?? "";
        _userPhoto = user['photo'] as String? ?? "";
        _currentLang = (user['lang'] as String?) ?? "한국어";
      });
      var res = await DBHelper._db.rawQuery("SELECT COUNT(*) as c, SUM(distance) as d FROM records WHERE userId = ?", [_userId]);
      setState(() {
        _totalCount = (res.first['c'] as int? ?? 0);
        _totalDist = (res.first['d'] as num? ?? 0.0) / 1000.0;
      });
    } else {
      setState(() { _userId = "Guest"; _userName = ""; _userPhoto = ""; });
    }
    _updateWeather();
  }
  
  Future<void> _updateWeather() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      Weather w = await wf.currentWeatherByLocation(pos.latitude, pos.longitude);
      setState(() { _temp = "${w.temperature?.celsius?.toStringAsFixed(1)}°"; _weather = "${w.weatherMain}"; });
    } catch (_) { setState(() => _weather = "실외 권장"); }
  }

  @override
  Widget build(BuildContext context) {
    bool isKor = _currentLang == "한국어";
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(children: [
              Expanded(child: Row(children: [_card(isKor ? "걷기" : "Walk", Icons.hiking, const Color(0xFFE57373)), _card(isKor ? "등산" : "Climb", Icons.terrain, const Color(0xFFFB8C00))])),
              Expanded(child: Row(children: [_card(isKor ? "자전거" : "Cycle", Icons.pedal_bike, const Color(0xFF9575CD)), _card(isKor ? "달리기" : "Run", Icons.run_circle_outlined, const Color(0xFF4CAF50))])),
            ]),
            Positioned(top: 20, left: 20, right: 20, child: Row(children: [
              Row(children: [
                CircleAvatar(
                  radius: 25, 
                  backgroundColor: Colors.white24, 
                  backgroundImage: (_userPhoto.isNotEmpty && File(_userPhoto).existsSync()) ? FileImage(File(_userPhoto)) : null, 
                  child: (_userPhoto.isEmpty || !File(_userPhoto).existsSync()) ? const Icon(Icons.person, color: Colors.white) : null
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("K-Path", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(_userId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  if(_userName.isNotEmpty) Text(_userName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ]),
              const Spacer(),
              IconButton(icon: const Icon(Icons.settings, color: Colors.white, size: 35), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage())).then((_) => _refresh())),
            ])),
            Center(child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(userId: _userId, lang: _currentLang))).then((_) => _refresh()),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("${_totalDist.toStringAsFixed(1)}km", style: const TextStyle(fontSize: 38, color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(isKor ? "$_totalCount 기록" : "$_totalCount Records", style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  const Divider(color: Colors.white24, indent: 45, endIndent: 45, height: 25),
                  Text(_temp, style: const TextStyle(fontSize: 28, color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  Text(_weather, style: const TextStyle(color: Colors.white60, fontSize: 14)),
                ]),
              ),
            )),
          ],
        ),
      ),
    );
  }
  Widget _card(String l, IconData i, Color c) => Expanded(child: GestureDetector(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ExercisePage(type: l, lang: _currentLang, userId: _userId))).then((_) => _refresh()),
    child: Container(color: c, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 90, color: Colors.white), Text(l, style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.bold))])),
  ));
}

// --- 3. 운동 페이지 (현재 위치 디폴트 및 지도선택 삭제) ---
class ExercisePage extends StatefulWidget {
  final String type; final String lang; final String userId;
  const ExercisePage({super.key, required this.type, required this.lang, required this.userId});
  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends State<ExercisePage> {
  final MapController _mapC = MapController();
  final List<LatLng> _points = [];
  // [수정] 초기 좌표를 임시로 설정하고, initState에서 현재 위치를 즉시 가져옴
  LatLng _loc = const LatLng(37.5665, 126.9780); 
  double _dist = 0; int _sec = 0; bool _active = false; StreamSubscription<Position>? _sub;

  @override
  void initState() { 
    super.initState(); 
    _initLoc(); // [수정] 시작하자마자 현재 위치로 지도를 이동
  }
  
  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  Future<void> _initLoc() async { 
    // [수정] 현재 위치를 즉시 가져와서 지도의 초기 중심으로 설정
    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high); 
    setState(() { 
      _loc = LatLng(p.latitude, p.longitude); 
      _mapC.move(_loc, 16); 
    }); 
  }
  
  void _start() {
    setState(() => _active = true);
    Timer.periodic(const Duration(seconds: 1), (t) { if(!_active) t.cancel(); else if(mounted) setState(() => _sec++); });
    _sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3)).listen((p) {
      LatLng pos = LatLng(p.latitude, p.longitude);
      if (mounted) { setState(() { if (_points.isNotEmpty) _dist += Geolocator.distanceBetween(_points.last.latitude, _points.last.longitude, pos.latitude, pos.longitude); _points.add(pos); _loc = pos; _mapC.move(pos, 16); }); }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isKor = widget.lang == "한국어";
    return Scaffold(
      body: Stack(children: [
        FlutterMap(mapController: _mapC, options: MapOptions(initialCenter: _loc, initialZoom: 16), children: [
          TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", userAgentPackageName: 'com.example.k_path_final'),
          PolylineLayer(polylines: [Polyline(points: _points, strokeWidth: 5, color: Colors.blue)]),
          MarkerLayer(markers: [Marker(point: _loc, child: const Icon(Icons.location_on, color: Colors.red, size: 45))]),
        ]),
        Positioned(top: 40, left: 15, right: 15, child: Container(padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(15)), 
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat(isKor ? "시간" : "Time", "${(_sec~/3600).toString().padLeft(2,'0')}:${((_sec%3600)~/60).toString().padLeft(2,'0')}:${(_sec%60).toString().padLeft(2,'0')}"),
            _stat(isKor ? "거리" : "Dist", "${(_dist/1000).toStringAsFixed(2)}km"),
            _stat(isKor ? "속도" : "Speed", "${(_dist/(_sec>0?_sec:1)*3.6).toStringAsFixed(1)}km/h"),
          ]))),
        // [수정] 지도선택(Layers) 탭 삭제
        Positioned(right: 15, top: 150, child: Column(children: [
          _fab(Icons.my_location, _initLoc), 
          const SizedBox(height: 12), 
          _fab(Icons.camera_alt, () async => await ImagePicker().pickImage(source: ImageSource.camera)),
        ])),
        Positioned(bottom: 60, left: 50, right: 50, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _active ? Colors.red : Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
          onPressed: () async {
            if(!_active) _start();
            else {
              String pts = _points.map((p) => "${p.latitude},${p.longitude}").join("|");
              await DBHelper._db.insert('records', {'userId': widget.userId, 'type': widget.type, 'distance': _dist, 'date': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()), 'duration': '$_sec', 'points': pts});
              Navigator.pop(context);
            }
          },
          child: Text(_active ? (isKor ? "운동 종료" : "Finish") : (isKor ? "시작하기" : "Start"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        )),
        Positioned(top: 45, left: 20, child: CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)))),
      ]),
    );
  }
  Widget _stat(String l, String v) => Column(children: [Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(v, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))]);
  Widget _fab(IconData i, VoidCallback o) => FloatingActionButton(heroTag: null, mini: true, onPressed: o, backgroundColor: Colors.white, child: Icon(i, color: Colors.black87));
}

// --- 4. 설정 페이지 (기능 유지) ---
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  bool _isVoiceOn = true; String _selectedLang = "한국어";
  @override
  void initState() { super.initState(); _loadSettings(); }
  void _loadSettings() async { var user = await DBHelper._db.query('user', limit: 1); if(user.isNotEmpty) setState(() { _isVoiceOn = user.first['voice'] == 1; _selectedLang = (user.first['lang'] as String?) ?? "한국어"; }); }
  @override
  Widget build(BuildContext context) {
    bool isKor = _selectedLang == "한국어";
    return Scaffold(
      appBar: AppBar(title: Text(isKor ? '설정' : 'Settings')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.group_add, color: Colors.blue), title: Text(isKor ? '이용자 관리/등록' : 'User Registration'), subtitle: Text(isKor ? '아이디 전환 및 신규 등록' : 'Switch or Add User'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UserProfilePage(lang: _selectedLang)))),
        SwitchListTile(secondary: const Icon(Icons.record_voice_over, color: Colors.purple), title: Text(isKor ? '음성 안내' : 'Voice Guide'), value: _isVoiceOn, onChanged: (v) async { await DBHelper._db.update('user', {'voice': v ? 1 : 0}); setState(() => _isVoiceOn = v); }),
        ListTile(leading: const Icon(Icons.language, color: Colors.teal), title: Text(isKor ? '언어 선택' : 'Language'), subtitle: Text(_selectedLang), trailing: DropdownButton<String>(value: _selectedLang, items: ["한국어", "English"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) async { if(v != null) { await DBHelper._db.update('user', {'lang': v}); setState(() => _selectedLang = v); } })),
        ListTile(leading: const Icon(Icons.security, color: Colors.green), title: Text(isKor ? '시스템 권한 설정' : 'System Permissions'), onTap: () => openAppSettings()),
      ]),
    );
  }
}

// --- 5. 이용자 등록/관리 페이지 ---
class UserProfilePage extends StatefulWidget {
  final String lang; const UserProfilePage({super.key, required this.lang});
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}
class _UserProfilePageState extends State<UserProfilePage> {
  final TextEditingController _id = TextEditingController(); final TextEditingController _name = TextEditingController(); final TextEditingController _age = TextEditingController(); final TextEditingController _height = TextEditingController(); final TextEditingController _weight = TextEditingController();
  String _photoPath = "";
  @override
  void initState() { super.initState(); _loadCurrent(); }
  void _loadCurrent() async {
    var user = await DBHelper._db.query('user', limit: 1);
    if(user.isNotEmpty) { var d = user.first; setState(() { _id.text = d['id']?.toString() ?? ""; _name.text = d['name']?.toString() ?? ""; _age.text = d['age']?.toString() ?? ""; _height.text = d['height']?.toString() ?? ""; _weight.text = d['weight']?.toString() ?? ""; _photoPath = d['photo']?.toString() ?? ""; }); }
  }
  Future<void> _pickImage() async { final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery); if (image != null) setState(() => _photoPath = image.path); }
  @override
  Widget build(BuildContext context) {
    bool isKor = widget.lang == "한국어";
    return Scaffold(appBar: AppBar(title: Text(isKor ? "이용자 관리" : "User Management")), body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
        GestureDetector(onTap: _pickImage, child: CircleAvatar(radius: 50, backgroundColor: Colors.grey[300], backgroundImage: _photoPath.isNotEmpty ? FileImage(File(_photoPath)) : null, child: _photoPath.isEmpty ? const Icon(Icons.camera_alt, size: 40) : null)),
        const SizedBox(height: 10), Text(isKor ? "사진 등록" : "Tap to upload photo"), const SizedBox(height: 20),
        _input(_id, isKor ? "사용자 아이디 (필수)" : "User ID (Unique)", Icons.account_circle), _input(_name, isKor ? "성명" : "Name", Icons.person), _input(_age, isKor ? "나이" : "Age", Icons.calendar_today, isNum: true), _input(_height, isKor ? "키 (cm)" : "Height (cm)", Icons.height, isNum: true), _input(_weight, isKor ? "체중 (kg)" : "Weight (kg)", Icons.monitor_weight, isNum: true),
        const SizedBox(height: 20),
        ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.blue, foregroundColor: Colors.white), onPressed: () async { if(_id.text.isEmpty) return; await DBHelper._db.insert('user', {'id': _id.text, 'name': _name.text, 'age': _age.text, 'height': _height.text, 'weight': _weight.text, 'voice': 1, 'lang': widget.lang, 'photo': _photoPath}, conflictAlgorithm: ConflictAlgorithm.replace); Navigator.pop(context); }, child: Text(isKor ? "저장 및 사용자 전환" : "Save & Switch User", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
    ])));
  }
  Widget _input(TextEditingController c, String l, IconData i, {bool isNum = false}) => Padding(padding: const EdgeInsets.only(bottom: 15), child: TextField(controller: c, keyboardType: isNum ? TextInputType.number : TextInputType.text, decoration: InputDecoration(prefixIcon: Icon(i), labelText: l, border: const OutlineInputBorder())));
}

// --- 6. 기록 페이지 / 상세 ---
class HistoryPage extends StatefulWidget {
  final String userId; final String lang;
  const HistoryPage({super.key, required this.userId, required this.lang});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}
class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    bool isKor = widget.lang == "한국어";
    return Scaffold(appBar: AppBar(title: Text(isKor ? '${widget.userId}의 기록' : '${widget.userId}\'s Records')), 
      body: FutureBuilder<List<Map<String, dynamic>>>(future: DBHelper.getRecordsById(widget.userId), builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, i) {
            var item = snapshot.data![i];
            return ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryDetailPage(record: item, lang: widget.lang))), leading: const Icon(Icons.directions_run, color: Colors.blue), title: Text("${item['type']} - ${((item['distance'] as double)/1000).toStringAsFixed(2)}km"), subtitle: Text("${item['date']}"), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async { await DBHelper.deleteRecord(item['id'] as int); setState(() {}); }));
          });
        }));
  }
}

// --- 7. 기록 상세 지도 화면 ---
class HistoryDetailPage extends StatelessWidget {
  final Map<String, dynamic> record; final String lang;
  const HistoryDetailPage({super.key, required this.record, required this.lang});
  @override
  Widget build(BuildContext context) {
    bool isKor = lang == "한국어"; List<LatLng> points = [];
    if (record['points'] != null && record['points'].toString().isNotEmpty) { 
      points = record['points'].toString().split('|').map((s) { 
        var latlng = s.split(','); return LatLng(double.parse(latlng[0]), double.parse(latlng[1])); 
      }).toList(); 
    }
    return Scaffold(
      appBar: AppBar(title: Text("${record['type']} ${isKor ? '상세' : 'Detail'}")), 
      body: Stack(children: [
        FlutterMap(options: MapOptions(initialCenter: points.isNotEmpty ? points.first : const LatLng(37.5665, 126.9780), initialZoom: 16), children: [ 
          TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", userAgentPackageName: 'com.example.k_path_final'), 
          if (points.isNotEmpty) PolylineLayer(polylines: [Polyline(points: points, strokeWidth: 5, color: Colors.blue)]), 
        ]),
        // [수정] 상세 화면 하단 기록바를 위로 올림 (bottom: 20 -> 50)
        Positioned(bottom: 50, left: 20, right: 20, child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [ 
          _info(isKor ? "시간" : "Time", "${(int.parse(record['duration'])~/60)}${isKor ? '분' : 'm'}"), 
          _info(isKor ? "거리" : "Dist", "${((record['distance'] as double)/1000).toStringAsFixed(2)}km"), 
          _info(isKor ? "날짜" : "Date", record['date'].toString().split(' ')[0]), 
        ]))),
    ]));
  }
  Widget _info(String l, String v) => Column(children: [Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(v, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))]);
}
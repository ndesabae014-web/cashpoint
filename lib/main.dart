import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_options.dart';

const gold = Color(0xFFD6B45A);
const bg = Color(0xFF101010);
const panel = Color(0xFF1D1D1D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CashPointApp());
}

class CashPointApp extends StatelessWidget {
  const CashPointApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CashPoint',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: gold, secondary: gold),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: gold),
      cardTheme: CardThemeData(color: panel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      useMaterial3: true,
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snap.data == null ? const LoginPage() : const HomePage();
    },
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  final name = TextEditingController();
  bool register = false, busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      if (register) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(), password: pass.text,
        );
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
          'name': name.text.trim(),
          'email': email.text.trim(),
          'points': 0,
          'level': 'Bronze',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(), password: pass.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Autentikasi gagal')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.workspace_premium, color: gold, size: 66),
          const SizedBox(height: 10),
          const Text('CASHPOINT', textAlign: TextAlign.center,
            style: TextStyle(color: gold, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 3)),
          const Text('EARN POINTS. GET REWARDS.', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, letterSpacing: 1)),
          const SizedBox(height: 32),
          if (register) TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama pengguna')),
          TextField(controller: email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 12),
          TextField(controller: pass, obscureText: true,
            decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(busy ? 'Mohon tunggu...' : register ? 'DAFTAR' : 'MASUK'),
          ),
          TextButton(
            onPressed: () => setState(() => register = !register),
            child: Text(register ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar'),
          ),
        ],
      )),
    )),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final functions = FirebaseFunctions.instance;

  Future<void> claim(String id) async {
    try {
      final call = functions.httpsCallable('claimMission');
      final result = await call.call({'missionId': id});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berhasil! +${result.data['points']} poin')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Misi gagal diklaim')),
      );
    }
  }

  Future<void> redeem(String id) async {
    try {
      await functions.httpsCallable('redeemReward').call({'rewardId': id});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permintaan penukaran dikirim ke admin.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Penukaran gagal')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      dashboard(),
      missions(),
      rewards(),
      profile(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('CASHPOINT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2))),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel, indicatorColor: gold.withOpacity(.18),
        selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'Misi'),
          NavigationDestination(icon: Icon(Icons.card_giftcard), label: 'Hadiah'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }

  Widget dashboard() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, snap) {
      final data = snap.data?.data() ?? {};
      final points = (data['points'] ?? 0) as num;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF4B3A15), Color(0xFF1E1B14)]),
            border: Border.all(color: gold.withOpacity(.6)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TOTAL POINT WALLET', style: TextStyle(color: Colors.white70, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text('${points.toStringAsFixed(0)} PTS',
              style: const TextStyle(fontSize: 34, color: gold, fontWeight: FontWeight.bold)),
            Text('Level ${data['level'] ?? 'Bronze'}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('Mulai kumpulkan poin', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        actionCard(Icons.flag, 'Misi Harian', 'Selesaikan misi dan dapatkan poin', () => setState(() => tab = 1)),
        actionCard(Icons.card_giftcard, 'Toko Hadiah', 'Tukarkan poin dengan hadiah', () => setState(() => tab = 2)),
      ]);
    },
  );

  Widget actionCard(IconData icon, String title, String subtitle, VoidCallback onTap) =>
    Card(child: ListTile(leading: Icon(icon, color: gold, size: 30), title: Text(title),
      subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap));

  Widget missions() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('missions').where('active', isEqualTo: true).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('Gagal memuat misi'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs;
      if (docs.isEmpty) return const Center(child: Text('Belum ada misi aktif'));
      return ListView(padding: const EdgeInsets.all(12), children: docs.map((d) {
        final m = d.data();
        return Card(child: ListTile(
          leading: const Icon(Icons.stars, color: gold),
          title: Text(m['title'] ?? 'Misi'),
          subtitle: Text('${m['description'] ?? ''}\n+${m['rewardPoints'] ?? 0} poin'),
          isThreeLine: true,
          trailing: FilledButton(onPressed: () => claim(d.id), child: const Text('Klaim')),
        ));
      }).toList());
    },
  );

  Widget rewards() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('rewards').where('active', isEqualTo: true).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('Gagal memuat hadiah'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs;
      if (docs.isEmpty) return const Center(child: Text('Belum ada hadiah'));
      return ListView(padding: const EdgeInsets.all(12), children: docs.map((d) {
        final r = d.data();
        return Card(child: ListTile(
          leading: const Icon(Icons.redeem, color: gold, size: 32),
          title: Text(r['name'] ?? 'Hadiah'),
          subtitle: Text('${r['description'] ?? ''}\n${r['pricePoints'] ?? 0} poin • Stok ${r['stock'] ?? 0}'),
          isThreeLine: true,
          trailing: FilledButton(onPressed: (r['stock'] ?? 0) > 0 ? () => redeem(d.id) : null,
            child: const Text('Tukar')),
        ));
      }).toList());
    },
  );

  Widget profile() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, snap) {
      final d = snap.data?.data() ?? {};
      return ListView(padding: const EdgeInsets.all(16), children: [
        const CircleAvatar(radius: 38, backgroundColor: gold, child: Icon(Icons.person, color: Colors.black, size: 42)),
        const SizedBox(height: 12),
        Center(child: Text(d['name'] ?? 'Member', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
        Center(child: Text(d['email'] ?? '', style: const TextStyle(color: Colors.white54))),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout), label: const Text('Keluar akun'),
        ),
      ]);
    },
  );
}

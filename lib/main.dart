import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ofmmfvxewspgxyckxguk.supabase.co',
    publishableKey: 'sb_publishable_6H5NhrwXsZgj01Wl1kWsgg_9MLfjIMK',
  );
  runApp(const DriveControlApp());
}

const enlaceAutenticacion = 'io.drivecontrol.app://login-callback/';

const verde = Color(0xFF32E548);
const fondo = Color(0xFF0B1113);
const tarjeta = Color(0xFF182226);


// Autenticación y autorización. El rol se lee de la base de datos, no del cliente.
class Acceso extends StatefulWidget {
  const Acceso({super.key});
  @override
  State<Acceso> createState() => _AccesoState();
}

class _AccesoState extends State<Acceso> {
  final cliente = Supabase.instance.client;
  late final Stream<AuthState> cambios;
  Future<bool>? verificacion;
  String? idVerificado;
  StreamSubscription<AuthState>? suscripcion;
  bool recuperando = false;
  @override
  void initState() {
    super.initState();
    cambios = cliente.auth.onAuthStateChange;
    suscripcion = cambios.listen((evento) {
      if (evento.event == AuthChangeEvent.signedOut || evento.event == AuthChangeEvent.signedIn) {
        verificacion = null;
        idVerificado = null;
        if (mounted) setState(() {});
      }
      if (evento.event == AuthChangeEvent.passwordRecovery && mounted) {
        setState(() => recuperando = true);
      }
    });
  }

  @override
  void dispose() {
    suscripcion?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => recuperando
    ? PantallaNuevaClave(alTerminar: () => setState(() => recuperando = false))
    : StreamBuilder<AuthState>(
    stream: cambios,
    builder: (context, snapshot) {
      final usuario = cliente.auth.currentUser;
      if (usuario == null) return const PantallaAutenticacion();
      if (idVerificado != usuario.id || verificacion == null) {
        idVerificado = usuario.id;
        verificacion = _esAdministrador(usuario.id);
      }
      return FutureBuilder<bool>(
        key: ValueKey(usuario.id),
        future: verificacion,
        builder: (context, resultado) {
          if (resultado.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (resultado.hasError) {
            return Scaffold(body: Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('No se pudo verificar tu perfil. Comprueba tu conexión.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => setState(() { verificacion = null; idVerificado = null; }), child: const Text('Reintentar')),
                TextButton(onPressed: () => cliente.auth.signOut(), child: const Text('Cerrar sesión')),
              ]),
            )));
          }
          return resultado.data == true ? const Principal() : const PantallaUsuario();
        },
      );
    },
  );

  Future<bool> _esAdministrador(String id) async {
    final perfil = await cliente.from('perfiles').select('rol').eq('id', id).maybeSingle();
    return perfil?['rol'] == 'admin';
  }
}

class PantallaNuevaClave extends StatefulWidget {
  const PantallaNuevaClave({super.key, required this.alTerminar});
  final VoidCallback alTerminar;
  @override
  State<PantallaNuevaClave> createState() => _PantallaNuevaClaveState();
}

class _PantallaNuevaClaveState extends State<PantallaNuevaClave> {
  final clave = TextEditingController();
  bool guardando = false;
  @override
  void dispose() { clave.dispose(); super.dispose(); }
  Future<void> actualizar() async {
    if (clave.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La contraseña debe tener al menos 6 caracteres')));
      return;
    }
    setState(() => guardando = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: clave.text));
      await Supabase.instance.client.auth.signOut();
      if (mounted) widget.alTerminar();
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Nueva contraseña', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      TextField(controller: clave, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña')),
      const SizedBox(height: 16),
      FilledButton(onPressed: guardando ? null : actualizar, child: const Text('Guardar contraseña')),
    ])),
  )));
}

class PantallaUsuario extends StatelessWidget {
  const PantallaUsuario({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DriveControl')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified_user_outlined, color: verde, size: 64),
        const SizedBox(height: 16),
        const Text('Sesión iniciada', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Tu cuenta está activa. El panel de administración es exclusivo del administrador.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: () => Supabase.instance.client.auth.signOut(),
          icon: const Icon(Icons.logout), label: const Text('Cerrar sesión')),
      ]),
    )),
  );
}

class PantallaAutenticacion extends StatefulWidget {
  const PantallaAutenticacion({super.key});
  @override
  State<PantallaAutenticacion> createState() => _PantallaAutenticacionState();
}

class _PantallaAutenticacionState extends State<PantallaAutenticacion> {
  final correo = TextEditingController();
  final clave = TextEditingController();
  final formulario = GlobalKey<FormState>();
  int modo = 0; // 0 iniciar, 1 registrarse, 2 recuperar
  bool cargando = false;
  bool ocultar = true;
  final cliente = Supabase.instance.client;

  @override
  void dispose() {
    correo.dispose();
    clave.dispose();
    super.dispose();
  }

  void aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> enviar() async {
    if (!(formulario.currentState?.validate() ?? false)) return;
    setState(() => cargando = true);
    try {
      final email = correo.text.trim();
      if (modo == 0) {
        await cliente.auth.signInWithPassword(email: email, password: clave.text);
      } else if (modo == 1) {
        final respuesta = await cliente.auth.signUp(
          email: email,
          password: clave.text,
          emailRedirectTo: enlaceAutenticacion,
        );
        if (respuesta.session == null) {
          aviso('Revisa tu correo y confirma tu cuenta para iniciar sesión.');
        } else {
          aviso('Cuenta creada correctamente.');
        }
      } else {
        await cliente.auth.resetPasswordForEmail(
          email,
          redirectTo: enlaceAutenticacion,
        );
        aviso('Si la cuenta existe, recibirás un correo para recuperar tu contraseña.');
      }
    } on AuthException catch (e) {
      aviso('No se pudo completar la operación: ${e.message}');
    } catch (_) {
      aviso('Error de conexión. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = ['Iniciar sesión', 'Crear cuenta', 'Recuperar contraseña'][modo];
    return Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Form(
        key: formulario,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.directions_car, color: verde, size: 64),
          const SizedBox(height: 12),
          const Text('DriveControl', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: verde)),
          const SizedBox(height: 30),
          Text(titulo, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          TextFormField(controller: correo, keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.email_outlined)),
            validator: (v) => v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
              ? 'Ingresa un correo válido' : null),
          if (modo != 2) ...[
            const SizedBox(height: 16),
            TextFormField(controller: clave, obscureText: ocultar,
              decoration: InputDecoration(labelText: 'Contraseña', prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(onPressed: () => setState(() => ocultar = !ocultar),
                  icon: Icon(ocultar ? Icons.visibility : Icons.visibility_off))),
              validator: (v) => v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: cargando ? null : enviar,
            style: FilledButton.styleFrom(backgroundColor: verde, foregroundColor: Colors.black,
              padding: const EdgeInsets.all(18)),
            child: cargando ? const SizedBox(height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2)) : Text(titulo)),
          const SizedBox(height: 12),
          if (modo == 0) ...[
            TextButton(onPressed: () => setState(() => modo = 1), child: const Text('¿No tienes cuenta? Regístrate')),
            TextButton(onPressed: () => setState(() => modo = 2), child: const Text('¿Olvidaste tu contraseña?')),
          ] else
            TextButton(onPressed: () => setState(() => modo = 0), child: const Text('Volver a iniciar sesión')),
        ]),
      )),
    ))));
  }
}

class Registro {
  const Registro({required this.id, required this.fecha, required this.ganado, required this.gasolina});
  final String id;
  final DateTime fecha;
  final double ganado;
  final double gasolina;
  double get neto => ganado - gasolina;

  factory Registro.desdeMapa(Map<String, dynamic> m) => Registro(
    id: m['id'].toString(),
    fecha: DateTime.parse(m['fecha'].toString()),
    ganado: (m['ganado'] as num).toDouble(),
    gasolina: (m['gasolina'] as num?)?.toDouble() ?? 0,
  );
}

String dinero(double n) => '\$${n.toStringAsFixed(2)}';
String fechaTexto(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String fechaSql(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class DriveControlApp extends StatelessWidget {
  const DriveControlApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DriveControl', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: fondo,
      colorScheme: ColorScheme.fromSeed(seedColor: verde, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: fondo, foregroundColor: Colors.white),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: tarjeta,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white24)),
      ),
    ),
    home: const Acceso(),
  );
}

class Principal extends StatefulWidget {
  const Principal({super.key});
  @override
  State<Principal> createState() => _PrincipalState();
}

class _PrincipalState extends State<Principal> {
  final cliente = Supabase.instance.client;
  List<Registro> registros = [];
  int pagina = 0;
  bool cargando = true;
  String? error;
  DateTime get hoy => DateTime.now();
  List<Registro> get deHoy => registros.where((r) => DateUtils.isSameDay(r.fecha, hoy)).toList();
  double suma(Iterable<Registro> datos) => datos.fold(0.0, (a, r) => a + r.ganado);
  double sumaGasolina(Iterable<Registro> datos) => datos.fold(0.0, (a, r) => a + r.gasolina);

  @override
  void initState() { super.initState(); cargar(); }

  Future<void> cargar() async {
    setState(() { cargando = true; error = null; });
    try {
      final id = cliente.auth.currentUser!.id;
      final datos = await cliente.from('registros')
          .select('id, fecha, ganado, gasolina').eq('usuario_id', id).order('fecha', ascending: false);
      if (!mounted) return;
      setState(() => registros = (datos as List)
          .map((e) => Registro.desdeMapa(e as Map<String, dynamic>)).toList());
    } catch (e) {
      if (mounted) setState(() => error = 'No se pudieron cargar los registros: $e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  void aviso(String texto) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> eliminar(Registro r) async {
    final confirmar = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Eliminar registro'),
      content: const Text('¿Quieres eliminar esta ganancia permanentemente?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
      ],
    ));
    if (confirmar != true || !mounted) return;
    try {
      await cliente.from('registros').delete().eq('id', r.id)
          .eq('usuario_id', cliente.auth.currentUser!.id);
      await cargar();
      aviso('Registro eliminado');
    } catch (e) { aviso('No se pudo eliminar: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.directions_car, color: verde), SizedBox(width: 10),
        Text('Drive', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Control', style: TextStyle(color: verde, fontWeight: FontWeight.bold))]),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: cargar, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'Cerrar sesión', onPressed: () => cliente.auth.signOut(), icon: const Icon(Icons.logout))]),
      body: SafeArea(child: cargando
        ? const Center(child: CircularProgressIndicator())
        : error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisSize: MainAxisSize.min, children: [Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16), FilledButton(onPressed: cargar, child: const Text('Reintentar'))])))
          : [inicio(), historial(), reportes()][pagina]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: tarjeta, indicatorColor: verde.withValues(alpha: 0.2),
        selectedIndex: pagina, onDestinationSelected: (i) => setState(() => pagina = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: verde), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history, color: verde), label: 'Historial'),
          NavigationDestination(icon: Icon(Icons.bar_chart), selectedIcon: Icon(Icons.bar_chart, color: verde), label: 'Reportes'),
        ],
      ),
    );
  }

  Widget panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: tarjeta, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
    child: child,
  );

  Widget inicio() {
    final ganado = suma(deHoy);
    final gasolina = sumaGasolina(deHoy);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Text('TU TRABAJO, TUS GANANCIAS', style: TextStyle(color: Colors.white60, letterSpacing: 2)),
      const SizedBox(height: 18),
      panel(child: Row(children: [const Icon(Icons.calendar_month, color: verde), const SizedBox(width: 12),
        const Text('Hoy: ', style: TextStyle(color: Colors.white70)), Text(fechaTexto(hoy))])),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF086B2A), Color(0xFF16BC38)]), borderRadius: BorderRadius.circular(20)),
        child: Column(children: [const Text('GANANCIA NETA DE HOY', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 14), Text(dinero(ganado - gasolina), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10), Text('${deHoy.length} registros realizados')]),
      ),
      const SizedBox(height: 16),
      panel(child: Row(children: [const Icon(Icons.monetization_on, color: verde, size: 30),
        const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total ganado hoy', style: TextStyle(color: Colors.white70)),
          Text(dinero(ganado), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]))])),
      const SizedBox(height: 12),
      panel(child: Row(children: [const Icon(Icons.local_gas_station, color: Colors.orange), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Gasolina de hoy', style: TextStyle(color: Colors.white70)), Text(dinero(gasolina), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]))])),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: abrirFormulario, icon: const Icon(Icons.add_circle_outline), label: const Text('Registrar ganancia'),
        style: FilledButton.styleFrom(backgroundColor: verde, foregroundColor: Colors.black, padding: const EdgeInsets.all(18))),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () => setState(() => pagina = 1), icon: const Icon(Icons.history), label: const Text('Ver historial')),
    ]);
  }

  Future<void> abrirFormulario() async {
    final guardado = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const FormularioRegistro()));
    if (!mounted) return;
    if (guardado == true) { await cargar(); aviso('Ganancia guardada correctamente'); }
  }

  Widget historial() {
    final ordenados = [...registros]..sort((a, b) => b.fecha.compareTo(a.fecha));
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Historial de registros', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      if (ordenados.isEmpty) panel(child: const Text('Todavía no tienes registros. Pulsa Inicio para agregar el primero.')),
      for (final r in ordenados) ...[
        panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(fechaTexto(r.fecha), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => eliminar(r), tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline, color: Colors.redAccent))]),
          Text('Ganado: ${dinero(r.ganado)}'),
          Text('Gasolina: ${dinero(r.gasolina)}'), const SizedBox(height: 8),
          Text('Ganancia neta: ${dinero(r.neto)}', style: const TextStyle(color: verde, fontSize: 18, fontWeight: FontWeight.bold)),
        ])), const SizedBox(height: 12),
      ],
    ]);
  }

  Widget reportes() {
    final ahora = hoy;
    final mes = registros.where((r) => r.fecha.year == ahora.year && r.fecha.month == ahora.month).toList();
    final ganado = suma(mes);
    final gasolina = sumaGasolina(mes);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Reportes mensuales', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Text('Mes ${ahora.month}/${ahora.year}', style: const TextStyle(color: Colors.white60)),
      const SizedBox(height: 20),
      panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('GANANCIA NETA DEL MES', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8), Text(dinero(ganado - gasolina), style: const TextStyle(color: verde, fontSize: 36, fontWeight: FontWeight.bold)),
      ])),
      const SizedBox(height: 14),
      panel(child: Column(children: [
        fila('Ingresos', dinero(ganado)), const Divider(),
        fila('Gasolina', dinero(gasolina)), const Divider(),
        fila('Ganancia neta', dinero(ganado - gasolina)), const Divider(),
        fila('Registros del mes', '${mes.length}'),
      ])),
      const SizedBox(height: 14),
      const Text('Estos resultados corresponden al mes actual.', style: TextStyle(color: Colors.white60)),
    ]);
  }

  Widget fila(String titulo, String valor) => Padding(padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [Expanded(child: Text(titulo)), Text(valor, style: const TextStyle(fontWeight: FontWeight.bold))]));
}

class FormularioRegistro extends StatefulWidget {
  const FormularioRegistro({super.key});
  @override
  State<FormularioRegistro> createState() => _FormularioRegistroState();
}

class _FormularioRegistroState extends State<FormularioRegistro> {
  final formKey = GlobalKey<FormState>();
  final ganado = TextEditingController();
  final gasolina = TextEditingController();
  DateTime fecha = DateTime.now();
  bool guardando = false;

  double? numero(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() { ganado.dispose(); gasolina.dispose(); super.dispose(); }

  Future<void> seleccionarFecha() async {
    final elegida = await showDatePicker(context: context, initialDate: fecha,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (elegida != null) setState(() => fecha = elegida);
  }

  Future<void> guardar() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => guardando = true);
    try {
      final cliente = Supabase.instance.client;
      await cliente.from('registros').insert({
        'usuario_id': cliente.auth.currentUser!.id,
        'fecha': fechaSql(fecha),
        'ganado': numero(ganado.text)!,
        'gasolina': gasolina.text.trim().isEmpty ? 0 : numero(gasolina.text)!, 
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
  setState(() => guardando = false);
}
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Registrar ganancia')),
    body: Form(key: formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
      OutlinedButton.icon(onPressed: guardando ? null : seleccionarFecha, icon: const Icon(Icons.calendar_today, color: verde),
        label: Text('Fecha: ${fechaTexto(fecha)}')),
      const SizedBox(height: 20),
      TextFormField(controller: ganado, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Dinero ganado en inDrive (\$)', prefixIcon: Icon(Icons.attach_money)),
        validator: (v) { final n = numero(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Ingresa un monto mayor que cero' : null; }),
      const SizedBox(height: 16),
      TextFormField(controller: gasolina, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Gasto en gasolina (opcional)', prefixIcon: Icon(Icons.local_gas_station), hintText: 'Si no gastaste, déjalo vacío'),
        validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = numero(v!); return n == null || !n.isFinite || n < 0 ? 'Ingresa un monto válido o déjalo vacío' : null; }),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: guardando ? null : guardar, icon: const Icon(Icons.save),
        label: Text(guardando ? 'Guardando...' : 'Guardar registro'),
        style: FilledButton.styleFrom(backgroundColor: verde, foregroundColor: Colors.black,
          padding: const EdgeInsets.all(18))),
    ])),
  );
}

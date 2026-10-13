import 'dart:convert';
import 'dart:io';

import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/controllers/places_controller.dart' show EstadoCarga;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, int code, {Map<String, String> h = const {}}) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json', ...h});

/// Servidor falso: usuarios y gastos en memoria según el contrato real.
MockClient _servidor({
  List<Map<String, dynamic>> gastos = const [],
  bool registroDuplicado = false,
  bool sinRed = false,
  int? falloListar,
}) {
  return MockClient((req) async {
    if (sinRed) throw const SocketException('sin red');
    final ruta = req.url.path;
    if (ruta == '/usuarios/' && req.method == 'POST') {
      final b = jsonDecode(req.body) as Map;
      if ((b['password'] as String).length < 8) {
        return _json({'detail': [{'type': 'string_too_short', 'loc': ['body', 'password'], 'msg': 'String should have at least 8 characters'}]}, 422);
      }
      if (registroDuplicado) return _json({'detail': 'El email ya está registrado'}, 400);
      return _json({'id': 1, 'email': b['email']}, 201);
    }
    if (ruta == '/usuarios/token') {
      expect(req.headers['content-type'], contains('application/x-www-form-urlencoded'));
      expect(req.bodyFields['username'], isNotEmpty);
      return _json({'access_token': 'tok', 'token_type': 'bearer'}, 200);
    }
    if (ruta == '/gastos/') {
      if (falloListar != null) return _json({'detail': 'x'}, falloListar);
      expect(req.headers['authorization'], 'Bearer tok');
      return _json(gastos, 200, h: {'x-total-count': '${gastos.length}'});
    }
    return _json({'detail': 'no existe'}, 404);
  });
}

void main() {
  setUp(() => Get.testMode = true);

  Future<GastosController> entrar(MockClient c, {String pass = 'clave-1234'}) async {
    final g = GastosController();
    await http.runWithClient(() => g.entrar('a@b.com', pass), () => c);
    return g;
  }

  test('usuario nuevo: registro -> login -> lista vacía', () async {
    final g = await entrar(_servidor());
    expect(g.sesionActiva.value, isTrue);
    expect(g.estado.value, EstadoCarga.exito);
    expect(g.gastos, isEmpty);
  });

  test('éxito: carga gastos y total desde X-Total-Count (monto entero o decimal)', () async {
    final g = await entrar(_servidor(gastos: [
      {'id': 1, 'descripcion': 'Almuerzo', 'monto': 6.5, 'categoria': 'comida', 'fecha': '2026-10-05'},
      {'id': 2, 'descripcion': 'Taxi', 'monto': 3, 'categoria': 'transporte', 'fecha': '2026-10-05'},
    ]));
    expect(g.gastos.length, 2);
    expect(g.totalEnServidor.value, 2);
    expect(g.gastos[1].monto, 3.0);
  });

  test('400 al registrar (correo existente) se ignora y sigue al login', () async {
    final g = await entrar(_servidor(registroDuplicado: true));
    expect(g.sesionActiva.value, isTrue);
  });

  test('422 al registrar: mensaje legible con el campo, sin sesión', () async {
    final g = await entrar(_servidor(), pass: 'abc');
    expect(g.sesionActiva.value, isFalse);
    expect(g.mensajeAuth.value, startsWith('Datos inválidos — password:'));
  });

  test('sin conexión: error legible y la sesión no se pierde', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
    expect(g.estado.value, EstadoCarga.error);
    expect(g.mensajeError.value, startsWith('No hay conexión con el servidor'));
    expect(g.sesionActiva.value, isTrue);
  });

  test('401 al listar: vuelve al formulario y explica por qué', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 401));
    expect(g.sesionActiva.value, isFalse);
    expect(g.mensajeAuth.value, startsWith('Tu sesión caducó'));
  });

  test('5xx: mensaje genérico', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 503));
    expect(g.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
  });
}
